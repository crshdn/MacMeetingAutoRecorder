import Foundation

/// Represents a meeting application that we monitor
enum WatchedApp: String, CaseIterable, Codable, Identifiable {
    case zoom
    case teamsNew
    case teamsLegacy
    case googleMeet
    
    var id: String { rawValue }
    
    /// Bundle identifiers for native apps
    var bundleIdentifiers: [String] {
        switch self {
        case .zoom:
            return ["us.zoom.xos"]
        case .teamsNew:
            return ["com.microsoft.teams2"]
        case .teamsLegacy:
            return ["com.microsoft.teams"]
        case .googleMeet:
            return [] // Google Meet runs in browser, no bundle ID
        }
    }
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .zoom:
            return "Zoom"
        case .teamsNew, .teamsLegacy:
            return "Microsoft Teams"
        case .googleMeet:
            return "Google Meet"
        }
    }
    
    /// Short name for file naming
    var shortName: String {
        switch self {
        case .zoom:
            return "Zoom"
        case .teamsNew, .teamsLegacy:
            return "Teams"
        case .googleMeet:
            return "Meet"
        }
    }
    
    /// Whether this app runs in a browser
    var isBrowserBased: Bool {
        switch self {
        case .googleMeet:
            return true
        default:
            return false
        }
    }
    
    /// All native apps (non-browser)
    static var nativeApps: [WatchedApp] {
        [.zoom, .teamsNew, .teamsLegacy]
    }
    
    /// All browser-based apps
    static var browserApps: [WatchedApp] {
        [.googleMeet]
    }
    
    /// Get all bundle IDs we should watch
    static var allBundleIdentifiers: Set<String> {
        Set(nativeApps.flatMap { $0.bundleIdentifiers })
    }
    
    /// Find which app matches a given bundle ID
    static func from(bundleIdentifier: String) -> WatchedApp? {
        for app in nativeApps {
            if app.bundleIdentifiers.contains(bundleIdentifier) {
                return app
            }
        }
        return nil
    }
}

/// Browser apps we monitor for Google Meet
enum MonitoredBrowser: String, CaseIterable {
    case safari
    case chrome
    case comet
    case firefox
    case edge
    case arc
    case brave
    case opera
    case vivaldi
    
    var bundleIdentifiers: [String] {
        switch self {
        case .safari:
            return ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
        case .chrome:
            return ["com.google.Chrome", "com.google.Chrome.canary"]
        case .comet:
            return ["com.cometbrowser.Comet", "app.cometbrowser.Comet"]
        case .firefox:
            return ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition"]
        case .edge:
            return ["com.microsoft.edgemac", "com.microsoft.edgemac.Dev"]
        case .arc:
            return ["company.thebrowser.Browser"]
        case .brave:
            return ["com.brave.Browser", "com.brave.Browser.nightly"]
        case .opera:
            return ["com.operasoftware.Opera"]
        case .vivaldi:
            return ["com.vivaldi.Vivaldi"]
        }
    }
    
    static var allBundleIdentifiers: Set<String> {
        Set(allCases.flatMap { $0.bundleIdentifiers })
    }
}

