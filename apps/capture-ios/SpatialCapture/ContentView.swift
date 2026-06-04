import SwiftUI
import PhotosUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var settings: CaptureSettings
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var status = "Ready"
    @State private var lastVideoURL: URL?
    @State private var runId: String?
    @State private var viewerURL: String?
    @State private var uploadProgress: Double = 0
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server (WSL capture API)") {
                    TextField("Base URL", text: $settings.serverBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Text("Use your PC LAN IP, port 8787. Example: http://192.168.1.50:8787")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Scene ID", text: $settings.sceneId)
                }
                Section("Capture") {
                    Button("Record Video") { showCamera = true }
                    Button("Choose from Library") { showPicker = true }
                    if let url = lastVideoURL {
                        Text(url.lastPathComponent).font(.caption)
                    }
                }
                Section("Upload & pipeline") {
                    Button("Upload and run pipeline") {
                        Task { await uploadAndPoll() }
                    }
                    .disabled(lastVideoURL == nil || isBusy)
                    if isBusy && uploadProgress < 1 {
                        ProgressView(value: uploadProgress)
                    }
                    Text(status).font(.caption)
                    if let rid = runId {
                        Text("Run: \(rid)").font(.caption2)
                    }
                }
                if let urlStr = viewerURL, let url = URL(string: urlStr) {
                    Section("Viewer") {
                        Link("Open Viewer in Safari", destination: url)
                        Text("Includes run_id for mobile render metrics.")
                            .font(.caption2)
                    }
                }
            }
            .navigationTitle("Spatial Capture")
            .sheet(isPresented: $showCamera) {
                CameraView { url in
                    lastVideoURL = url
                    showCamera = false
                }
            }
            .sheet(isPresented: $showPicker) {
                VideoPicker { url in
                    lastVideoURL = url
                    showPicker = false
                }
            }
        }
    }

    func uploadAndPoll() async {
        guard let videoURL = lastVideoURL else { return }
        isBusy = true
        viewerURL = nil
        runId = nil
        uploadProgress = 0
        status = "Uploading…"
        let t0 = Date()

        do {
            let resp = try await RunAPI.upload(
                baseURL: settings.serverBaseURL,
                sceneId: settings.sceneId,
                videoURL: videoURL,
                metadata: CaptureMetadata.current(),
                onProgress: { p in uploadProgress = p }
            )
            runId = resp.run_id
            uploadProgress = 1
            let videoBytes = (try? Data(contentsOf: videoURL).count) ?? resp.bytes
            let uploadSec = Date().timeIntervalSince(t0)
            try? await RunAPI.postMobileMetrics(
                baseURL: settings.serverBaseURL,
                runId: resp.run_id,
                payload: [
                    "device_model": CaptureMetadata.current().device_model,
                    "os_version": CaptureMetadata.current().os_version as Any,
                    "app_version": CaptureMetadata.current().app_version as Any,
                    "uploaded_video_bytes": videoBytes,
                    "upload_duration_sec": uploadSec,
                    "extra": ["source": "capture-ios", "phase": "upload"],
                ]
            )
            status = "Uploaded — pipeline \(resp.status)"

            while true {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                let st = try await RunAPI.fetchStatus(
                    baseURL: settings.serverBaseURL,
                    runId: resp.run_id
                )
                let stage = st.current_stage ?? "—"
                status = "\(st.status) · \(stage) · \(Int(st.elapsed_sec))s"
                if st.status == "completed" || st.status == "failed" {
                    break
                }
            }

            let result = try await RunAPI.fetchResult(
                baseURL: settings.serverBaseURL,
                runId: resp.run_id
            )
            if result.status == "completed", let v = result.viewer_url {
                let url = v.contains("benchmark=1") ? v : v + "&benchmark=1"
                viewerURL = url
                status = "Complete — open viewer (render metrics auto-report)"
            } else {
                status = "Failed: \(result.failure_reason ?? "unknown")"
            }
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
        isBusy = false
    }
}
