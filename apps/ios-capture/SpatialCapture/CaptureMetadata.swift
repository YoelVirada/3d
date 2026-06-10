import UIKit
import AVFoundation

struct CaptureMetadata: Codable {
    var device_model: String
    var os_version: String?
    var app_version: String?
    var camera_type: String
    var resolution: String?
    var duration_s: Double?
    var orientation: String
    var timestamp: String
    var network_type: String?

    static func current() -> CaptureMetadata {
        let device = UIDevice.current
        let formatter = ISO8601DateFormatter()
        let build = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return CaptureMetadata(
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

    static func withVideo(url: URL) -> CaptureMetadata {
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
