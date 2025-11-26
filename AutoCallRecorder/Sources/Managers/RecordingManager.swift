import Foundation
import AppKit
import Combine
import ScreenCaptureKit

/// Orchestrates the entire recording workflow
@MainActor
final class RecordingManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published var showingScreenSelection = false
    @Published var showingSaveDialog = false
    @Published var pendingApp: WatchedApp?
    @Published var lastError: String?
    
    // MARK: - Dependencies
    
    var appWatcher: AppWatcher!
    var browserWatcher: BrowserWatcher!
    var screenCaptureManager: ScreenCaptureManager!
    let preferencesManager: PreferencesManager
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var tempFileURL: URL?
    private var recordingApp: WatchedApp?
    private var recordingStartTime: Date?
    
    // MARK: - Initialization
    
    init(
        preferencesManager: PreferencesManager
    ) {
        self.preferencesManager = preferencesManager
        self.appWatcher = AppWatcher()
        self.browserWatcher = BrowserWatcher()
        self.screenCaptureManager = ScreenCaptureManager()
        
        // Configure managers with preferences
        self.appWatcher.configure(preferencesManager: preferencesManager)
        self.browserWatcher.configure(preferencesManager: preferencesManager)
        
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring for meeting apps
    func startMonitoring() {
        appWatcher.startWatching()
        browserWatcher.startWatching()
        print("RecordingManager: Started monitoring for meeting apps")
    }
    
    /// Stop monitoring
    func stopMonitoring() {
        appWatcher.stopWatching()
        browserWatcher.stopWatching()
        print("RecordingManager: Stopped monitoring")
    }
    
    /// Check if screen recording permission is granted
    func checkPermission() async -> Bool {
        return await screenCaptureManager.checkPermission()
    }
    
    /// Start recording on the specified display
    func startRecording(displayID: CGDirectDisplayID, for app: WatchedApp, rememberChoice: Bool) async {
        guard state.isIdle || state == .awaitingUserChoice(app: app) else {
            print("RecordingManager: Cannot start recording, current state: \(state)")
            return
        }
        
        // Check permission first
        guard await screenCaptureManager.checkPermission() else {
            lastError = ScreenCaptureError.permissionDenied.localizedDescription
            showPermissionAlert()
            return
        }
        
        // Remember choice if requested
        if rememberChoice {
            preferencesManager.rememberDisplay(displayID, for: app)
        }
        
        do {
            // Start capture
            let tempURL = try await screenCaptureManager.startRecording(displayID: displayID)
            
            // Update state
            tempFileURL = tempURL
            recordingApp = app
            recordingStartTime = Date()
            state = .recording(app: app, displayID: displayID, startTime: Date())
            
            print("RecordingManager: Recording started for \(app.displayName)")
            
        } catch {
            lastError = error.localizedDescription
            state = .idle
            print("RecordingManager: Failed to start recording: \(error)")
        }
        
        showingScreenSelection = false
    }
    
    /// Stop the current recording
    func stopRecording() async {
        guard state.isRecording else {
            print("RecordingManager: Not recording, nothing to stop")
            return
        }
        
        guard let app = recordingApp, let startTime = recordingStartTime else { return }
        
        do {
            if let tempURL = try await screenCaptureManager.stopRecording() {
                tempFileURL = tempURL
                state = .saving(tempFileURL: tempURL, app: app, startTime: startTime)
                showingSaveDialog = true
                print("RecordingManager: Recording stopped, ready to save")
            } else {
                state = .idle
                print("RecordingManager: Recording stopped but no file produced")
            }
        } catch {
            lastError = error.localizedDescription
            state = .idle
            print("RecordingManager: Error stopping recording: \(error)")
        }
        
        // Reset watchers so they can detect new sessions
        appWatcher.resetPromptedApps()
        browserWatcher.resetSession()
    }
    
    /// Handle save action from save dialog
    func saveRecording(to destinationURL: URL) async -> Bool {
        guard case .saving(let tempURL, _, _) = state else {
            return false
        }
        
        do {
            // Ensure destination directory exists
            let directory = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            
            // Remove existing file if any
            try? FileManager.default.removeItem(at: destinationURL)
            
            // Move temp file to destination
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            
            print("RecordingManager: Recording saved to \(destinationURL.path)")
            
            cleanup()
            return true
            
        } catch {
            lastError = "Failed to save recording: \(error.localizedDescription)"
            print("RecordingManager: Failed to save: \(error)")
            return false
        }
    }
    
    /// Discard the recording
    func discardRecording() {
        guard case .saving(let tempURL, _, _) = state else { return }
        
        do {
            try FileManager.default.removeItem(at: tempURL)
            print("RecordingManager: Recording discarded")
        } catch {
            print("RecordingManager: Failed to delete temp file: \(error)")
        }
        
        cleanup()
    }
    
    /// Keep the recording with auto-generated name
    func keepRecording() async -> Bool {
        guard case .saving(_, let app, let startTime) = state else {
            return false
        }
        
        let filename = generateFilename(for: app, startTime: startTime)
        let destinationURL = preferencesManager.defaultSaveFolder.appendingPathComponent(filename)
        
        return await saveRecording(to: destinationURL)
    }
    
    /// Cancel the screen selection dialog
    func cancelScreenSelection() {
        showingScreenSelection = false
        pendingApp = nil
        state = .idle
    }
    
    /// Get suggested filename for save dialog
    func suggestedFilename() -> String {
        guard case .saving(_, let app, let startTime) = state else {
            return "Recording.mov"
        }
        return generateFilename(for: app, startTime: startTime)
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Handle native app launches
        appWatcher.onWatchedAppLaunched = { [weak self] app in
            Task { @MainActor in
                self?.handleAppDetected(app)
            }
        }
        
        // Handle native app terminations
        appWatcher.onWatchedAppTerminated = { [weak self] app in
            Task { @MainActor in
                await self?.handleAppTerminated(app)
            }
        }
        
        // Handle Google Meet detection
        browserWatcher.onGoogleMeetDetected = { [weak self] in
            Task { @MainActor in
                self?.handleAppDetected(.googleMeet)
            }
        }
        
        // Handle Google Meet ended
        browserWatcher.onGoogleMeetEnded = { [weak self] in
            Task { @MainActor in
                await self?.handleAppTerminated(.googleMeet)
            }
        }
        
        // Bind recording duration
        screenCaptureManager.$recordingDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$recordingDuration)
    }
    
    private func handleAppDetected(_ app: WatchedApp) {
        // Ignore if already recording
        guard state.isIdle else {
            print("RecordingManager: Ignoring \(app.displayName), already recording")
            return
        }
        
        // Check if this app is being watched
        guard preferencesManager.isWatching(app) else {
            print("RecordingManager: \(app.displayName) not being watched")
            return
        }
        
        print("RecordingManager: Detected \(app.displayName)")
        
        // Check for remembered display
        if let rememberedDisplayID = preferencesManager.rememberedDisplay(for: app) {
            // Use remembered display directly
            Task {
                await startRecording(displayID: rememberedDisplayID, for: app, rememberChoice: false)
            }
        } else {
            // Show screen selection dialog
            pendingApp = app
            state = .awaitingUserChoice(app: app)
            showingScreenSelection = true
        }
    }
    
    private func handleAppTerminated(_ app: WatchedApp) async {
        // Only stop if we're recording this specific app
        guard case .recording(let recordingApp, _, _) = state,
              recordingApp == app || 
              (recordingApp == .teamsNew && app == .teamsLegacy) ||
              (recordingApp == .teamsLegacy && app == .teamsNew) else {
            return
        }
        
        print("RecordingManager: \(app.displayName) terminated, stopping recording")
        await stopRecording()
    }
    
    private func cleanup() {
        state = .idle
        tempFileURL = nil
        recordingApp = nil
        recordingStartTime = nil
        showingSaveDialog = false
        pendingApp = nil
    }
    
    private func generateFilename(for app: WatchedApp, startTime: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: startTime)
        return "\(app.shortName)-\(timestamp).mov"
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "AutoCallRecorder needs screen recording permission to capture your meetings. Please enable it in System Settings > Privacy & Security > Screen Recording."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Open System Settings to Privacy & Security > Screen Recording
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

