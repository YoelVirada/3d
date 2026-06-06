import SwiftUI
import PhotosUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var settings: CaptureSettings
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var showAR = false
    @State private var status = "Ready"
    @State private var lastVideoURL: URL?
    @State private var lastARZipURL: URL?
    @State private var runId: String?
    @State private var viewerURL: String?
    @State private var uploadProgress: Double = 0
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server (WSL capture API)") {
                    TextField("Base URL", text: $settings.serverBaseURL, prompt: Text("http://10.100.102.12:8787"))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Text("WSL capture server at http://10.100.102.12:8787")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Scene ID", text: $settings.sceneId)
                }
                Section("Capture (ARKit default)") {
                    Button("Record AR Capture") { showAR = true }
                    Button("Record Video (legacy / COLMAP)") { showCamera = true }
                    Button("Choose Video from Library") { showPicker = true }
                    if let url = lastARZipURL {
                        Text("AR: \(url.lastPathComponent)").font(.caption)
                    }
                    if let url = lastVideoURL {
                        Text("Video: \(url.lastPathComponent)").font(.caption)
                    }
                }
                Section("Upload & pipeline") {
                    Button("Upload and run pipeline") {
                        Task { await uploadAndPoll() }
                    }
                    .disabled((lastARZipURL == nil && lastVideoURL == nil) || isBusy)
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
                    }
                }
            }
            .navigationTitle("Spatial Capture")
            .sheet(isPresented: $showAR) {
                ARCaptureView(
                    onComplete: { url in
                        lastARZipURL = url
                        lastVideoURL = nil
                        showAR = false
                        status = "AR package ready (\(url.lastPathComponent))"
                    },
                    onCancel: { showAR = false }
                )
            }
            .sheet(isPresented: $showCamera) {
                CameraView { url in
                    lastVideoURL = url
                    lastARZipURL = nil
                    showCamera = false
                }
            }
            .sheet(isPresented: $showPicker) {
                VideoPicker { url in
                    lastVideoURL = url
                    lastARZipURL = nil
                    showPicker = false
                }
            }
        }
    }

    func uploadAndPoll() async {
        isBusy = true
        viewerURL = nil
        runId = nil
        uploadProgress = 0
        status = "Uploading…"
        let t0 = Date()

        do {
            let resp: UploadResponse
            if let arZip = lastARZipURL {
                resp = try await RunAPI.uploadARPackage(
                    baseURL: settings.serverBaseURL,
                    sceneId: settings.sceneId,
                    zipURL: arZip,
                    metadata: CaptureMetadata.current()
                )
            } else if let videoURL = lastVideoURL {
                resp = try await RunAPI.upload(
                    baseURL: settings.serverBaseURL,
                    sceneId: settings.sceneId,
                    videoURL: videoURL,
                    metadata: CaptureMetadata.current(),
                    onProgress: { p in uploadProgress = p }
                )
            } else {
                status = "No capture selected"
                isBusy = false
                return
            }
            runId = resp.run_id
            uploadProgress = 1
            try? await RunAPI.postMobileMetrics(
                baseURL: settings.serverBaseURL,
                runId: resp.run_id,
                payload: [
                    "device_model": CaptureMetadata.current().device_model,
                    "os_version": CaptureMetadata.current().os_version as Any,
                    "app_version": CaptureMetadata.current().app_version as Any,
                    "uploaded_video_bytes": resp.bytes,
                    "upload_duration_sec": Date().timeIntervalSince(t0),
                    "extra": ["source": "capture-ios", "phase": "upload", "capture_mode": resp.capture_mode ?? "unknown"],
                ]
            )
            status = "Uploaded — \(resp.capture_mode ?? "capture") — \(resp.status)"

            while true {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                let st = try await RunAPI.fetchStatus(
                    baseURL: settings.serverBaseURL,
                    runId: resp.run_id
                )
                status = "\(st.status) · \(st.current_stage ?? "—") · \(Int(st.elapsed_sec))s"
                if st.status == "completed" || st.status == "failed" { break }
            }

            let result = try await RunAPI.fetchResult(
                baseURL: settings.serverBaseURL,
                runId: resp.run_id
            )
            if result.status == "completed", let v = result.viewer_url {
                viewerURL = v.contains("benchmark=1") ? v : v + "&benchmark=1"
                status = "Complete — open viewer"
            } else {
                status = "Failed: \(result.failure_reason ?? "unknown")"
            }
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
        isBusy = false
    }
}
