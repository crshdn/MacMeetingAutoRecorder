import SwiftUI
import ScreenCaptureKit

/// Dialog for selecting which display to record
struct ScreenSelectionView: View {
    @ObservedObject var recordingManager: RecordingManager
    @State private var selectedDisplayID: CGDirectDisplayID?
    @State private var rememberChoice = false
    @State private var displays: [DisplayInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            headerSection
            
            // Display picker
            displayPickerSection
            
            // Remember choice toggle
            rememberChoiceSection
            
            // Buttons
            buttonSection
        }
        .padding(24)
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadDisplays()
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "record.circle")
                .font(.system(size: 40))
                .foregroundColor(.red)
            
            Text("Start Screen Recording?")
                .font(.headline)
            
            if let app = recordingManager.pendingApp {
                Text("\(app.displayName) is active. Which display would you like to record?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var displayPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Display:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                Picker("Display", selection: $selectedDisplayID) {
                    ForEach(displays) { display in
                        HStack {
                            Image(systemName: display.isMain ? "display" : "rectangle.on.rectangle")
                            Text(display.name)
                        }
                        .tag(display.id as CGDirectDisplayID?)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private var rememberChoiceSection: some View {
        Toggle(isOn: $rememberChoice) {
            if let app = recordingManager.pendingApp {
                Text("Remember this choice for \(app.displayName)")
                    .font(.subheadline)
            } else {
                Text("Remember this choice")
                    .font(.subheadline)
            }
        }
        .toggleStyle(.checkbox)
    }
    
    private var buttonSection: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                recordingManager.cancelScreenSelection()
            }
            .keyboardShortcut(.escape, modifiers: [])
            
            Spacer()
            
            Button("Start Recording") {
                startRecording()
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
            .disabled(selectedDisplayID == nil || isLoading)
        }
    }
    
    // MARK: - Actions
    
    private func loadDisplays() {
        isLoading = true
        errorMessage = nil
        
        Task {
            // Check permission first
            let hasPermission = await recordingManager.checkPermission()
            
            if !hasPermission {
                await MainActor.run {
                    errorMessage = "Screen recording permission required. Please grant permission in System Settings."
                    isLoading = false
                }
                return
            }
            
            // Get displays
            let loadedDisplays = DisplayInfo.allDisplays()
            
            await MainActor.run {
                displays = loadedDisplays
                
                // Auto-select main display or first display
                if let main = displays.first(where: { $0.isMain }) {
                    selectedDisplayID = main.id
                } else {
                    selectedDisplayID = displays.first?.id
                }
                
                isLoading = false
            }
        }
    }
    
    private func startRecording() {
        guard let displayID = selectedDisplayID,
              let app = recordingManager.pendingApp else { return }
        
        Task {
            await recordingManager.startRecording(
                displayID: displayID,
                for: app,
                rememberChoice: rememberChoice
            )
        }
    }
}

// MARK: - Preview

#Preview {
    ScreenSelectionView(
        recordingManager: RecordingManager(preferencesManager: .shared)
    )
}

