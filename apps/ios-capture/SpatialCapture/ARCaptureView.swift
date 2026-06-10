import ARKit
import SceneKit
import SwiftUI

/// Guided video capture backed by ARKit.
///
/// ARKit's role here is capture assistance only: live camera preview plus
/// tracking-quality feedback so the user keeps slow, well-lit, parallax-rich
/// motion. The output is a plain video file — no poses, no AR package.
/// COLMAP on the server recovers camera geometry from the video.
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
    private var latestTrackingState = "initializing"
    private var isRecording = false

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

        updateOverlay(message: "Starting AR-assisted capture…")
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
        tracking: \(latestTrackingState)
        Keep motion slow; cover all sides.
        """
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        switch frame.camera.trackingState {
        case .normal:
            latestTrackingState = "normal"
        case .limited(let reason):
            latestTrackingState = "limited_\(reason)"
        case .notAvailable:
            latestTrackingState = "not_available"
        }
        if isRecording {
            recorder?.append(frame: frame)
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
        updateOverlay(message: "Finalizing video…")
        Task { @MainActor in
            do {
                let url = try await recorder.finish()
                self.sceneView.session.pause()
                self.onComplete?(url)
            } catch {
                self.recordButton.isEnabled = true
                self.updateOverlay(message: "Finalize error: \(error.localizedDescription)")
            }
        }
    }
}
