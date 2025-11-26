# Changelog

All notable changes to MacMeetingAutoRecorder will be documented in this file.

## [1.2.0] - 2024-11-26

### Fixed

- **Comet Browser Detection**: Updated bundle ID from `com.cometbrowser.Comet` to `ai.perplexity.comet` (Perplexity's Comet browser)

### Added

- **Automatic Display Detection**: App now automatically detects which screen the browser window is on and records that display instead of defaulting to the main display
  - Uses Accessibility API to get browser window position
  - Calculates which display contains the window center point
  - Falls back to main display if detection fails

- **Comprehensive Logging**: Added `os.log` logging throughout for debugging
  - BrowserWatcher: Logs permission checks, browser detection, window titles, display detection
  - RecordingManager: Logs app detection, display selection, recording start/stop
  - ScreenCaptureManager: Logs permission checks and errors
  - All logs visible in Console.app under subsystem `com.meetingrecorder.AutoCallRecorder`

### Technical Changes

- `BrowserWatcher` now returns display ID along with Google Meet detection
- `onGoogleMeetDetected` callback now passes `CGDirectDisplayID?` parameter
- Added `getWindowInfo()` method to get window frames via Accessibility API
- Added `getDisplayID(for:)` method to determine display from window frame

---

## [1.1.0] - 2024-11-26

### Added - Fully Automatic Mode

- **Fully Automatic Mode** (enabled by default):
  - Auto-starts recording when a meeting app is detected (no prompts)
  - Uses main display or remembered display choice
  - Auto-saves to default folder when meeting ends (no save dialog)
  - Shows system notifications for: recording started, recording saved, errors
  
- **Preferences Toggle**: Users can switch between:
  - Fully Automatic Mode (zero interaction)
  - Manual Mode (prompts for display selection and save location)

### Changed

- Default behavior is now fully automatic (no user interaction required)
- Improved notification system using modern UserNotifications framework

---

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

