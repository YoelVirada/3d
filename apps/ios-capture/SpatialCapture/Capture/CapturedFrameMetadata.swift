import Foundation

/// Per-frame capture record for future msplat/COLMAP export.
struct CapturedFrameMetadata: Codable, Equatable {
    var frameIndex: Int
    var timestamp: TimeInterval
    var intrinsics: CameraIntrinsics
    var pose: CameraPose
    /// Relative path under the session directory, e.g. `frames/frame_000001.jpg`.
    var imagePath: String?
}
