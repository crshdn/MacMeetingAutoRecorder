# 🎬 MacMeetingAutoRecorder

A lightweight macOS menu bar app that **automatically detects and records your video meetings** — no manual clicking required.

## The Problem

We've all been there: you finish an important meeting and realize you can't remember half of what was discussed. Action items get lost, key decisions fade from memory, and you're left piecing together notes that don't quite capture everything.

The usual solution? Manually start a screen recording before every call. But let's be honest — when you're rushing to join a meeting, hitting "record" is the last thing on your mind.

## The Solution

**MacMeetingAutoRecorder** runs quietly in your menu bar and watches for video calls. The moment you open Zoom, Microsoft Teams, or Google Meet, it detects it and prompts you to record. When the meeting ends, it automatically stops and asks where you'd like to save the file.

No apps to open. No buttons to click. No meetings forgotten. And lightweight!

**It just works.**

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| **🔍 Auto-Detection** | Automatically detects when Zoom, Teams, or Google Meet starts |
| **🖥️ Display Selection** | Choose which monitor to record (great for multi-monitor setups) |
| **🎤 Full Audio** | Captures system audio + your microphone |
| **📁 Smart Saving** | Prompts to name and save when the meeting ends |
| **⚙️ Preferences** | Remember display choices, set default save folder |
| **🚀 Launch at Login** | Optional auto-start when you log in |
| **🔴 Recording Indicator** | Menu bar icon shows when recording is active |

---

## 📦 Installation

### Option 1: Download Release (Recommended)
1. Go to [Releases](https://github.com/crshdn/MacMeetingAutoRecorder/releases)
2. Download `MacMeetingAutoRecorder.app.zip`
3. Unzip and drag to `/Applications`
4. Double-click to run

### Option 2: Build from Source
```bash
# Clone the repo
git clone https://github.com/crshdn/MacMeetingAutoRecorder.git
cd MacMeetingAutoRecorder

# Build with Xcode
cd AutoCallRecorder
xcodebuild -project AutoCallRecorder.xcodeproj \
           -scheme AutoCallRecorder \
           -configuration Release \
           build

# The app will be in:
# ~/Library/Developer/Xcode/DerivedData/AutoCallRecorder-*/Build/Products/Release/
```

Or open `AutoCallRecorder/AutoCallRecorder.xcodeproj` in Xcode and press ⌘R.

---

## 🔐 Permissions Required

On first run, macOS will ask for these permissions. **All are required for full functionality:**

| Permission | Why It's Needed | How to Grant |
|------------|-----------------|--------------|
| **Screen Recording** | To capture your display | System Settings → Privacy & Security → Screen Recording |
| **Microphone** | To record your voice | System Settings → Privacy & Security → Microphone |
| **Accessibility** | To detect Google Meet in browsers | System Settings → Privacy & Security → Accessibility |

> 💡 **Tip:** If the app can't record, check that all permissions are enabled in System Settings.

---

## 🚀 How It Works

### 1. Launch the App
The app runs in your **menu bar** (no dock icon). Look for the ⏺ icon.

### 2. Start a Meeting
Open **Zoom**, **Microsoft Teams**, or **Google Meet** in any browser.

### 3. Choose Display
A dialog appears asking which display to record. Optionally check "Remember this choice."

### 4. Recording Starts
The menu bar icon turns **red** 🔴 to indicate recording is active.

### 5. End the Meeting
Close the meeting app. The recording stops automatically.

### 6. Save Your Recording
A save dialog appears. Name your file and choose where to save it.

---

## 🎯 Supported Apps

### Native Apps (Auto-detected)
- ✅ **Zoom** (`us.zoom.xos`)
- ✅ **Microsoft Teams** (new and legacy versions)

### Browser-Based (Window Title Detection)
- ✅ **Google Meet** - Works in any browser:
  - Safari
  - Chrome / Comet
  - Firefox
  - Microsoft Edge
  - Arc
  - Brave
  - Opera
  - Vivaldi

---

## ⚙️ Preferences

Click the menu bar icon → **Preferences** to configure:

| Setting | Description |
|---------|-------------|
| **Watched Apps** | Toggle which apps trigger recording prompts |
| **Default Save Folder** | Where recordings are saved by default |
| **Display Selection** | Ask every time vs. remember per app |
| **Start at Login** | Auto-launch when you log in |

---

## 📹 Recording Specs

| Property | Value |
|----------|-------|
| **Resolution** | 1080p (scaled from your display) |
| **Frame Rate** | 30 fps |
| **Video Codec** | H.264 (hardware accelerated) |
| **Audio** | 48kHz stereo AAC |
| **File Format** | .mov (QuickTime) |
| **Audio Sources** | System audio + Microphone |

---

## 🛠️ Troubleshooting

### App doesn't appear in menu bar
- Check if it's running: `ps aux | grep AutoCallRecorder`
- Try launching from Terminal: `open /Applications/MacMeetingAutoRecorder.app`

### Recording permission denied
1. Open **System Settings** → **Privacy & Security** → **Screen Recording**
2. Find and enable **MacMeetingAutoRecorder**
3. Restart the app

### No audio in recordings
1. Open **System Settings** → **Privacy & Security** → **Microphone**
2. Enable **MacMeetingAutoRecorder**

### Google Meet not detected
1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Enable **MacMeetingAutoRecorder**
3. Restart the app

### Recording is black/empty
- Ensure you selected the correct display
- Some apps (like DRM-protected content) cannot be captured

---

## 🏗️ Project Structure

```
MacMeetingAutoRecorder/
├── AutoCallRecorder/
│   ├── AutoCallRecorder.xcodeproj/
│   └── Sources/
│       ├── AutoCallRecorderApp.swift    # Main entry point
│       ├── Models/
│       │   ├── RecordingState.swift     # State machine
│       │   ├── WatchedApp.swift         # App definitions
│       │   └── DisplayInfo.swift        # Display wrapper
│       ├── Managers/
│       │   ├── AppWatcher.swift         # Native app detection
│       │   ├── BrowserWatcher.swift     # Google Meet detection
│       │   ├── ScreenCaptureManager.swift
│       │   ├── RecordingManager.swift   # Orchestration
│       │   ├── PreferencesManager.swift
│       │   └── LoginItemManager.swift
│       └── Views/
│           ├── MenuBarView.swift
│           ├── ScreenSelectionView.swift
│           ├── PreferencesView.swift
│           └── SaveDialogHelper.swift
├── README.md
├── CHANGELOG.md
└── SPEC.md
```

---

## 📋 Requirements

- **macOS 14.0** (Sonoma) or later
- **Xcode 15+** (for building from source)

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.

---

## 🤝 Contributing

Contributions are welcome! Feel free to:
- 🐛 Report bugs
- 💡 Suggest features
- 🔧 Submit pull requests

---

## 📬 Contact

Created by [@crshdn](https://github.com/crshdn)

---

<p align="center">
  <i>Never forget to record an important meeting again.</i>
</p>
