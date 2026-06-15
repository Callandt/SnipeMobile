import SwiftUI
import AVFoundation
import UIKit

#if os(iOS)
/// QR scan errors.
enum ScanError: Error {
    case badInput
    case badOutput
    case initError(Error)
    case permissionDenied
}

/// Successful scan result.
struct ScanResult {
    let string: String
    let type: AVMetadataObject.ObjectType
    let image: UIImage?
    let corners: [CGPoint]
}

struct ZoomableQRScannerView: UIViewControllerRepresentable {
    typealias ScanCompletion = (Result<ScanResult, ScanError>) -> Void

    let completion: ScanCompletion
    let supportedTypes: [AVMetadataObject.ObjectType]
    // Keep scanning after a hit instead of stopping (debounced).
    let continuous: Bool

    init(
        completion: @escaping ScanCompletion,
        supportedTypes: [AVMetadataObject.ObjectType] = [.qr],
        continuous: Bool = false
    ) {
        self.completion = completion
        self.supportedTypes = supportedTypes
        self.continuous = continuous
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.completion = context.coordinator.handle(result:)
        controller.supportedTypes = supportedTypes
        controller.continuous = continuous
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        // No updates.
    }

    final class Coordinator {
        private let completion: ScanCompletion

        init(completion: @escaping ScanCompletion) {
            self.completion = completion
        }

        func handle(result: Result<ScanResult, ScanError>) {
            completion(result)
        }
    }
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var completion: ((Result<ScanResult, ScanError>) -> Void)?
    var supportedTypes: [AVMetadataObject.ObjectType] = [.qr]
    var continuous: Bool = false

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var videoDevice: AVCaptureDevice?

    // Serialize all session calls. Starting/stopping across threads races
    // inside libdispatch and can crash, especially during long scan sessions.
    private let sessionQueue = DispatchQueue(label: "com.snipemobile.scanner.session")
    private var isConfigured = false

    private var initialZoomFactor: CGFloat = 1.0

    // Debounce state for continuous scanning.
    private var lastScanValue: String?
    private var lastScanTime: Date = .distantPast

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        // Preview and gestures on main, session work on its own queue.
        configurePreview()
        configureGestures()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSession()
            if self.isConfigured, !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func failOnMain(_ error: ScanError) {
        DispatchQueue.main.async { [weak self] in
            self?.completion?(.failure(error))
        }
    }

    // Runs on sessionQueue.
    private func configureSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ?? AVCaptureDevice.default(for: .video) else {
            failOnMain(.badInput)
            return
        }

        videoDevice = device

        session.beginConfiguration()

        do {
            let input = try AVCaptureDeviceInput(device: device)

            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                session.commitConfiguration()
                failOnMain(.badInput)
                return
            }
        } catch {
            session.commitConfiguration()
            failOnMain(.initError(error))
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)

            let availableTypes = metadataOutput.availableMetadataObjectTypes
            let desiredTypes: [AVMetadataObject.ObjectType] = self.supportedTypes.isEmpty
                ? [.qr]
                : self.supportedTypes
            let filteredSupportedTypes = desiredTypes.filter { availableTypes.contains($0) }

            #if DEBUG
            print("[Scanner] available types: \(availableTypes)")
            print("[Scanner] desired types: \(desiredTypes)")
            print("[Scanner] filtered types: \(filteredSupportedTypes)")
            #endif

            // Fall back to all symbologies if the filter set is empty on this device.
            let typesToUse = !filteredSupportedTypes.isEmpty ? filteredSupportedTypes : availableTypes
            guard !typesToUse.isEmpty else {
                session.commitConfiguration()
                failOnMain(.badOutput)
                return
            }

            metadataOutput.metadataObjectTypes = typesToUse
        } else {
            session.commitConfiguration()
            failOnMain(.badOutput)
            return
        }

        session.commitConfiguration()
        isConfigured = true
    }

    private func configurePreview() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
    }

    private func configureGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        view.addGestureRecognizer(pinch)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device = videoDevice else { return }

        switch gesture.state {
        case .began:
            initialZoomFactor = device.videoZoomFactor
        case .changed:
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 8.0)
            let minZoom: CGFloat = 1.0
            var newZoom = initialZoomFactor * gesture.scale
            newZoom = max(minZoom, min(newZoom, maxZoom))

            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = newZoom
                device.unlockForConfiguration()
            } catch {
                break
            }
        default:
            break
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = readable.stringValue else {
            return
        }

        if continuous {
            let now = Date()
            // Drop repeats of the same code and add a short cooldown between hits.
            if stringValue == lastScanValue, now.timeIntervalSince(lastScanTime) < 2.0 { return }
            if now.timeIntervalSince(lastScanTime) < 0.6 { return }
            lastScanValue = stringValue
            lastScanTime = now

            let result = ScanResult(
                string: stringValue,
                type: readable.type,
                image: nil,
                corners: []
            )
            completion?(.success(result))
            return
        }

        session.stopRunning()

        let transformedObject = previewLayer.transformedMetadataObject(for: readable) as? AVMetadataMachineReadableCodeObject
        let corners = transformedObject?.corners ?? []

        let result = ScanResult(
            string: stringValue,
            type: readable.type,
            image: nil,
            corners: corners
        )

        completion?(.success(result))
        completion = nil
    }

    deinit {
        // Stop on the session queue to avoid racing an in-flight start/stop.
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }
}
#endif


