import Foundation

/// Camera pose in world space (ARKit camera-to-world).
struct CameraPose: Codable, Equatable {
    var timestamp: TimeInterval
    /// Column-major 4×4 cam-to-world transform.
    var transform: [Float]
    var trackingState: CaptureTrackingState
}
