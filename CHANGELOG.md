# Changelog

All notable changes to AutoCallRecorder will be documented in this file.

## [1.0.0] - 2024-11-26

### Initial Release

Complete implementation of AutoCallRecorder - a macOS menu bar app that automatically detects and records meetings.

#### Features Added

- **Menu Bar App**
  - Runs in the menu bar with no dock icon
  - Icon changes to indicate recording state (idle vs recording)
  - Clean dropdown menu with status, controls, and preferences

- **Meeting App Detection**
  - Automatic detection of Zoom (`us.zoom.xos`)
  - Automatic detection of Microsoft Teams (`com.microsoft.teams2`, `com.microsoft.teams`)
  - Automatic detection of Google Meet (via browser window title monitoring)
  - Support for multiple browsers: Safari, Chrome, Comet, Firefox, Edge, Arc, Brave, Opera, Vivaldi

- **Screen Recording**
  - Uses ScreenCaptureKit for high-quality capture
  - 1080p @ 30fps H.264 video
  - System audio + microphone recording (48kHz AAC)
  - Hardware-accelerated encoding

- **User Flow**
  - Display selection dialog when meeting app is detected
  - Option to remember display choice per app
  - NSSavePanel for naming and saving recordings
  - Discard/Keep options if user cancels save

- **Preferences**
  - Toggle which apps to watch (Zoom, Teams, Google Meet)
  - Set default save location
  - Display selection behavior (ask every time vs remember)
  - Auto-start at login option

- **Permissions**
  - Screen Recording permission handling
  - Microphone permission for audio
  - Accessibility permission for Google Meet detection

#### Files Created

| File | Description |
|------|-------------|
| `Sources/AutoCallRecorderApp.swift` | Main app entry, menu bar setup, AppDelegate |
| `Sources/Models/RecordingState.swift` | Recording state machine enum |
| `Sources/Models/WatchedApp.swift` | Meeting app definitions and browser list |
| `Sources/Models/DisplayInfo.swift` | Display information wrapper |
| `Sources/Managers/AppWatcher.swift` | Native app detection via NSWorkspace |
| `Sources/Managers/BrowserWatcher.swift` | Google Meet detection via Accessibility API |
| `Sources/Managers/ScreenCaptureManager.swift` | ScreenCaptureKit wrapper for recording |
| `Sources/Managers/RecordingManager.swift` | Orchestrates the recording workflow |
| `Sources/Managers/PreferencesManager.swift` | User preferences and settings |
| `Sources/Managers/LoginItemManager.swift` | Auto-start at login management |
| `Sources/Views/MenuBarView.swift` | Menu bar dropdown content |
| `Sources/Views/ScreenSelectionView.swift` | Display selection dialog |
| `Sources/Views/PreferencesView.swift` | Settings window |
| `Sources/Views/SaveDialogHelper.swift` | Save dialog and notifications |
| `Sources/Info.plist` | App configuration and permissions |
| `Sources/AutoCallRecorder.entitlements` | App entitlements |
| `AutoCallRecorder.xcodeproj/` | Xcode project files |

#### Technical Details

- **Target:** macOS 14.0+ (Sonoma/Tahoe compatible)
- **Language:** Swift 5.9
- **UI Framework:** SwiftUI with AppKit bridges
- **Capture API:** ScreenCaptureKit
- **Video Codec:** H.264 with hardware acceleration
- **Audio:** 48kHz stereo AAC
- **Distribution:** Non-sandboxed (direct distribution, not App Store)

