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
                Section("Local capture") {
                    TextField("Session label", text: $settings.sessionLabel)
                    Text("Captures are stored locally for on-device msplat experiments.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Guided Capture (AR-assisted)") { showAR = true }
                    Button("Record Video (camera)") { showCamera = true }
                    Button("Choose Video from Library") { showPicker = true }
                    if let url = lastVideoURL {
                        Text("Video: \(url.lastPathComponent)").font(.caption)
                    }
                }

                Section("Status") {
                    Text(status).font(.caption)
                }

                if settings.legacyServerUploadEnabled {
                    Section("Legacy: server upload (debug)") {
                        TextField("Base URL", text: $settings.legacyServerBaseURL, prompt: Text("http://10.100.102.12:8787"))
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        TextField("Scene ID", text: $settings.legacySceneId)
                        Button("Upload to legacy GPU pipeline") {
                            Task { await legacyUploadAndPoll() }
                        }
                        .disabled(lastVideoURL == nil || isBusy)
                        if isBusy && uploadProgress < 1 {
                            ProgressView(value: uploadProgress)
                        }
                    }
                }
            }
            .navigationTitle("3DGS Capture")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Legacy upload", isOn: $settings.legacyServerUploadEnabled)
                        .labelsHidden()
                }
            }
            .sheet(isPresented: $showAR) {
                ARCaptureView(
                    onComplete: { url in
                        lastVideoURL = url
                        showAR = false
                        status = "Capture ready (\(url.lastPathComponent))"
                    },
                    onCancel: { showAR = false }
                )
            }
            .sheet(isPresented: $showCamera) {
                CameraView { url in
                    lastVideoURL = url
                    showCamera = false
                    status = "Capture ready (\(url.lastPathComponent))"
                }
            }
            .sheet(isPresented: $showPicker) {
                VideoPicker { url in
                    lastVideoURL = url
                    showPicker = false
                    status = "Capture ready (\(url.lastPathComponent))"
                }
            }
        }
    }

    func legacyUploadAndPoll() async {
        guard let videoURL = lastVideoURL else {
            status = "No capture selected"
            return
        }
        isBusy = true
        uploadProgress = 0
        status = "Legacy upload…"

        do {
            let resp = try await LegacyUploadAPI.uploadVideo(
                baseURL: settings.legacyServerBaseURL,
                sceneId: settings.legacySceneId,
                videoURL: videoURL,
                metadata: LegacyCaptureMetadata.withVideo(url: videoURL),
                onProgress: { p in uploadProgress = p }
            )
            uploadProgress = 1
            status = "Uploaded (\(resp.bytes) bytes) — \(resp.status)"

            while true {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                let st = try await LegacyUploadAPI.fetchStatus(
                    baseURL: settings.legacyServerBaseURL,
                    sceneId: settings.legacySceneId
                )
                status = "\(st.status) · \(st.stage ?? "—")"
                if st.status == "completed" {
                    status = st.artifact.map { "Complete — \($0)" } ?? "Complete"
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
