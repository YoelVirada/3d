import Foundation

struct UploadResponse: Decodable {
    let scene_id: String
    let run_id: String
    let status: String
    let bytes: Int
    let upload_duration_sec: Double?
    let status_url: String?
    let result_url: String?
    let capture_mode: String?
}

struct RunStatus: Decodable {
    let run_id: String
    let scene_id: String
    let status: String
    let current_stage: String?
    let progress: Double?
    let failure_reason: String?
    let elapsed_sec: Double
}

struct RunResult: Decodable {
    let run_id: String
    let scene_id: String
    let status: String
    let manifest_url: String?
    let viewer_url: String?
    let report_url: String?
    let failure_reason: String?
}

enum RunAPI {
    static func upload(
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

        var meta = metadata
        meta = CaptureMetadata.withVideo(url: videoURL)

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
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"start_pipeline\"\r\n\r\n".data(using: .utf8)!)
        body.append("true\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"profile\"\r\n\r\n".data(using: .utf8)!)
        body.append("dev\r\n".data(using: .utf8)!)

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

    static func uploadARPackage(
        baseURL: String,
        sceneId: String,
        zipURL: URL,
        metadata: CaptureMetadata
    ) async throws -> UploadResponse {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/captures/\(sceneId)") else {
            throw URLError(.badURL)
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        let metaData = try JSONEncoder().encode(metadata)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"metadata\"\r\n\r\n".data(using: .utf8)!)
        body.append(metaData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"start_pipeline\"\r\n\r\n".data(using: .utf8)!)
        body.append("true\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"profile\"\r\n\r\n".data(using: .utf8)!)
        body.append("dev\r\n".data(using: .utf8)!)

        let zipData = try Data(contentsOf: zipURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"ar_package\"; filename=\"ar_capture.zip\"\r\n".data(using: .utf8)!
        )
        body.append("Content-Type: application/zip\r\n\r\n".data(using: .utf8)!)
        body.append(zipData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(UploadResponse.self, from: data)
    }

    static func fetchStatus(baseURL: String, runId: String) async throws -> RunStatus {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/runs/\(runId)/status") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(RunStatus.self, from: data)
    }

    static func fetchResult(baseURL: String, runId: String) async throws -> RunResult {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/runs/\(runId)/result") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 409 {
            throw URLError(.resourceUnavailable)
        }
        guard http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(RunResult.self, from: data)
    }

    static func postMobileMetrics(
        baseURL: String,
        runId: String,
        payload: [String: Any]
    ) async throws {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/runs/\(runId)/mobile-metrics") else {
            throw URLError(.badURL)
        }
        var body = payload
        body["run_id"] = runId
        if body["timestamp"] == nil {
            body["timestamp"] = ISO8601DateFormatter().string(from: Date())
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
