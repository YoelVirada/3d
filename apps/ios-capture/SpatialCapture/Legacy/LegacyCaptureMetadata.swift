import UIKit
import AVFoundation

/// Metadata JSON for the legacy server upload path.
struct LegacyCaptureMetadata: Codable {
    var device_model: String
    var os_version: String?
    var app_version: String?
    var camera_type: String
    var resolution: String?
    var duration_s: Double?
    var orientation: String
    var timestamp: String
    var network_type: String?

    static func current() -> LegacyCaptureMetadata {
        let device = UIDevice.current
        let formatter = ISO8601DateFormatter()
        let build = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return LegacyCaptureMetadata(
            device_model: device.model,
            os_version: device.systemVersion,
            app_version: build,
            camera_type: "avfoundation",
            resolution: nil,
            duration_s: nil,
            orientation: UIDevice.current.orientation.isPortrait ? "portrait" : "landscape",
            timestamp: formatter.string(from: Date()),
            network_type: nil
        )
    }

    static func withVideo(url: URL) -> LegacyCaptureMetadata {
        var m = current()
        let asset = AVAsset(url: url)
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize
            m.resolution = "\(Int(size.width))x\(Int(size.height))"
        }
        m.duration_s = CMTimeGetSeconds(asset.duration)
        return m
    }
}
