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
        var zipEntries: [ZipEntry] = []
        for (name, data) in entries {
            let offset = UInt32(out.count)
            let nameData = Data(name.utf8)
            let size = UInt32(data.count)
            let crc = zipCRC32(of: data)
            let local = localHeader(name: nameData, size: size, crc: crc)
            out.append(local)
            out.append(data)
            zipEntries.append(ZipEntry(name: name, offset: offset, crc: crc, size: size))
        }
        let cdStart = UInt32(out.count)
        for entry in zipEntries {
            out.append(
                centralDir(
                    name: Data(entry.name.utf8),
                    offset: entry.offset,
                    comp: entry.size,
                    uncomp: entry.size,
                    crc: entry.crc
                )
            )
        }
        let cdSize = UInt32(out.count) - cdStart
        out.append(endRecord(count: UInt16(entries.count), cdSize: cdSize, cdStart: cdStart))
        try out.write(to: zipURL)
        #if DEBUG
        try validateStoreZip(at: zipURL)
        #endif
    }

    /// PKZIP CRC-32 for store-only ZIP entries.
    static func zipCRC32(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crc32Table[idx]
        }
        return crc ^ 0xFFFF_FFFF
    }

    #if DEBUG
    /// Parse a store-only ZIP written by this module and verify entry CRC-32 values.
    static func validateStoreZip(at url: URL) throws {
        let zip = try Data(contentsOf: url)
        var offset = 0
        var entryCount = 0
        while offset + 30 <= zip.count {
            let sig = zip.readUInt32LE(at: offset)
            guard sig == 0x0403_4B50 else { break }
            let crc = zip.readUInt32LE(at: offset + 14)
            let compSize = zip.readUInt32LE(at: offset + 18)
            let uncompSize = zip.readUInt32LE(at: offset + 22)
            let nameLen = Int(zip.readUInt16LE(at: offset + 26))
            let extraLen = Int(zip.readUInt16LE(at: offset + 28))
            let dataStart = offset + 30 + nameLen + extraLen
            guard compSize == uncompSize else {
                throw ZipValidationError.compressionNotSupported
            }
            guard dataStart + Int(compSize) <= zip.count else {
                throw ZipValidationError.truncatedEntry
            }
            let payload = zip.subdata(in: dataStart..<(dataStart + Int(compSize)))
            guard zipCRC32(of: payload) == crc else {
                throw ZipValidationError.badCRC
            }
            offset = dataStart + Int(compSize)
            entryCount += 1
        }
        guard entryCount > 0 else {
            throw ZipValidationError.emptyArchive
        }
    }
    #endif

    private struct ZipEntry {
        let name: String
        let offset: UInt32
        let crc: UInt32
        let size: UInt32
    }

    private static let crc32Table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    private static func localHeader(name: Data, size: UInt32, crc: UInt32) -> Data {
        var d = Data()
        d.appendLE(UInt32(0x04034b50))
        d.appendLE(UInt16(20))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(crc)
        d.appendLE(size)
        d.appendLE(size)
        d.appendLE(UInt16(name.count))
        d.appendLE(UInt16(0))
        d.append(name)
        return d
    }

    private static func centralDir(
        name: Data,
        offset: UInt32,
        comp: UInt32,
        uncomp: UInt32,
        crc: UInt32
    ) -> Data {
        var d = Data()
        d.appendLE(UInt32(0x02014b50))
        d.appendLE(UInt16(20))
        d.appendLE(UInt16(20))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(UInt16(0))
        d.appendLE(crc)
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

private enum ZipValidationError: Error {
    case badCRC
    case compressionNotSupported
    case truncatedEntry
    case emptyArchive
}

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    mutating func appendLE(_ v: UInt16) {
        var x = v.littleEndian
        append(Data(bytes: &x, count: 2))
    }
    mutating func appendLE(_ v: UInt32) {
        var x = v.littleEndian
        append(Data(bytes: &x, count: 4))
    }
}
