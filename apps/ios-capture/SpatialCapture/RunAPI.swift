import Foundation

struct UploadResponse: Decodable {
    let scene_id: String
    let status: String
    let bytes: Int
}

struct CaptureStatus: Decodable {
    let scene_id: String
    let status: String
    let stage: String?
    let detail: String?
    let artifact: String?
}

/// Minimal client for the capture-upload server.
/// Upload a video, then poll status until the Mobile-GS pipeline completes.
/// The server never streams rendered frames back — the produced artifact is a
/// compressed Mobile-GS asset (comp.xz) for the native runtime to download.
enum RunAPI {
    static func uploadVideo(
        baseURL: String,
        sceneId: String,
        videoURL: URL,
        metadata: CaptureMetadata,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> UploadResponse {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/captures/\(sceneId)") else {
            throw URLError(.badURL)
        }

        let meta = CaptureMetadata.withVideo(url: videoURL)

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        let metaData = try JSONEncoder().encode(meta)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"metadata\"\r\n\r\n".data(using: .utf8)!)
        body.append(metaData)
        body.append("\r\n".data(using: .utf8)!)

        let videoData = try Data(contentsOf: videoURL)
        let filename = videoURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!
        )
        body.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        onProgress?(1.0)
        return try JSONDecoder().decode(UploadResponse.self, from: data)
    }

    static func fetchStatus(baseURL: String, sceneId: String) async throws -> CaptureStatus {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/captures/\(sceneId)/status") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(CaptureStatus.self, from: data)
    }
}
