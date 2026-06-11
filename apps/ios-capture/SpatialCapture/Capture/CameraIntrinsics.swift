import Foundation

/// Pinhole camera intrinsics for a captured frame or session.
struct CameraIntrinsics: Codable, Equatable {
    var width: Int
    var height: Int
    var focalLengthX: Float
    var focalLengthY: Float
    var principalPointX: Float
    var principalPointY: Float

    /// Column-major 3×3 intrinsic matrix K.
    var matrixK: [Float] {
        [
            focalLengthX, 0, principalPointX,
            0, focalLengthY, principalPointY,
            0, 0, 1,
        ]
    }
}
