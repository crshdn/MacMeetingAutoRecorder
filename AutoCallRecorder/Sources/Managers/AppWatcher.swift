import Foundation
import AppKit
import Combine

/// Monitors for launch and termination of watched meeting applications
@MainActor
final class AppWatcher: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Currently running watched apps (by bundle ID)
    @Published private(set) var runningWatchedApps: Set<String> = []
    
    /// Apps we've already shown the dialog for in this session
    @Published private(set) var promptedApps: Set<String> = []
    
    // MARK: - Callbacks
    
    /// Called when a watched app is launched (first activation)
    var onWatchedAppLaunched: ((WatchedApp) -> Void)?
    
    /// Called when a watched app terminates
    var onWatchedAppTerminated: ((WatchedApp) -> Void)?
    
    // MARK: - Private Properties
    
    private var workspaceNotificationObservers: [NSObjectProtocol] = []
    private var preferencesManager: PreferencesManager!
    
    // MARK: - Initialization
    
    init(preferencesManager: PreferencesManager? = nil) {
        self.preferencesManager = preferencesManager
    }
    
    func configure(preferencesManager: PreferencesManager) {
        self.preferencesManager = preferencesManager
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring for watched apps
    func startWatching() {
        stopWatching() // Clean up any existing observers
        
        let workspace = NSWorkspace.shared
        let notificationCenter = workspace.notificationCenter
        
        // Check currently running apps
        checkRunningApps()
        
        // Watch for app launches
        let launchObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: workspace,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAppLaunch(notification)
            }
        }
        workspaceNotificationObservers.append(launchObserver)
        
        // Watch for app terminations
        let terminateObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: workspace,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAppTermination(notification)
            }
        }
        workspaceNotificationObservers.append(terminateObserver)
        
        // Watch for app activations (to detect first-time focus)
        let activateObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: workspace,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAppActivation(notification)
            }
        }
        workspaceNotificationObservers.append(activateObserver)
        
        print("AppWatcher: Started watching for meeting apps")
    }
    
    /// Stop monitoring
    func stopWatching() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceNotificationObservers {
            notificationCenter.removeObserver(observer)
        }
        workspaceNotificationObservers.removeAll()
        print("AppWatcher: Stopped watching")
    }
    
    /// Reset prompted apps (e.g., after a recording ends)
    func resetPromptedApps() {
        promptedApps.removeAll()
    }
    
    /// Mark an app as prompted (to avoid re-prompting)
    func markAsPrompted(_ bundleID: String) {
        promptedApps.insert(bundleID)
    }
    
    // MARK: - Private Methods
    
    /// Check which watched apps are currently running
    private func checkRunningApps() {
        let runningApps = NSWorkspace.shared.runningApplications
        let watchedBundleIDs = preferencesManager.watchedBundleIdentifiers()
        
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            if watchedBundleIDs.contains(bundleID) {
                runningWatchedApps.insert(bundleID)
            }
        }
        
        print("AppWatcher: Currently running watched apps: \(runningWatchedApps)")
    }
    
    /// Handle app launch notification
    private func handleAppLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        
        let watchedBundleIDs = preferencesManager.watchedBundleIdentifiers()
        guard watchedBundleIDs.contains(bundleID) else { return }
        
        print("AppWatcher: Watched app launched: \(bundleID)")
        runningWatchedApps.insert(bundleID)
    }
    
    /// Handle app activation notification
    private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        
        guard let prefs = preferencesManager else { return }
        let watchedBundleIDs = prefs.watchedBundleIdentifiers()
        guard watchedBundleIDs.contains(bundleID) else { return }
        
        // Only trigger if we haven't already prompted for this app
        guard !promptedApps.contains(bundleID) else {
            print("AppWatcher: Already prompted for \(bundleID), ignoring activation")
            return
        }
        
        // Check if this app was just launched (not already in our running set before)
        if !runningWatchedApps.contains(bundleID) {
            // App wasn't in our running set, add it now
            runningWatchedApps.insert(bundleID)
        }
        
        print("AppWatcher: Watched app activated (first time): \(bundleID)")
        
        // Find the WatchedApp enum
        if let watchedApp = WatchedApp.from(bundleIdentifier: bundleID) {
            promptedApps.insert(bundleID)
            onWatchedAppLaunched?(watchedApp)
        }
    }
    
    /// Handle app termination notification
    private func handleAppTermination(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        
        guard runningWatchedApps.contains(bundleID) else { return }
        
        print("AppWatcher: Watched app terminated: \(bundleID)")
        runningWatchedApps.remove(bundleID)
        promptedApps.remove(bundleID)
        
        // Find the WatchedApp enum
        if let watchedApp = WatchedApp.from(bundleIdentifier: bundleID) {
            onWatchedAppTerminated?(watchedApp)
        }
    }
}

