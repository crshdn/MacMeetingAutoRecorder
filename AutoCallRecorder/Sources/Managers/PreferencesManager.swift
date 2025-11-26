import Foundation
import AppKit
import Combine

/// Manages user preferences and settings
@MainActor
final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()
    
    // MARK: - Published Properties
    
    /// Whether Zoom monitoring is enabled
    @Published var watchZoom: Bool {
        didSet { UserDefaults.standard.set(watchZoom, forKey: Keys.watchZoom) }
    }
    
    /// Whether Teams monitoring is enabled
    @Published var watchTeams: Bool {
        didSet { UserDefaults.standard.set(watchTeams, forKey: Keys.watchTeams) }
    }
    
    /// Whether Google Meet monitoring is enabled
    @Published var watchGoogleMeet: Bool {
        didSet { UserDefaults.standard.set(watchGoogleMeet, forKey: Keys.watchGoogleMeet) }
    }
    
    /// Whether to ask for display every time or remember per app
    @Published var askEveryTime: Bool {
        didSet { UserDefaults.standard.set(askEveryTime, forKey: Keys.askEveryTime) }
    }
    
    /// Whether to start at login
    @Published var startAtLogin: Bool {
        didSet { 
            UserDefaults.standard.set(startAtLogin, forKey: Keys.startAtLogin)
            LoginItemManager.shared.setEnabled(startAtLogin)
        }
    }
    
    /// Default save folder URL
    @Published var defaultSaveFolder: URL {
        didSet { saveFolderBookmark() }
    }
    
    /// Remembered display selections per app bundle ID
    @Published var rememberedDisplays: [String: CGDirectDisplayID] {
        didSet { saveRememberedDisplays() }
    }
    
    // MARK: - Keys
    
    private enum Keys {
        static let watchZoom = "watchZoom"
        static let watchTeams = "watchTeams"
        static let watchGoogleMeet = "watchGoogleMeet"
        static let askEveryTime = "askEveryTime"
        static let startAtLogin = "startAtLogin"
        static let saveFolderBookmark = "saveFolderBookmark"
        static let rememberedDisplays = "rememberedDisplays"
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load preferences with defaults
        self.watchZoom = UserDefaults.standard.object(forKey: Keys.watchZoom) as? Bool ?? true
        self.watchTeams = UserDefaults.standard.object(forKey: Keys.watchTeams) as? Bool ?? true
        self.watchGoogleMeet = UserDefaults.standard.object(forKey: Keys.watchGoogleMeet) as? Bool ?? true
        self.askEveryTime = UserDefaults.standard.object(forKey: Keys.askEveryTime) as? Bool ?? true
        self.startAtLogin = UserDefaults.standard.object(forKey: Keys.startAtLogin) as? Bool ?? false
        
        // Load remembered displays
        if let data = UserDefaults.standard.data(forKey: Keys.rememberedDisplays),
           let displays = try? JSONDecoder().decode([String: UInt32].self, from: data) {
            self.rememberedDisplays = displays
        } else {
            self.rememberedDisplays = [:]
        }
        
        // Load default save folder
        if let bookmarkData = UserDefaults.standard.data(forKey: Keys.saveFolderBookmark),
           let url = try? Self.resolveBookmark(bookmarkData) {
            self.defaultSaveFolder = url
        } else {
            // Default to ~/Movies/Call Recordings
            let moviesURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
            self.defaultSaveFolder = moviesURL.appendingPathComponent("Call Recordings", isDirectory: true)
        }
        
        // Ensure save folder exists
        try? FileManager.default.createDirectory(at: self.defaultSaveFolder, withIntermediateDirectories: true)
    }
    
    // MARK: - Public Methods
    
    /// Check if a specific app should be watched
    func isWatching(_ app: WatchedApp) -> Bool {
        switch app {
        case .zoom:
            return watchZoom
        case .teamsNew, .teamsLegacy:
            return watchTeams
        case .googleMeet:
            return watchGoogleMeet
        }
    }
    
    /// Get remembered display for an app, if any
    func rememberedDisplay(for app: WatchedApp) -> CGDirectDisplayID? {
        guard !askEveryTime else { return nil }
        return rememberedDisplays[app.rawValue]
    }
    
    /// Remember display choice for an app
    func rememberDisplay(_ displayID: CGDirectDisplayID, for app: WatchedApp) {
        rememberedDisplays[app.rawValue] = displayID
    }
    
    /// Clear remembered display for an app
    func clearRememberedDisplay(for app: WatchedApp) {
        rememberedDisplays.removeValue(forKey: app.rawValue)
    }
    
    /// Get list of currently watched apps
    func watchedApps() -> [WatchedApp] {
        var apps: [WatchedApp] = []
        if watchZoom { apps.append(.zoom) }
        if watchTeams { 
            apps.append(.teamsNew)
            apps.append(.teamsLegacy)
        }
        if watchGoogleMeet { apps.append(.googleMeet) }
        return apps
    }
    
    /// Get watched bundle identifiers for native apps
    func watchedBundleIdentifiers() -> Set<String> {
        var ids = Set<String>()
        if watchZoom { ids.formUnion(WatchedApp.zoom.bundleIdentifiers) }
        if watchTeams { 
            ids.formUnion(WatchedApp.teamsNew.bundleIdentifiers)
            ids.formUnion(WatchedApp.teamsLegacy.bundleIdentifiers)
        }
        return ids
    }
    
    // MARK: - Private Methods
    
    private func saveFolderBookmark() {
        do {
            let bookmarkData = try defaultSaveFolder.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: Keys.saveFolderBookmark)
        } catch {
            print("Failed to save folder bookmark: \(error)")
        }
    }
    
    private static func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            print("Bookmark is stale, needs refresh")
        }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
    
    private func saveRememberedDisplays() {
        if let data = try? JSONEncoder().encode(rememberedDisplays) {
            UserDefaults.standard.set(data, forKey: Keys.rememberedDisplays)
        }
    }
}

