import SwiftUI

/// Preferences window for app settings
struct PreferencesView: View {
    @ObservedObject var preferencesManager: PreferencesManager
    @Environment(\.dismiss) private var dismiss
    @State private var isSelectingFolder = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    watchedAppsSection
                    saveFolderSection
                    displayBehaviorSection
                    loginItemSection
                }
                .padding(24)
            }
            
            Divider()
            
            // Footer
            footerSection
        }
        .frame(width: 500, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        HStack {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            Text("Preferences")
                .font(.headline)
            
            Spacer()
        }
        .padding()
    }
    
    private var watchedAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Watched Applications", systemImage: "app.badge.checkmark")
                .font(.headline)
            
            Text("AutoCallRecorder will prompt to record when these apps are launched:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $preferencesManager.watchZoom) {
                    HStack {
                        Image(systemName: "video.fill")
                            .frame(width: 20)
                        Text("Zoom")
                    }
                }
                
                Toggle(isOn: $preferencesManager.watchTeams) {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .frame(width: 20)
                        Text("Microsoft Teams")
                    }
                }
                
                Toggle(isOn: $preferencesManager.watchGoogleMeet) {
                    HStack {
                        Image(systemName: "globe")
                            .frame(width: 20)
                        VStack(alignment: .leading) {
                            Text("Google Meet")
                            Text("Requires Accessibility permission")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.leading, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private var saveFolderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Default Save Location", systemImage: "folder")
                .font(.headline)
            
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.blue)
                
                Text(preferencesManager.defaultSaveFolder.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                Button("Change...") {
                    selectFolder()
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            
            Text("Recordings will be saved here by default. You can choose a different location when saving.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private var displayBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Display Selection", systemImage: "display")
                .font(.headline)
            
            Picker("", selection: $preferencesManager.askEveryTime) {
                Text("Ask every time").tag(true)
                Text("Remember per app").tag(false)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            
            if !preferencesManager.askEveryTime {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remembered displays:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if preferencesManager.rememberedDisplays.isEmpty {
                        Text("None yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(Array(preferencesManager.rememberedDisplays.keys), id: \.self) { appKey in
                            if let app = WatchedApp(rawValue: appKey) {
                                HStack {
                                    Text("• \(app.displayName)")
                                        .font(.caption)
                                    Spacer()
                                    Button("Clear") {
                                        preferencesManager.clearRememberedDisplay(for: app)
                                    }
                                    .font(.caption)
                                    .buttonStyle(.link)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private var loginItemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Startup", systemImage: "power")
                .font(.headline)
            
            Toggle(isOn: $preferencesManager.startAtLogin) {
                Text("Start AutoCallRecorder at login")
            }
            
            Text("The app will run in the menu bar automatically when you log in.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private var footerSection: some View {
        HStack {
            Text("AutoCallRecorder v1.0")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose Save Location"
        panel.message = "Select a folder where recordings will be saved by default."
        panel.directoryURL = preferencesManager.defaultSaveFolder
        
        if panel.runModal() == .OK, let url = panel.url {
            preferencesManager.defaultSaveFolder = url
        }
    }
}

// MARK: - Preview

#Preview {
    PreferencesView(preferencesManager: .shared)
}

