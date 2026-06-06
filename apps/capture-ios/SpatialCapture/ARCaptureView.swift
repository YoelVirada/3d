import ARKit
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

    private let session = ARSession()
    private var builder = ARPackageBuilder()
    private var frameData: [(String, Data)] = []
    private let statusLabel = UILabel()
    private let stopButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        statusLabel.textColor = .white
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        stopButton.setTitle("Finish AR Capture", for: .normal)
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.addTarget(self, action: #selector(finishCapture), for: .touchUpInside)
        view.addSubview(statusLabel)
        view.addSubview(stopButton)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stopButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            stopButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
        session.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard ARWorldTrackingConfiguration.isSupported else {
            statusLabel.text = "ARKit world tracking not supported on this device."
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        session.run(config)
        statusLabel.text = "AR capture running… Move slowly around the object."
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let state: String
        switch frame.camera.trackingState {
        case .normal: state = "normal"
        case .limited(let reason): state = "limited_\(reason)"
        case .notAvailable: state = "not_available"
        }
        guard let jpeg = builder.trySample(
            pixelBuffer: frame.capturedImage,
            frame: frame,
            trackingState: state
        ) else { return }
        if let last = builder.poses.last {
            frameData.append((last.frame, jpeg))
        }
        DispatchQueue.main.async {
            self.statusLabel.text = "Frames: \(self.builder.poses.count) · rejected: \(self.builder.rejectedCount)"
        }
    }

    @objc private func finishCapture() {
        session.pause()
        guard !builder.poses.isEmpty else {
            statusLabel.text = "No AR frames captured."
            return
        }
        do {
            let zip = try builder.buildZip(
                captureMeta: CaptureMetadata.current(),
                frames: frameData
            )
            onComplete?(zip)
        } catch {
            statusLabel.text = "Zip error: \(error.localizedDescription)"
        }
    }
}
