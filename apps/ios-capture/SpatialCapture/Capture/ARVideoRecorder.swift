import ARKit
import AVFoundation
import Foundation

/// Writes ARFrame camera images to a standard .mov file.
final class ARVideoRecorder {
    enum RecorderError: Error {
        case notRecording
        case writerFailed(String)
    }

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: TimeInterval?
    private(set) var frameCount = 0
    let outputURL: URL

    init() {
        outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture_\(UUID().uuidString).mov")
    }

    func start(width: Int, height: Int) throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 20_000_000,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            ]
        )
        writer.add(input)
        guard writer.startWriting() else {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.startTime = nil
        self.frameCount = 0
    }

    func append(frame: ARFrame) {
        guard let input, let adaptor, input.isReadyForMoreMediaData else { return }
        if startTime == nil {
            startTime = frame.timestamp
        }
        let elapsed = frame.timestamp - (startTime ?? frame.timestamp)
        let time = CMTime(seconds: elapsed, preferredTimescale: 600)
        if adaptor.append(frame.capturedImage, withPresentationTime: time) {
            frameCount += 1
        }
    }

    func finish() async throws -> URL {
        guard let writer, let input else {
            throw RecorderError.notRecording
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "finishWriting failed")
        }
        self.writer = nil
        self.input = nil
        self.adaptor = nil
        return outputURL
    }
}
