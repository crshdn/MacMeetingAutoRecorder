import Foundation
import AppKit
import Combine
import os.log

/// Monitors browser windows for Google Meet tabs using Accessibility API
@MainActor
final class BrowserWatcher: ObservableObject {
    
    // MARK: - Logging
    
    private static let logger = Logger(subsystem: "com.meetingrecorder.AutoCallRecorder", category: "BrowserWatcher")
    
    // MARK: - Published Properties
    
    /// Whether Google Meet is currently detected in any browser
    @Published private(set) var isGoogleMeetActive: Bool = false
    
    /// The browser where Google Meet was detected
    @Published private(set) var activeBrowser: String?
    
    /// The display ID where Google Meet window is located
    @Published private(set) var detectedDisplayID: CGDirectDisplayID?
    
    // MARK: - Callbacks
    
    /// Called when Google Meet is first detected (passes the display ID where the window is)
    var onGoogleMeetDetected: ((CGDirectDisplayID?) -> Void)?
    
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
        
        Self.logger.notice("startWatching() called")
        
        guard preferencesManager.watchGoogleMeet else {
            Self.logger.error("Google Meet watching is DISABLED in preferences")
            return
        }
        
        Self.logger.notice("Google Meet watching is enabled, checking Accessibility permissions...")
        
        // Check Accessibility permissions
        guard checkAccessibilityPermissions() else {
            Self.logger.error("Accessibility permissions NOT GRANTED - cannot read window titles")
            return
        }
        
        Self.logger.notice("Accessibility permissions granted ✓")
        
        // Log which browsers we're watching for
        let browserBundleIDs = MonitoredBrowser.allBundleIdentifiers
        Self.logger.notice("Monitoring for browsers: \(browserBundleIDs.joined(separator: ", "))")
        
        // Start polling timer
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForGoogleMeet()
            }
        }
        
        // Do an initial check
        checkForGoogleMeet()
        
        Self.logger.notice("Started watching for Google Meet (polling every \(self.pollingInterval)s)")
    }
    
    /// Stop monitoring
    func stopWatching() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        Self.logger.info("Stopped watching")
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
        var foundDisplayID: CGDirectDisplayID?
        var browsersChecked: [String] = []
        var allTitlesFound: [String: [String]] = [:]
        
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            
            // Check if this is a monitored browser
            if browserBundleIDs.contains(bundleID) {
                browsersChecked.append("\(app.localizedName ?? "Unknown") (\(bundleID))")
                
                // Get window info for this browser (titles and frames)
                if let windowInfo = getWindowInfo(for: app) {
                    allTitlesFound[bundleID] = windowInfo.map { $0.title }
                    
                    for info in windowInfo {
                        if containsMeetPattern(info.title) {
                            foundMeet = true
                            foundBrowser = app.localizedName ?? bundleID
                            foundDisplayID = getDisplayID(for: info.frame)
                            Self.logger.info("✓ MATCH FOUND: '\(info.title)' in \(foundBrowser ?? "unknown") on display \(foundDisplayID ?? 0)")
                            break
                        }
                    }
                } else {
                    Self.logger.debug("No window titles returned for \(bundleID) - Accessibility issue?")
                    allTitlesFound[bundleID] = ["<no titles - accessibility denied?>"]
                }
            }
            
            if foundMeet { break }
        }
        
        // Log periodic status (every ~10 seconds = every 5th check)
        if Int.random(in: 0..<5) == 0 {
            if browsersChecked.isEmpty {
                Self.logger.notice("Poll: No monitored browsers running")
            } else {
                Self.logger.notice("Poll: Checked \(browsersChecked.count) browser(s): \(browsersChecked.joined(separator: ", "))")
                for (bundleID, titles) in allTitlesFound {
                    Self.logger.notice("  \(bundleID) windows: \(titles.joined(separator: " | "))")
                }
            }
        }
        
        // Handle state changes
        if foundMeet && !isGoogleMeetActive {
            isGoogleMeetActive = true
            activeBrowser = foundBrowser
            detectedDisplayID = foundDisplayID
            Self.logger.notice("🎬 Google Meet DETECTED in \(foundBrowser ?? "unknown browser") on display \(foundDisplayID ?? 0) - triggering recording")
            
            if !hasPromptedThisSession {
                hasPromptedThisSession = true
                Self.logger.notice("Calling onGoogleMeetDetected callback with display \(foundDisplayID ?? 0)...")
                onGoogleMeetDetected?(foundDisplayID)
            } else {
                Self.logger.error("Already prompted this session, not triggering again")
            }
        } else if !foundMeet && isGoogleMeetActive {
            isGoogleMeetActive = false
            activeBrowser = nil
            detectedDisplayID = nil
            Self.logger.notice("🛑 Google Meet NO LONGER DETECTED - stopping recording")
            onGoogleMeetEnded?()
        }
    }
    
    /// Window info containing title and frame
    private struct WindowInfo {
        let title: String
        let frame: CGRect
    }
    
    /// Get window info (titles and frames) for a running application using Accessibility API
    private func getWindowInfo(for app: NSRunningApplication) -> [WindowInfo]? {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            // Log the error code for debugging
            Self.logger.debug("AXUIElement failed for PID \(pid): error code \(result.rawValue)")
            return nil
        }
        
        var windowInfos: [WindowInfo] = []
        
        for window in windows {
            // Get title
            var titleRef: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            guard titleResult == .success, let title = titleRef as? String, !title.isEmpty else {
                continue
            }
            
            // Get position
            var positionRef: CFTypeRef?
            let positionResult = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
            var position = CGPoint.zero
            if positionResult == .success, let positionValue = positionRef {
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
            }
            
            // Get size
            var sizeRef: CFTypeRef?
            let sizeResult = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
            var size = CGSize.zero
            if sizeResult == .success, let sizeValue = sizeRef {
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            }
            
            let frame = CGRect(origin: position, size: size)
            windowInfos.append(WindowInfo(title: title, frame: frame))
        }
        
        return windowInfos.isEmpty ? nil : windowInfos
    }
    
    /// Get window titles for a running application using Accessibility API (legacy method)
    private func getWindowTitles(for app: NSRunningApplication) -> [String]? {
        return getWindowInfo(for: app)?.map { $0.title }
    }
    
    /// Determine which display contains the center of the given window frame
    private func getDisplayID(for windowFrame: CGRect) -> CGDirectDisplayID? {
        // Get the center point of the window
        let centerPoint = CGPoint(
            x: windowFrame.midX,
            y: windowFrame.midY
        )
        
        // Get all online displays
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        
        guard displayCount > 0 else { return nil }
        
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displays, &displayCount)
        
        // Find which display contains the center point
        for displayID in displays {
            let displayBounds = CGDisplayBounds(displayID)
            if displayBounds.contains(centerPoint) {
                Self.logger.debug("Window center (\(centerPoint.x), \(centerPoint.y)) is on display \(displayID)")
                return displayID
            }
        }
        
        // Fallback: return main display if no match found
        Self.logger.debug("No display found for window center, using main display")
        return CGMainDisplayID()
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

