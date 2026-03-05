import SwiftUI
import AVFoundation
import UIKit

#if os(iOS)
/// Eigen fouttype voor QR-scannen, gemodelleerd naar CodeScanner.
enum ScanError: Error {
    case badInput
    case badOutput
    case initError(Error)
    case permissionDenied
}

/// Resultaat van een succesvolle scan.
struct ScanResult {
    let string: String
    let type: AVMetadataObject.ObjectType
    let image: UIImage?
    let corners: [CGPoint]
}

struct ZoomableQRScannerView: UIViewControllerRepresentable {
    typealias ScanCompletion = (Result<ScanResult, ScanError>) -> Void

    let completion: ScanCompletion

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.completion = context.coordinator.handle(result:)
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        // Geen dynamische updates nodig.
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

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var videoDevice: AVCaptureDevice?

    private var initialZoomFactor: CGFloat = 1.0

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        configureSession()
        configurePreview()
        configureGestures()

        session.startRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ?? AVCaptureDevice.default(for: .video) else {
            completion?(.failure(.badInput))
            return
        }

        videoDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)

            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                completion?(.failure(.badInput))
                return
            }
        } catch {
            completion?(.failure(.initError(error)))
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)

            if metadataOutput.availableMetadataObjectTypes.contains(.qr) {
                metadataOutput.metadataObjectTypes = [.qr]
            } else {
                completion?(.failure(.badOutput))
            }
        } else {
            completion?(.failure(.badOutput))
            return
        }
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
        session.stopRunning()
    }
}
#endif


