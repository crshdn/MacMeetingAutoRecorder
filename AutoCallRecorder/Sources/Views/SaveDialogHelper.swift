import Foundation
import AppKit
import SwiftUI
import UserNotifications

/// Helper to show NSSavePanel for saving recordings
@MainActor
final class SaveDialogHelper {
    
    /// Show save dialog and return the chosen URL, or nil if cancelled
    static func showSaveDialog(
        suggestedFilename: String,
        defaultDirectory: URL
    ) async -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Recording"
        panel.message = "Choose where to save your recording."
        panel.nameFieldLabel = "File Name:"
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.movie]
        panel.directoryURL = defaultDirectory
        
        let response = await panel.begin()
        
        if response == .OK {
            return panel.url
        }
        return nil
    }
    
    /// Show discard confirmation dialog
    /// Returns: true to discard, false to keep
    static func showDiscardConfirmation() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Discard Recording?"
        alert.informativeText = "Do you want to discard this recording, or keep it with an auto-generated name?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Recording")
        alert.addButton(withTitle: "Discard")
        
        let response = alert.runModal()
        return response == .alertSecondButtonReturn // Discard
    }
}

/// SwiftUI wrapper for save dialog flow
struct SaveDialogView: View {
    @ObservedObject var recordingManager: RecordingManager
    @State private var isSaving = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Recording info
            VStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text("Recording Complete")
                    .font(.headline)
                
                if case .saving(_, let app, let startTime) = recordingManager.state {
                    Text("Recorded \(app.displayName) on \(formatDate(startTime))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Duration
            if recordingManager.recordingDuration > 0 {
                Text("Duration: \(formatDuration(recordingManager.recordingDuration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button("Discard") {
                    handleDiscard()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save As...") {
                    Task {
                        await handleSaveAs()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func handleSaveAs() async {
        isSaving = true
        defer { isSaving = false }
        
        let suggestedFilename = recordingManager.suggestedFilename()
        let defaultDirectory = PreferencesManager.shared.defaultSaveFolder
        
        if let url = await SaveDialogHelper.showSaveDialog(
            suggestedFilename: suggestedFilename,
            defaultDirectory: defaultDirectory
        ) {
            let success = await recordingManager.saveRecording(to: url)
            if success {
                showSuccessNotification(url: url)
            }
        } else {
            // User cancelled save dialog
            let shouldDiscard = SaveDialogHelper.showDiscardConfirmation()
            if shouldDiscard {
                recordingManager.discardRecording()
            } else {
                // Keep with auto-generated name
                _ = await recordingManager.keepRecording()
            }
        }
    }
    
    private func handleDiscard() {
        let shouldDiscard = SaveDialogHelper.showDiscardConfirmation()
        if shouldDiscard {
            recordingManager.discardRecording()
        } else {
            Task {
                _ = await recordingManager.keepRecording()
            }
        }
    }
    
    private func showSuccessNotification(url: URL) {
        Task {
            let center = UNUserNotificationCenter.current()
            
            // Request permission if needed
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else { return }
            } catch {
                print("Notification permission error: \(error)")
                return
            }
            
            // Create notification content
            let content = UNMutableNotificationContent()
            content.title = "Recording Saved"
            content.body = "Your recording has been saved to \(url.lastPathComponent)"
            content.sound = .default
            
            // Create request
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil // Deliver immediately
            )
            
            try? await center.add(request)
        }
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

