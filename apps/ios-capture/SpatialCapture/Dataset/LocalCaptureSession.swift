import Foundation

/// In-memory handle for a locally stored capture session.
struct LocalCaptureSession: Identifiable, Equatable {
    var id: String { manifest.sessionId }
    var manifest: CaptureSessionManifest
    var directoryURL: URL

    var videoURL: URL? {
        guard let videoPath = manifest.videoPath else { return nil }
        return directoryURL.appendingPathComponent(videoPath)
    }

    // TODO: Load existing sessions from Documents/captures/.
    // TODO: Attach msplat GaussianDatasetProtocol adapter when bridge is wired.
}
