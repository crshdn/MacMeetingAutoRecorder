import Foundation
import CoreGraphics

/// Represents the current state of the recording system
enum RecordingState: Equatable {
    /// No recording in progress, ready to detect meeting apps
    case idle
    
    /// A watched app was detected, waiting for user to select display
    case awaitingUserChoice(app: WatchedApp)
    
    /// Actively recording the screen
    case recording(app: WatchedApp, displayID: UInt32, startTime: Date)
    
    /// Recording stopped, waiting for user to save
    case saving(tempFileURL: URL, app: WatchedApp, startTime: Date)
    
    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }
    
    var isIdle: Bool {
        if case .idle = self {
            return true
        }
        return false
    }
    
    var currentApp: WatchedApp? {
        switch self {
        case .idle:
            return nil
        case .awaitingUserChoice(let app):
            return app
        case .recording(let app, _, _):
            return app
        case .saving(_, let app, _):
            return app
        }
    }
}

