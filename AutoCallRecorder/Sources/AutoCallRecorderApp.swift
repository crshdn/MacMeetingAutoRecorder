import SwiftUI
import AppKit

@main
struct AutoCallRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Menu bar only - no main window
        MenuBarExtra {
            MenuBarContentView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
        
        // Settings window (opened via Preferences)
        Settings {
            PreferencesView(preferencesManager: .shared)
        }
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    @ObservedObject private var recordingManager = AppState.shared.recordingManager
    
    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.hierarchical)
    }
    
    private var iconName: String {
        if recordingManager.state.isRecording {
            return "record.circle.fill"
        } else {
            return "record.circle"
        }
    }
}

// MARK: - Menu Bar Content

struct MenuBarContentView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var recordingManager = AppState.shared.recordingManager
    
    var body: some View {
        MenuBarView(
            recordingManager: recordingManager,
            preferencesManager: appState.preferencesManager
        )
        .sheet(isPresented: $recordingManager.showingScreenSelection) {
            ScreenSelectionView(recordingManager: recordingManager)
        }
        .sheet(isPresented: $recordingManager.showingSaveDialog) {
            SaveDialogView(recordingManager: recordingManager)
        }
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    let preferencesManager: PreferencesManager
    let recordingManager: RecordingManager
    
    private init() {
        let prefs = PreferencesManager.shared
        self.preferencesManager = prefs
        self.recordingManager = RecordingManager(preferencesManager: prefs)
    }
    
    func startMonitoring() {
        recordingManager.startMonitoring()
    }
    
    func stopMonitoring() {
        recordingManager.stopMonitoring()
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var screenSelectionWindow: NSWindow?
    private var saveDialogWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Start monitoring for meeting apps
        Task { @MainActor in
            AppState.shared.startMonitoring()
        }
        
        // Set up window observers
        setupWindowObservers()
        
        print("AutoCallRecorder: App launched")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Stop any active recording
        Task { @MainActor in
            if AppState.shared.recordingManager.state.isRecording {
                await AppState.shared.recordingManager.stopRecording()
            }
            AppState.shared.stopMonitoring()
        }
        
        print("AutoCallRecorder: App terminating")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Don't reopen windows when clicking dock icon
        return false
    }
    
    private func setupWindowObservers() {
        // Observe when screen selection should be shown
        Task { @MainActor in
            let recordingManager = AppState.shared.recordingManager
            
            // Watch for screen selection dialog
            for await showingScreenSelection in recordingManager.$showingScreenSelection.values {
                if showingScreenSelection && screenSelectionWindow == nil {
                    showScreenSelectionWindow()
                } else if !showingScreenSelection {
                    closeScreenSelectionWindow()
                }
            }
        }
        
        Task { @MainActor in
            let recordingManager = AppState.shared.recordingManager
            
            // Watch for save dialog
            for await showingSaveDialog in recordingManager.$showingSaveDialog.values {
                if showingSaveDialog && saveDialogWindow == nil {
                    showSaveDialogWindow()
                } else if !showingSaveDialog {
                    closeSaveDialogWindow()
                }
            }
        }
    }
    
    @MainActor
    private func showScreenSelectionWindow() {
        let contentView = ScreenSelectionView(recordingManager: AppState.shared.recordingManager)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Start Recording"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        screenSelectionWindow = window
    }
    
    private func closeScreenSelectionWindow() {
        screenSelectionWindow?.close()
        screenSelectionWindow = nil
    }
    
    @MainActor
    private func showSaveDialogWindow() {
        let contentView = SaveDialogView(recordingManager: AppState.shared.recordingManager)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Save Recording"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        saveDialogWindow = window
    }
    
    private func closeSaveDialogWindow() {
        saveDialogWindow?.close()
        saveDialogWindow = nil
    }
}

