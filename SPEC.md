# AutoCallRecorder Specification

## 1. Project Overview

| Property | Description |
| :--- | :--- |
| **Name** | AutoCallRecorder (placeholder) |
| **Platform** | macOS 15+ (Tahoe) |
| **Type** | Menu bar app (no Dock icon, no main window by default) |

**Goal:** Automatically record a selected display whenever Zoom, Google Meet, or Microsoft Teams is active, then stop when the app closes and prompt the user to name and save the recording.

---

## 2. Functional Requirements

### 2.1 App & Meeting Detection

The app runs in the menu bar and starts automatically at login (optional toggle). It monitors running applications via `NSWorkspace`.

**Watched Apps:**

- **Zoom** (`us.zoom.xos`)
- **Microsoft Teams** (`com.microsoft.teams2` and `com.microsoft.teams`)
- **Google Meet** (browser-based - requires window title monitoring across all browsers)

**Trigger Condition:**

- When a watched app becomes active/frontmost AND no recording is currently in progress.
- Action: Open a "Start Recording" dialog.
- *Note: Prompt once per "session" when the app launches, not every time the user switches back to it.*

**Stop Condition:**

- When the watched app terminates.
- OR when the user manually stops recording from the menu bar.

### 2.2 Screen Selection & Recording

When a watched app becomes active, show a modal dialog:

**Dialog:**

- **Title:** Start screen recording?
- **Body:** Zoom (or Teams/Meet) is active. Which display would you like to record?
- **UI:**
  - Dropdown/List of available displays (e.g., "Display 1", "Display 2" with resolutions).
  - Checkbox: "Remember this choice for [Zoom/Teams/Meet]".
- **Buttons:** [Start Recording] [Cancel]

**Recording Logic:**

1. Enumerate displays using `NSScreen.screens`.
2. On "Start Recording":
   - Check screen recording permissions. If missing, macOS prompts the user.
   - Start full-screen capture of the selected display using **ScreenCaptureKit**.
   - Update menu bar icon to indicate recording state (e.g., red dot).
3. Recording continues until the watched app terminates or user manually stops.

### 2.3 Saving & Naming Files

**During Recording:**

- Write to a temporary file in the app's container:
  ```
  ~/Library/Containers/com.meetingrecorder.AutoCallRecorder/Data/tmp/AutoCallRecorder-<timestamp>.mov
  ```

**After Recording (Stop):**

1. Display an `NSSavePanel`.
   - **Default Directory:** User-selected folder (from preferences) or `~/Movies/Call Recordings`.
   - **Suggested Filename:** `Zoom-YYYY-MM-DD-HHMMSS.mov`, `Teams-YYYY-MM-DD-HHMMSS.mov`, or `Meet-YYYY-MM-DD-HHMMSS.mov`.
2. **User Actions:**
   - **Save:** Move/rename the temporary file to the chosen location.
   - **Cancel:** Show an alert "Do you want to discard this recording?".
     - **Discard:** Delete temp file.
     - **Keep:** Save temp file to default folder with auto-generated name.

### 2.4 Preferences

Accessible via the menu bar.

**Settings:**

- **Watched Apps:** Checkboxes for Zoom, Microsoft Teams, Google Meet.
- **Default Save Folder:**
  - Display current path.
  - [Change...] button (opens `NSOpenPanel`).
  - *Implementation Note:* Store security-scoped bookmark.
- **Display Selection Behavior:**
  - (•) Ask every time
  - ( ) Remember per app
  - *Implementation Note:* Store display index per bundle ID.
- **Auto Start:**
  - [x] Start AutoCallRecorder at login.

---

## 3. Non-Functional Requirements

- **Privacy & Transparency:**
  - Always show a clear recording indicator in the menu bar.
  - Never record without user confirmation (initial prompt) and system permission.
- **Reliability:**
  - If recording fails, show an error. Do not fail silently.
- **Performance:**
  - Use hardware-accelerated encoding (H.264).
  - Minimal CPU usage when idle (listening for notifications).

---

## 4. High-Level Architecture

