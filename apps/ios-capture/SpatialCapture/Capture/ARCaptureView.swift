import ARKit
import SceneKit
import SwiftUI

/// Guided AR capture with live tracking feedback.
/// Output is structured for local session storage (video + future frame metadata).
struct ARCaptureView: UIViewControllerRepresentable {
    let onComplete: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> ARCaptureViewController {
        let vc = ARCaptureViewController()
        vc.onComplete = onComplete
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ uiViewController: ARCaptureViewController, context: Context) {}
}

final class ARCaptureViewController: UIViewController, ARSessionDelegate {
    var onComplete: ((URL) -> Void)?
    var onCancel: (() -> Void)?

    private let sceneView = ARSCNView()
    private var recorder: ARVideoRecorder?
    private let statusBackground = UIView()
    private let statusLabel = UILabel()
    private let recordButton = UIButton(type: .system)
    private var captureStartTime: Date?
    private var latestTrackingState = CaptureTrackingState.unknown
    private var isRecording = false
  // TODO: Accumulate CapturedFrameMetadata per ARFrame during recording.
    private var pendingManifest: CaptureSessionManifest?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.automaticallyUpdatesLighting = true
        view.addSubview(sceneView)
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        sceneView.session.delegate = self

        statusBackground.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusBackground.layer.cornerRadius = 8
        statusBackground.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .white
        statusLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBackground.addSubview(statusLabel)
        view.addSubview(statusBackground)

        recordButton.setTitle("Start Recording", for: .normal)
        recordButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        recordButton.backgroundColor = .systemRed
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.layer.cornerRadius = 10
        recordButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        view.addSubview(recordButton)

        NSLayoutConstraint.activate([
            statusBackground.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statusBackground.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            statusLabel.topAnchor.constraint(equalTo: statusBackground.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: statusBackground.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: statusBackground.trailingAnchor, constant: -10),
            statusLabel.bottomAnchor.constraint(equalTo: statusBackground.bottomAnchor, constant: -8),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        updateOverlay(message: "Starting AR capture…")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard ARWorldTrackingConfiguration.isSupported else {
            updateOverlay(message: "ARKit world tracking not supported on this device.")
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        sceneView.session.run(config)
        updateOverlay(message: "Move slowly around the object. Tap Start Recording when ready.")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    private func updateOverlay(message: String? = nil) {
        if let message {
            statusLabel.text = message
            return
        }
        let elapsed = Int(Date().timeIntervalSince(captureStartTime ?? Date()))
        let frames = recorder?.frameCount ?? 0
        statusLabel.text = """
        \(isRecording ? "REC" : "ready") · \(elapsed)s · \(frames) frames
        tracking: \(latestTrackingState.rawValue)
        Keep motion slow; cover all sides.
        """
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestTrackingState = Self.trackingState(from: frame.camera.trackingState)

        if isRecording {
            recorder?.append(frame: frame)

            // TODO: Extract CameraIntrinsics from frame.camera (imageResolution, intrinsics matrix).
            // TODO: Extract CameraPose from frame.camera.transform (column-major 4×4 cam-to-world).
            // TODO: Record frame.timestamp and tracking quality into CapturedFrameMetadata.
            // TODO: Optionally write frame.capturedImage to session frames/ directory via ImageStorage.
            // TODO: Append frame metadata to pendingManifest.frames.
        }

        DispatchQueue.main.async {
            self.updateOverlay()
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.updateOverlay(message: "AR session failed: \(error.localizedDescription)")
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            self.updateOverlay(message: "AR session interrupted — waiting to resume…")
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        sceneView.session.run(config, options: [.resetTracking])
        DispatchQueue.main.async {
            self.updateOverlay(message: "Capture resumed — keep moving slowly.")
        }
    }

    @objc private func toggleRecording() {
        if isRecording {
            finishRecording()
            return
        }
        let recorder = ARVideoRecorder()
        do {
            let res = sceneView.session.currentFrame?.camera.imageResolution
                ?? CGSize(width: 1920, height: 1440)
            try recorder.start(width: Int(res.width), height: Int(res.height))
        } catch {
            updateOverlay(message: "Recorder error: \(error.localizedDescription)")
            return
        }
        self.recorder = recorder
        captureStartTime = Date()
        isRecording = true
        recordButton.setTitle("Finish Recording", for: .normal)
        recordButton.backgroundColor = .systemBlue

        let device = UIDevice.current
        let build = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        pendingManifest = CaptureSessionManifest.newSession(
            captureMode: "ar_guided",
            deviceModel: device.model,
            osVersion: device.systemVersion,
            appVersion: build
        )

        updateOverlay()
    }

    private func finishRecording() {
        isRecording = false
        guard let recorder else { return }
        guard recorder.frameCount > 0 else {
            updateOverlay(message: "No frames recorded.")
            return
        }
        recordButton.isEnabled = false
        updateOverlay(message: "Finalizing capture…")
        Task { @MainActor in
            do {
                let url = try await recorder.finish()
                // TODO: Copy video into LocalCaptureSession directory as video.mov.
                // TODO: Write manifest.json via CaptureSessionLayout.saveManifest.
                // TODO: Export intrinsics.json / poses for msplat COLMAP-style ingest.
                self.sceneView.session.pause()
                self.onComplete?(url)
            } catch {
                self.recordButton.isEnabled = true
                self.updateOverlay(message: "Finalize error: \(error.localizedDescription)")
            }
        }
    }

    private static func trackingState(from state: ARCamera.TrackingState) -> CaptureTrackingState {
        switch state {
        case .normal:
            return .normal
        case .limited:
            return .limited
        case .notAvailable:
            return .notAvailable
        }
    }
}
