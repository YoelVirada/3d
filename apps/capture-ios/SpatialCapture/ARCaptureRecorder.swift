import ARKit
import CoreImage
import Foundation
import simd

struct ARFramePoseRecord: Codable {
    var frame: String
    var timestamp_s: Double
    var tracking_state: String
    var transform: [[Float]]
    var intrinsics: [[Float]]
    var width: Int
    var height: Int
}

struct ARManifestFile: Codable {
    var ar_frame_count: Int
    var rejected_count: Int
    var sample_hz: Double
    var duration_s: Double?
}

struct ARPackageBuilder {
    let sampleHz: Double = 3.0
    private(set) var poses: [ARFramePoseRecord] = []
    private(set) var rejectedCount: Int = 0
    private var frameIndex: Int = 0
    private var lastSampleTime: TimeInterval = -1
    private let minSampleInterval: TimeInterval = 1.0 / 3.0

    mutating func trySample(
        pixelBuffer: CVPixelBuffer,
        frame: ARFrame,
        trackingState: String
    ) -> Data? {
        let t = frame.timestamp
        if trackingState != "normal" {
            rejectedCount += 1
            return nil
        }
        if lastSampleTime >= 0, t - lastSampleTime < minSampleInterval {
            return nil
        }
        lastSampleTime = t
        frameIndex += 1
        let name = String(format: "frame_%05d.jpg", frameIndex)
        guard let jpeg = JPEGEncoder.jpeg(from: pixelBuffer) else { return nil }

        let cam = frame.camera
        let intr = cam.intrinsics
        let transform = cam.transform
        var matrix: [[Float]] = []
        for row in 0..<4 {
            var r: [Float] = []
            for col in 0..<4 {
                r.append(transform[col][row])
            }
            matrix.append(r)
        }
        var k: [[Float]] = []
        for row in 0..<3 {
            var r: [Float] = []
            for col in 0..<3 {
                r.append(intr[col][row])
            }
            k.append(r)
        }
        let res = cam.imageResolution
        poses.append(
            ARFramePoseRecord(
                frame: name,
                timestamp_s: t,
                tracking_state: trackingState,
                transform: matrix,
                intrinsics: k,
                width: Int(res.width),
                height: Int(res.height)
            )
        )
        return jpeg
    }

    func buildZip(
        captureMeta: CaptureMetadata,
        frames: [(String, Data)]
    ) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ar_capture_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let arDir = tmp.appendingPathComponent("ar")
        let framesDir = arDir.appendingPathComponent("frames")
        try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

        for (name, data) in frames {
            try data.write(to: framesDir.appendingPathComponent(name))
        }
        let manifest = ARManifestFile(
            ar_frame_count: poses.count,
            rejected_count: rejectedCount,
            sample_hz: sampleHz,
            duration_s: poses.last.map { $0.timestamp_s }
        )
        try JSONEncoder().encode(manifest).write(to: arDir.appendingPathComponent("manifest.json"))
        try JSONEncoder().encode(poses).write(to: arDir.appendingPathComponent("poses.json"))

        var cap = captureMeta
        let capDict: [String: Any] = [
            "capture_mode": "arkit",
            "capture_version": "1.0",
            "device_model": cap.device_model,
            "os_version": cap.os_version as Any,
            "app_version": cap.app_version as Any,
            "sample_hz": sampleHz,
            "timestamp": cap.timestamp,
        ]
        let capData = try JSONSerialization.data(withJSONObject: capDict, options: [.prettyPrinted])
        try capData.write(to: tmp.appendingPathComponent("capture.json"))

        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ar_capture_\(UUID().uuidString).zip")
        try SimpleZip.storeDirectory(source: tmp, zipURL: zipURL)
        return zipURL
    }
}

enum JPEGEncoder {
    static func jpeg(from pixelBuffer: CVPixelBuffer) -> Data? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = CIContext()
        return ctx.jpegRepresentation(of: ci, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85])
    }
}

enum SimpleZip {
    /// Store-only ZIP (no compression) for ar_capture upload.
    static func storeDirectory(source: URL, zipURL: URL) throws {
        var entries: [(String, Data)] = []
        let fm = FileManager.default
        let base = source.path + "/"
        if let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
                if isDir.boolValue { continue }
                let rel = String(fileURL.path.dropFirst(base.count))
                entries.append((rel, try Data(contentsOf: fileURL)))
            }
        }
        var out = Data()
        var offsets: [(String, UInt32, UInt32, UInt32)] = []
        for (name, data) in entries {
            let offset = UInt32(out.count)
            let nameData = Data(name.utf8)
            let local = localHeader(name: nameData, size: UInt32(data.count))
            out.append(local)
            out.append(data)
            offsets.append((name, offset, UInt32(data.count), UInt32(data.count)))
        }
        let cdStart = UInt32(out.count)
        for (name, offset, comp, uncomp) in offsets {
            out.append(centralDir(name: Data(name.utf8), offset: offset, comp: comp, uncomp: uncomp))
        }
        let cdSize = UInt32(out.count) - cdStart
        out.append(endRecord(count: UInt16(entries.count), cdSize: cdSize, cdStart: cdStart))
        try out.write(to: zipURL)
    }

    private static func localHeader(name: Data, size: UInt32) -> Data {
        var d = Data()
        d.appendLE(UInt32(0x04034b50))
        d.appendLE(UInt16(20))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt32(0))
        d.appendLE(size)
        d.appendLE(size)
        d.appendLE(UInt16(name.count))
        d.appendLE(UInt16(0))
        d.append(name)
        return d
    }

    private static func centralDir(name: Data, offset: UInt32, comp: UInt32, uncomp: UInt32) -> Data {
        var d = Data()
        d.appendLE(UInt32(0x02014b50))
        d.appendLE(UInt16(20))
        d.appendLE(UInt16(20))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt32(0))
        d.appendLE(comp)
        d.appendLE(uncomp)
        d.appendLE(UInt16(name.count))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt32(0))
        d.appendLE(offset)
        d.append(name)
        return d
    }

    private static func endRecord(count: UInt16, cdSize: UInt32, cdStart: UInt32) -> Data {
        var d = Data()
        d.appendLE(UInt32(0x06054b50))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(count)
        d.appendLE(count)
        d.appendLE(cdSize)
        d.appendLE(cdStart)
        d.appendLE(UInt16(0))
        return d
    }
}

private extension Data {
    mutating func appendLE(_ v: UInt16) {
        var x = v.littleEndian
        append(Data(bytes: &x, count: 2))
    }
    mutating func appendLE(_ v: UInt32) {
        var x = v.littleEndian
        append Data(bytes: &x, count: 4))
    }
}
