import Foundation

/// JPEG/HEIF frame storage for structured capture sessions.
enum ImageStorage {
    // TODO: Write ARFrame pixel buffers to frames/frame_NNNNNN.jpg.
    // TODO: Choose ImageIO vs CoreImage encoding; respect session downscale policy.
    // TODO: Return relative path for CapturedFrameMetadata.imagePath.

    static func frameFileName(index: Int) -> String {
        String(format: "frame_%06d.jpg", index)
    }
}
