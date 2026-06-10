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
    @State private var uploadProgress: Double = 0
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server (capture upload)") {
                    TextField("Base URL", text: $settings.serverBaseURL, prompt: Text("http://10.100.102.12:8787"))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Text("Upload server runs the Mobile-GS pipeline on the GPU host.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Scene ID", text: $settings.sceneId)
                }
                Section("Capture video") {
                    Button("Guided Capture (AR-assisted)") { showAR = true }
                    Button("Record Video (camera)") { showCamera = true }
                    Button("Choose Video from Library") { showPicker = true }
                    if let url = lastVideoURL {
                        Text("Video: \(url.lastPathComponent)").font(.caption)
                    }
                }
                Section("Upload & pipeline") {
                    Button("Upload and start pipeline") {
                        Task { await uploadAndPoll() }
                    }
                    .disabled(lastVideoURL == nil || isBusy)
                    if isBusy && uploadProgress < 1 {
                        ProgressView(value: uploadProgress)
                    }
                    Text(status).font(.caption)
                }
            }
            .navigationTitle("Spatial Capture")
            .sheet(isPresented: $showAR) {
                ARCaptureView(
                    onComplete: { url in
                        lastVideoURL = url
                        showAR = false
                        status = "Video ready (\(url.lastPathComponent))"
                    },
                    onCancel: { showAR = false }
                )
            }
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
        guard let videoURL = lastVideoURL else {
            status = "No video selected"
            return
        }
        isBusy = true
        uploadProgress = 0
        status = "Uploading…"

        do {
            let resp = try await RunAPI.uploadVideo(
                baseURL: settings.serverBaseURL,
                sceneId: settings.sceneId,
                videoURL: videoURL,
                metadata: CaptureMetadata.current(),
                onProgress: { p in uploadProgress = p }
            )
            uploadProgress = 1
            status = "Uploaded (\(resp.bytes) bytes) — pipeline \(resp.status)"

            while true {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                let st = try await RunAPI.fetchStatus(
                    baseURL: settings.serverBaseURL,
                    sceneId: settings.sceneId
                )
                status = "\(st.status) · \(st.stage ?? "—")"
                if st.status == "completed" {
                    if let artifact = st.artifact {
                        status = "Complete — asset: \(artifact)"
                    } else {
                        status = "Complete"
                    }
                    break
                }
                if st.status == "failed" {
                    status = "Failed: \(st.detail ?? "unknown")"
                    break
                }
            }
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
        isBusy = false
    }
}
