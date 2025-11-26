import Foundation
import AppKit
import Combine
import ScreenCaptureKit
import UserNotifications
import os.log

/// Orchestrates the entire recording workflow
@MainActor
final class RecordingManager: ObservableObject {
    
    // MARK: - Logging
    
    private static let logger = Logger(subsystem: "com.meetingrecorder.AutoCallRecorder", category: "RecordingManager")
    
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
        Self.logger.notice("startMonitoring() called")
        appWatcher.startWatching()
        browserWatcher.startWatching()
        Self.logger.notice("Started monitoring for meeting apps")
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
    
    /// Start recording automatically (no prompts, with notification)
    func startRecordingAutomatic(displayID: UInt32, for app: WatchedApp) async {
        Self.logger.notice("startRecordingAutomatic() called for \(app.displayName) on display \(displayID)")
        
        guard state.isIdle else {
            Self.logger.error("Cannot start automatic recording - state is not idle: \(String(describing: self.state))")
            return
        }
        
        // Check permission first
        Self.logger.notice("Checking screen recording permission...")
        guard await screenCaptureManager.checkPermission() else {
            Self.logger.error("Screen recording permission DENIED")
            lastError = ScreenCaptureError.permissionDenied.localizedDescription
            showNotification(title: "Recording Failed", body: "Screen recording permission required. Please enable in System Settings.")
            return
        }
        Self.logger.notice("Screen recording permission granted ✓")
        
        do {
            // Start capture
            Self.logger.notice("Starting screen capture...")
            let tempURL = try await screenCaptureManager.startRecording(displayID: displayID)
            
            // Update state
            tempFileURL = tempURL
            recordingApp = app
            recordingStartTime = Date()
            state = .recording(app: app, displayID: displayID, startTime: Date())
            
            // Show notification
            showNotification(title: "Recording Started", body: "Recording \(app.displayName) meeting...")
            
            Self.logger.notice("🎬 Recording STARTED for \(app.displayName) - temp file: \(tempURL.path)")
            
        } catch {
            Self.logger.error("Failed to start recording: \(error.localizedDescription)")
            lastError = error.localizedDescription
            state = .idle
            showNotification(title: "Recording Failed", body: error.localizedDescription)
        }
    }
    
    /// Start recording on the specified display (manual mode with prompts)
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
                
                // Fully automatic mode - auto-save without prompts
                if preferencesManager.fullyAutomatic {
                    let filename = generateFilename(for: app, startTime: startTime)
                    let destinationURL = preferencesManager.defaultSaveFolder.appendingPathComponent(filename)
                    
                    // Ensure directory exists
                    try? FileManager.default.createDirectory(at: preferencesManager.defaultSaveFolder, withIntermediateDirectories: true)
                    
                    // Remove existing file if any
                    try? FileManager.default.removeItem(at: destinationURL)
                    
                    // Move temp file to destination
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    
                    showNotification(title: "Recording Saved", body: "Saved: \(filename)")
                    print("RecordingManager: Auto-saved recording to \(destinationURL.path)")
                    
                    cleanup()
                } else {
                    // Manual mode - show save dialog
                    state = .saving(tempFileURL: tempURL, app: app, startTime: startTime)
                    showingSaveDialog = true
                    print("RecordingManager: Recording stopped, ready to save")
                }
            } else {
                state = .idle
                print("RecordingManager: Recording stopped but no file produced")
            }
        } catch {
            lastError = error.localizedDescription
            state = .idle
            showNotification(title: "Save Failed", body: error.localizedDescription)
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
                self?.handleAppDetected(app, detectedDisplayID: nil)
            }
        }
        
        // Handle native app terminations
        appWatcher.onWatchedAppTerminated = { [weak self] app in
            Task { @MainActor in
                await self?.handleAppTerminated(app)
            }
        }
        
        // Handle Google Meet detection (with display ID from browser window)
        browserWatcher.onGoogleMeetDetected = { [weak self] displayID in
            Task { @MainActor in
                self?.handleAppDetected(.googleMeet, detectedDisplayID: displayID)
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
    
    private func handleAppDetected(_ app: WatchedApp, detectedDisplayID: CGDirectDisplayID?) {
        Self.logger.notice("handleAppDetected() called for: \(app.displayName), detectedDisplayID: \(detectedDisplayID ?? 0)")
        
        // Ignore if already recording
        guard state.isIdle else {
            Self.logger.error("Ignoring \(app.displayName) - already recording (state: \(String(describing: self.state)))")
            return
        }
        
        // Check if this app is being watched
        guard preferencesManager.isWatching(app) else {
            Self.logger.error("\(app.displayName) is not being watched in preferences")
            return
        }
        
        Self.logger.notice("✓ \(app.displayName) detected and is being watched")
        Self.logger.notice("fullyAutomatic mode: \(self.preferencesManager.fullyAutomatic)")
        
        // Fully automatic mode - just start recording
        if preferencesManager.fullyAutomatic {
            Task {
                // Priority: detected display > remembered display > main display > first display
                let displayID: UInt32
                if let detected = detectedDisplayID {
                    Self.logger.notice("Using detected display (where browser window is): \(detected)")
                    displayID = detected
                } else if let remembered = preferencesManager.rememberedDisplay(for: app) {
                    Self.logger.notice("Using remembered display: \(remembered)")
                    displayID = remembered
                } else if let mainDisplay = DisplayInfo.allDisplays().first(where: { $0.isMain }) {
                    Self.logger.notice("Using main display: \(mainDisplay.id)")
                    displayID = mainDisplay.id
                } else if let firstDisplay = DisplayInfo.allDisplays().first {
                    Self.logger.notice("Using first display: \(firstDisplay.id)")
                    displayID = firstDisplay.id
                } else {
                    Self.logger.error("No displays found - cannot record!")
                    return
                }
                
                Self.logger.notice("Starting automatic recording on display \(displayID)...")
                await startRecordingAutomatic(displayID: displayID, for: app)
            }
            return
        }
        
        // Manual mode - check for remembered display
        if let rememberedDisplayID = preferencesManager.rememberedDisplay(for: app) {
            Self.logger.notice("Manual mode: using remembered display \(rememberedDisplayID)")
            // Use remembered display directly
            Task {
                await startRecording(displayID: rememberedDisplayID, for: app, rememberChoice: false)
            }
        } else {
            Self.logger.notice("Manual mode: showing screen selection dialog")
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
    
    /// Show a system notification
    private func showNotification(title: String, body: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            
            // Request permission if needed
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else { return }
            } catch {
                print("Notification permission error: \(error)")
                return
            }
            
            // Create notification content
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            
            // Create request
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil // Deliver immediately
            )
            
            try? await center.add(request)
        }
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

