import SwiftUI

/// The menu bar dropdown content
struct MenuBarView: View {
    @ObservedObject var recordingManager: RecordingManager
    @ObservedObject var preferencesManager: PreferencesManager
    @State private var showingPreferences = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status section
            statusSection
            
            Divider()
                .padding(.vertical, 4)
            
            // Recording controls
            recordingControlsSection
            
            Divider()
                .padding(.vertical, 4)
            
            // Quick toggles
            watchedAppsSection
            
            Divider()
                .padding(.vertical, 4)
            
            // Bottom actions
            bottomSection
        }
        .padding(.vertical, 8)
        .frame(width: 280)
    }
    
    // MARK: - Sections
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                
                Spacer()
            }
            
            if recordingManager.state.isRecording {
                HStack {
                    Image(systemName: "record.circle")
                        .foregroundColor(.red)
                    
                    Text(formatDuration(recordingManager.recordingDuration))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    if let app = recordingManager.state.currentApp {
                        Text("• \(app.displayName)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 12)
    }
    
    private var recordingControlsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if recordingManager.state.isRecording {
                Button(action: {
                    Task {
                        await recordingManager.stopRecording()
                    }
                }) {
                    HStack {
                        Image(systemName: "stop.fill")
                            .foregroundColor(.red)
                        Text("Stop Recording")
                        Spacer()
                        Text("⌘S")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(MenuItemButtonStyle())
            } else {
                Button(action: {
                    // Manual start - show display picker
                    recordingManager.showingScreenSelection = true
                }) {
                    HStack {
                        Image(systemName: "record.circle")
                        Text("Start Recording...")
                        Spacer()
                    }
                }
                .buttonStyle(MenuItemButtonStyle())
                .disabled(!recordingManager.state.isIdle)
            }
        }
        .padding(.horizontal, 4)
    }
    
    private var watchedAppsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("WATCHED APPS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            
            Toggle(isOn: $preferencesManager.watchZoom) {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Zoom")
                }
            }
            .toggleStyle(MenuToggleStyle())
            .padding(.horizontal, 12)
            
            Toggle(isOn: $preferencesManager.watchTeams) {
                HStack {
                    Image(systemName: "person.2.fill")
                    Text("Microsoft Teams")
                }
            }
            .toggleStyle(MenuToggleStyle())
            .padding(.horizontal, 12)
            
            Toggle(isOn: $preferencesManager.watchGoogleMeet) {
                HStack {
                    Image(systemName: "globe")
                    Text("Google Meet")
                }
            }
            .toggleStyle(MenuToggleStyle())
            .padding(.horizontal, 12)
        }
    }
    
    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: {
                showingPreferences = true
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text("Preferences...")
                    Spacer()
                    Text("⌘,")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(MenuItemButtonStyle())
            .sheet(isPresented: $showingPreferences) {
                PreferencesView(preferencesManager: preferencesManager)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit AutoCallRecorder")
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(MenuItemButtonStyle())
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Helpers
    
    private var statusColor: Color {
        switch recordingManager.state {
        case .idle:
            return .green
        case .awaitingUserChoice:
            return .orange
        case .recording:
            return .red
        case .saving:
            return .blue
        }
    }
    
    private var statusText: String {
        switch recordingManager.state {
        case .idle:
            return "Ready"
        case .awaitingUserChoice(let app):
            return "Waiting: \(app.displayName)"
        case .recording(let app, _, _):
            return "Recording: \(app.displayName)"
        case .saving:
            return "Saving..."
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Custom Button Style

struct MenuItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Custom Toggle Style

struct MenuToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            HStack {
                configuration.label
                Spacer()
                Image(systemName: configuration.isOn ? "checkmark" : "")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

