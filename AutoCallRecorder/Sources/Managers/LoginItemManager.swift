import Foundation
import ServiceManagement

/// Manages the app's login item status using modern SMAppService API
@MainActor
final class LoginItemManager {
    static let shared = LoginItemManager()
    
    private init() {}
    
    /// Current login item status
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }
    
    /// Enable or disable login item
    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    print("Login item registered successfully")
                } else {
                    try SMAppService.mainApp.unregister()
                    print("Login item unregistered successfully")
                }
            } catch {
                print("Failed to \(enabled ? "register" : "unregister") login item: \(error)")
            }
        }
    }
    
    /// Check current status and sync with preferences if needed
    func syncWithPreferences() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            switch status {
            case .notRegistered:
                print("Login item: Not registered")
            case .enabled:
                print("Login item: Enabled")
            case .requiresApproval:
                print("Login item: Requires user approval in System Settings")
            case .notFound:
                print("Login item: Not found")
            @unknown default:
                print("Login item: Unknown status")
            }
        }
    }
}

