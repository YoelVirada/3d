import Foundation

/// Top-level manifest for a locally stored capture session.
struct CaptureSessionManifest: Codable, Equatable {
    var sessionId: String
    var createdAt: Date
    var deviceModel: String
    var osVersion: String
    var appVersion: String?
    var captureMode: String
    /// Relative path to companion video, e.g. `video.mov`.
    var videoPath: String?
    var frames: [CapturedFrameMetadata]
    var notes: String?

    static func newSession(
        captureMode: String,
        deviceModel: String,
        osVersion: String,
        appVersion: String?
    ) -> CaptureSessionManifest {
        CaptureSessionManifest(
            sessionId: UUID().uuidString,
            createdAt: Date(),
            deviceModel: deviceModel,
            osVersion: osVersion,
            appVersion: appVersion,
            captureMode: captureMode,
            videoPath: nil,
            frames: [],
            notes: nil
        )
    }
}
