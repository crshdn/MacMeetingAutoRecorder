import Foundation
import AppKit

/// Wrapper for display information
struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let resolution: String
    let isMain: Bool
    let frame: CGRect
    
    init(screen: NSScreen, index: Int) {
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        self.id = displayID
        self.isMain = screen == NSScreen.main
        self.frame = screen.frame
        
        // Get display name
        let width = Int(screen.frame.width)
        let height = Int(screen.frame.height)
        self.resolution = "\(width) × \(height)"
        
        if isMain {
            self.name = "Main Display (\(resolution))"
        } else {
            self.name = "Display \(index + 1) (\(resolution))"
        }
    }
    
    /// Get all connected displays
    static func allDisplays() -> [DisplayInfo] {
        NSScreen.screens.enumerated().map { index, screen in
            DisplayInfo(screen: screen, index: index)
        }
    }
    
    /// Find display by ID
    static func display(withID id: CGDirectDisplayID) -> DisplayInfo? {
        allDisplays().first { $0.id == id }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool {
        lhs.id == rhs.id
    }
}

