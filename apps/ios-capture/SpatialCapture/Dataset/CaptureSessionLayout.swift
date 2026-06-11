import Foundation

/// On-disk layout for a local capture session (msplat / COLMAP ingest target).
enum CaptureSessionLayout {
    static let manifestFileName = "manifest.json"
    static let videoFileName = "video.mov"
    static let intrinsicsFileName = "intrinsics.json"
    static let framesDirectoryName = "frames"

    /// Application Documents/captures/<sessionId>/
    static func sessionDirectory(sessionId: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("captures", isDirectory: true)
            .appendingPathComponent(sessionId, isDirectory: true)
    }

    static func manifestURL(sessionId: String) -> URL {
        sessionDirectory(sessionId: sessionId).appendingPathComponent(manifestFileName)
    }

    static func videoURL(sessionId: String) -> URL {
        sessionDirectory(sessionId: sessionId).appendingPathComponent(videoFileName)
    }

    static func framesDirectory(sessionId: String) -> URL {
        sessionDirectory(sessionId: sessionId).appendingPathComponent(framesDirectoryName, isDirectory: true)
    }

    // TODO: Create session directory tree (frames/, manifest.json placeholder).
    // TODO: Export COLMAP-style sparse/ + images/ tree for msplat dataset loader.
    // TODO: Export msa-data bundle format once defined for on-device training.

    static func saveManifest(_ manifest: CaptureSessionManifest) throws {
        let dir = sessionDirectory(sessionId: manifest.sessionId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = manifestURL(sessionId: manifest.sessionId)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
    }
}
