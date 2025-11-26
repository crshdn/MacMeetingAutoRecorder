import Foundation
import AppKit
import Combine

/// Monitors browser windows for Google Meet tabs using Accessibility API
@MainActor
final class BrowserWatcher: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether Google Meet is currently detected in any browser
    @Published private(set) var isGoogleMeetActive: Bool = false
    
    /// The browser where Google Meet was detected
    @Published private(set) var activeBrowser: String?
    
    // MARK: - Callbacks
    
    /// Called when Google Meet is first detected
    var onGoogleMeetDetected: (() -> Void)?
    
    /// Called when Google Meet is no longer detected
    var onGoogleMeetEnded: (() -> Void)?
    
    // MARK: - Private Properties
    
    private var pollingTimer: Timer?
    private var hasPromptedThisSession = false
    private let pollingInterval: TimeInterval = 2.0 // Check every 2 seconds
    private var preferencesManager: PreferencesManager!
    
    // Patterns to detect Google Meet in window titles
    private let meetPatterns = [
        "meet.google.com",
        "Google Meet",
        "Meet - ",
        " | Meet"
    ]
    
    // MARK: - Initialization
    
    init(preferencesManager: PreferencesManager? = nil) {
        if let pm = preferencesManager {
            self.preferencesManager = pm
        }
    }
    
    func configure(preferencesManager: PreferencesManager) {
        self.preferencesManager = preferencesManager
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring browsers for Google Meet
    func startWatching() {
        stopWatching()
        
        guard preferencesManager.watchGoogleMeet else {
            print("BrowserWatcher: Google Meet watching is disabled")
            return
        }
        
        // Check Accessibility permissions
        guard checkAccessibilityPermissions() else {
            print("BrowserWatcher: Accessibility permissions not granted")
            return
        }
        
        // Start polling timer
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForGoogleMeet()
            }
        }
        
        // Do an initial check
        checkForGoogleMeet()
        
        print("BrowserWatcher: Started watching for Google Meet")
    }
    
    /// Stop monitoring
    func stopWatching() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        print("BrowserWatcher: Stopped watching")
    }
    
    /// Reset session state
    func resetSession() {
        hasPromptedThisSession = false
        isGoogleMeetActive = false
        activeBrowser = nil
    }
    
    /// Mark as prompted to avoid re-prompting
    func markAsPrompted() {
        hasPromptedThisSession = true
    }
    
    // MARK: - Private Methods
    
    /// Check if Accessibility permissions are granted
    private func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// Poll all browser windows for Google Meet
    private func checkForGoogleMeet() {
        guard preferencesManager.watchGoogleMeet else { return }
        
        let runningApps = NSWorkspace.shared.runningApplications
        let browserBundleIDs = MonitoredBrowser.allBundleIdentifiers
        
        var foundMeet = false
        var foundBrowser: String?
        
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  browserBundleIDs.contains(bundleID) else { continue }
            
            // Get window titles for this browser
            if let windowTitles = getWindowTitles(for: app) {
                for title in windowTitles {
                    if containsMeetPattern(title) {
                        foundMeet = true
                        foundBrowser = app.localizedName ?? bundleID
                        break
                    }
                }
            }
            
            if foundMeet { break }
        }
        
        // Handle state changes
        if foundMeet && !isGoogleMeetActive {
            isGoogleMeetActive = true
            activeBrowser = foundBrowser
            print("BrowserWatcher: Google Meet detected in \(foundBrowser ?? "unknown browser")")
            
            if !hasPromptedThisSession {
                hasPromptedThisSession = true
                onGoogleMeetDetected?()
            }
        } else if !foundMeet && isGoogleMeetActive {
            isGoogleMeetActive = false
            activeBrowser = nil
            print("BrowserWatcher: Google Meet no longer detected")
            onGoogleMeetEnded?()
        }
    }
    
    /// Get window titles for a running application using Accessibility API
    private func getWindowTitles(for app: NSRunningApplication) -> [String]? {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }
        
        var titles: [String] = []
        
        for window in windows {
            var titleRef: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            
            if titleResult == .success, let title = titleRef as? String, !title.isEmpty {
                titles.append(title)
            }
        }
        
        return titles.isEmpty ? nil : titles
    }
    
    /// Check if a window title contains a Google Meet pattern
    private func containsMeetPattern(_ title: String) -> Bool {
        let lowercased = title.lowercased()
        for pattern in meetPatterns {
            if lowercased.contains(pattern.lowercased()) {
                return true
            }
        }
        return false
    }
}

