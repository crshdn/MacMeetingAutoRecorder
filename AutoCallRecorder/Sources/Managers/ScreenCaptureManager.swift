import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import Combine

/// Errors that can occur during screen capture
enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case displayNotFound
    case captureSetupFailed(String)
    case recordingFailed(String)
    case noAudioDeviceFound
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission denied. Please enable it in System Settings > Privacy & Security > Screen Recording."
        case .displayNotFound:
            return "The selected display was not found."
        case .captureSetupFailed(let reason):
            return "Failed to set up screen capture: \(reason)"
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        case .noAudioDeviceFound:
            return "No audio device found for recording."
        }
    }
}

/// Manages screen capture using ScreenCaptureKit
@MainActor
final class ScreenCaptureManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var currentTempFileURL: URL?
    
    // MARK: - Private Properties
    
    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    
    // Recording settings
    private let targetWidth: Int = 1920
    private let targetHeight: Int = 1080
    private let frameRate: Int = 30
    
    // MARK: - Public Methods
    
    /// Check if screen recording permission is granted
    func checkPermission() async -> Bool {
        do {
            // Requesting shareable content will prompt for permission if not granted
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            print("ScreenCaptureManager: Permission check failed: \(error)")
            return false
        }
    }
    
    /// Request permission by attempting to get shareable content
    func requestPermission() async -> Bool {
        return await checkPermission()
    }
    
    /// Get available displays for capture
    func getAvailableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays
    }
    
    /// Start recording a specific display
    func startRecording(displayID: CGDirectDisplayID) async throws -> URL {
        guard !isRecording else {
            throw ScreenCaptureError.captureSetupFailed("Already recording")
        }
        
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        // Find the display
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.displayNotFound
        }
        
        // Create temp file URL
        let tempURL = createTempFileURL()
        
        // Set up asset writer
        try setupAssetWriter(url: tempURL, display: display)
        
        // Create stream configuration
        let config = SCStreamConfiguration()
        
        // Video settings - scale to 1080p while maintaining aspect ratio
        let displayAspect = CGFloat(display.width) / CGFloat(display.height)
        let targetAspect = CGFloat(targetWidth) / CGFloat(targetHeight)
        
        if displayAspect > targetAspect {
            // Display is wider, fit to width
            config.width = targetWidth
            config.height = Int(CGFloat(targetWidth) / displayAspect)
        } else {
            // Display is taller, fit to height
            config.height = targetHeight
            config.width = Int(CGFloat(targetHeight) * displayAspect)
        }
        
        // Make dimensions even (required for video encoding)
        config.width = (config.width / 2) * 2
        config.height = (config.height / 2) * 2
        
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 5
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        
        // Audio settings - capture system audio
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        
        // Create content filter for the display
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // Create stream
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        
        // Create output handler
        let output = CaptureStreamOutput { [weak self] sampleBuffer, type in
            self?.processSampleBuffer(sampleBuffer, type: type)
        }
        
        // Add stream outputs
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.meetingrecorder.screen"))
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.meetingrecorder.audio"))
        
        // Start capture
        try await stream.startCapture()
        
        // Store references
        self.stream = stream
        self.streamOutput = output
        self.currentTempFileURL = tempURL
        self.isRecording = true
        self.recordingStartTime = Date()
        
        // Start duration timer
        startDurationTimer()
        
        print("ScreenCaptureManager: Started recording to \(tempURL.path)")
        
        return tempURL
    }
    
    /// Stop recording and return the temp file URL
    func stopRecording() async throws -> URL? {
        guard isRecording else { return nil }
        
        print("ScreenCaptureManager: Stopping recording...")
        
        // Stop duration timer
        stopDurationTimer()
        
        // Stop the stream
        if let stream = stream {
            try await stream.stopCapture()
        }
        
        // Finish writing
        await finishWriting()
        
        // Clean up
        let tempURL = currentTempFileURL
        stream = nil
        streamOutput = nil
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        isRecording = false
        recordingDuration = 0
        recordingStartTime = nil
        
        print("ScreenCaptureManager: Recording stopped")
        
        return tempURL
    }
    
    // MARK: - Private Methods
    
    private func createTempFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "AutoCallRecorder-\(timestamp).mov"
        return tempDir.appendingPathComponent(filename)
    }
    
    private func setupAssetWriter(url: URL, display: SCDisplay) throws {
        // Remove existing file if any
        try? FileManager.default.removeItem(at: url)
        
        // Create asset writer
        let writer = try AVAssetWriter(url: url, fileType: .mov)
        
        // Calculate output dimensions
        let displayAspect = CGFloat(display.width) / CGFloat(display.height)
        let targetAspect = CGFloat(targetWidth) / CGFloat(targetHeight)
        
        var outputWidth: Int
        var outputHeight: Int
        
        if displayAspect > targetAspect {
            outputWidth = targetWidth
            outputHeight = Int(CGFloat(targetWidth) / displayAspect)
        } else {
            outputHeight = targetHeight
            outputWidth = Int(CGFloat(targetHeight) * displayAspect)
        }
        
        // Make dimensions even
        outputWidth = (outputWidth / 2) * 2
        outputHeight = (outputHeight / 2) * 2
        
        // Video input settings - H.264 with hardware acceleration
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputWidth,
            AVVideoHeightKey: outputHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000, // 8 Mbps
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        
        // Audio input settings
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]
        
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        
        // Add inputs
        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        if writer.canAdd(audioInput) {
            writer.add(audioInput)
        }
        
        // Start writing
        writer.startWriting()
        
        self.assetWriter = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
    }
    
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard isRecording,
              let writer = assetWriter,
              writer.status == .writing else { return }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        // Start session on first sample
        if writer.status == .writing && videoInput?.isReadyForMoreMediaData == true {
            // Ensure session is started
            if case .unknown = writer.status {
                writer.startSession(atSourceTime: timestamp)
            }
        }
        
        switch type {
        case .screen:
            // Handle video frame
            if let videoInput = videoInput,
               videoInput.isReadyForMoreMediaData,
               let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                
                // Create a new sample buffer with just the image
                var newSampleBuffer: CMSampleBuffer?
                var timingInfo = CMSampleTimingInfo(
                    duration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
                    presentationTimeStamp: timestamp,
                    decodeTimeStamp: .invalid
                )
                var formatDescription: CMFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(
                    allocator: kCFAllocatorDefault,
                    imageBuffer: imageBuffer,
                    formatDescriptionOut: &formatDescription
                )
                
                if let formatDescription = formatDescription {
                    CMSampleBufferCreateReadyWithImageBuffer(
                        allocator: kCFAllocatorDefault,
                        imageBuffer: imageBuffer,
                        formatDescription: formatDescription,
                        sampleTiming: &timingInfo,
                        sampleBufferOut: &newSampleBuffer
                    )
                    
                    if let newSampleBuffer = newSampleBuffer {
                        videoInput.append(newSampleBuffer)
                    }
                }
            }
            
        case .audio:
            // Handle audio sample
            if let audioInput = audioInput,
               audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            }
            
        case .microphone:
            // We could mix microphone audio here if needed
            break
            
        @unknown default:
            break
        }
    }
    
    private func finishWriting() async {
        guard let writer = assetWriter else { return }
        
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                if writer.status == .failed {
                    print("ScreenCaptureManager: Asset writer failed: \(writer.error?.localizedDescription ?? "unknown")")
                }
                continuation.resume()
            }
        }
    }
    
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}

// MARK: - Stream Output Handler

private class CaptureStreamOutput: NSObject, SCStreamOutput {
    let handler: (CMSampleBuffer, SCStreamOutputType) -> Void
    private var hasStartedSession = false
    private var sessionStartTime: CMTime?
    
    init(handler: @escaping (CMSampleBuffer, SCStreamOutputType) -> Void) {
        self.handler = handler
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        
        // Initialize session start time on first sample
        if sessionStartTime == nil {
            sessionStartTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        }
        
        handler(sampleBuffer, type)
    }
}