### 4.1 Main Components

**AppDelegate / Main App**

- Sets up the menu bar item.
- Owns shared instances of `AppWatcher`, `RecordingManager`, `PreferencesManager`.

**AppWatcher**

- Listens to `NSWorkspace` notifications (`didLaunch`, `didTerminate`, `didActivate`).
- Filters by watched bundle IDs.
- Emits events: `onWatchedAppActivated`, `onWatchedAppTerminated`.

**RecordingManager**

- State Machine: `idle` → `awaitingUserScreenChoice` → `recording`.
- Manages `ScreenCaptureKit` session.
- Handles temp file paths and triggers the save flow.

**PreferencesManager**

- Stores settings using `UserDefaults` and security-scoped bookmarks.

**UI Components**

- Menu Bar Item (Icon changes state).
- Screen Selection Dialog (SwiftUI/NSAlert).
- Save Panel (`NSSavePanel`).
- Preferences Window.

---

## 5. State Machine / Event Flow

### 5.1 Starting a Recording (Example: Zoom)

1. User launches Zoom.
2. `AppWatcher` detects activation of `us.zoom.xos`.
3. If `RecordingManager` is `idle`:
   - Show Screen Selection Dialog.
4. User selects "Display 1" and clicks "Start".
5. `RecordingManager` starts capture on Display 1.
6. State becomes `.recording`. Menu bar icon turns red.

### 5.2 Stopping & Saving

**Automatic (App Quit):**

1. Zoom terminates.
2. `AppWatcher` detects termination.
3. `RecordingManager` stops recording.
4. Trigger Save Flow (`NSSavePanel`).

**Manual:**

1. User clicks "Stop Recording" in menu bar.
2. `RecordingManager` stops recording.
3. Trigger Save Flow.

---

## 6. Technology Choices

| Technology | Choice |
| :--- | :--- |
| **Language** | Swift |
| **UI** | SwiftUI (wrapping AppKit components like `NSSavePanel` where needed) |
| **Capture API** | ScreenCaptureKit (macOS 12+) |
| **Persistence** | `UserDefaults` + Security-Scoped Bookmarks |
| **Distribution** | Direct (non-sandboxed, not App Store) |

---

## 7. Edge Cases

| Scenario | Handling |
| :--- | :--- |
| **Permission Denied** | Show alert instructing user to enable Screen Recording in System Settings. Do not attempt to record. |
| **Multiple Apps Active** | Only one recording at a time. Silently ignore new meeting app activations while recording is in progress. |
| **Sleep/Lid Close** | Handle capture errors gracefully. Stop recording and attempt to save buffered content. |
| **User Cancels Selection** | App remains idle. |

---

## 8. Future Extensions (v2)

- **Smart Renaming:** Use Accessibility API to read meeting titles/contact names.
- **Shortcuts:** Global hotkey for start/stop.

---

## 9. Configuration Summary

| Setting | Value |
| :--- | :--- |
| **Bundle ID** | `com.meetingrecorder.AutoCallRecorder` |
| **Minimum macOS** | 15+ (Tahoe) |
| **Video Resolution** | 1080p |
| **Frame Rate** | 30fps |
| **Video Codec** | H.264 |
| **Audio** | System audio (both input and output, including Bluetooth) + Microphone |
| **Distribution** | Direct (non-sandboxed) |

---

## 10. Audio Requirements

- Record system audio (captures meeting audio regardless of output device - speakers or Bluetooth earbuds).
- Record microphone audio (captures user's voice).
- Both audio streams should be captured for complete meeting recordings.
- ScreenCaptureKit supports audio capture but requires additional permissions.

---

## 11. Google Meet Detection

Google Meet runs in a browser, requiring detection via window title monitoring using Accessibility APIs.

**Browsers to Monitor:**

- Comet (primary - Chrome-based)
- Google Chrome
- Safari
- Other Chromium-based browsers

**Detection Method:**

- Monitor browser window titles for "Google Meet" or meet.google.com patterns.
- Requires Accessibility permissions.
