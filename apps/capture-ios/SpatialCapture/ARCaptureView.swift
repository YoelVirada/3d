import ARKit
import SceneKit
import SwiftUI

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
    private var builder = ARPackageBuilder()
    private var frameData: [(String, Data)] = []
    private let statusBackground = UIView()
    private let statusLabel = UILabel()
    private let stopButton = UIButton(type: .system)
    private var captureStartTime: Date?
    private var latestTrackingState = "initializing"

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

        stopButton.setTitle("Finish AR Capture", for: .normal)
        stopButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        stopButton.backgroundColor = .systemBlue
        stopButton.setTitleColor(.white, for: .normal)
        stopButton.layer.cornerRadius = 10
        stopButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.addTarget(self, action: #selector(finishCapture), for: .touchUpInside)
        view.addSubview(stopButton)

        NSLayoutConstraint.activate([
            statusBackground.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statusBackground.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            statusLabel.topAnchor.constraint(equalTo: statusBackground.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: statusBackground.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: statusBackground.trailingAnchor, constant: -10),
            statusLabel.bottomAnchor.constraint(equalTo: statusBackground.bottomAnchor, constant: -8),
            stopButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            stopButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        updateOverlay(message: "Starting AR capture…")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard ARWorldTrackingConfiguration.isSupported else {
            updateOverlay(message: "ARKit world tracking not supported on this device.")
            return
        }
        captureStartTime = Date()
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        sceneView.session.run(config)
        updateOverlay(message: "AR capture running — move slowly around the object.")
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
        statusLabel.text = """
        AR capture running
        elapsed: \(elapsed)s
        frames: \(builder.poses.count)
        rejected: \(builder.rejectedCount)
        tracking: \(latestTrackingState)
        """
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let state: String
        switch frame.camera.trackingState {
        case .normal:
            state = "normal"
        case .limited(let reason):
            state = "limited_\(reason)"
        case .notAvailable:
            state = "not_available"
        }
        latestTrackingState = state

        guard let jpeg = builder.trySample(
            pixelBuffer: frame.capturedImage,
            frame: frame,
            trackingState: state
        ) else {
            DispatchQueue.main.async {
                self.updateOverlay()
            }
            return
        }
        if let last = builder.poses.last {
            frameData.append((last.frame, jpeg))
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
            self.updateOverlay(message: "AR capture resumed — move slowly around the object.")
        }
    }

    @objc private func finishCapture() {
        sceneView.session.pause()
        guard !builder.poses.isEmpty else {
            updateOverlay(message: "No AR frames captured.")
            return
        }
        do {
            let zip = try builder.buildZip(
                captureMeta: CaptureMetadata.current(),
                frames: frameData
            )
            onComplete?(zip)
        } catch {
            updateOverlay(message: "Zip error: \(error.localizedDescription)")
        }
    }
}
