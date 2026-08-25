//
//  QRCodeScannerView..swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import SwiftUI
import AVFoundation
import OSLog

/// UIKit QR scanner wrapped for SwiftUI.
///
/// This view starts an `AVCaptureSession` to read QR codes and calls `onCode` once,
/// debouncing repeated detections via `Coordinator.didDetect`.
///
/// - Important:
///   - Avoid logging the QR payload content (it may contain secrets).
///   - This implementation is "fire once": it stops emitting after the first detection.
///     If you need to scan again, recreate the view (e.g. dismiss and re-present the sheet).
struct QRCodeScannerView: UIViewControllerRepresentable {
    
    /// Called once when a QR code payload is detected.
    var onCode: (String) -> Void
    
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRCodeScannerView
        var didDetect = false   // evita multiple letture
        
        init(_ parent: QRCodeScannerView) {
            self.parent = parent
        }
        
        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            
            guard !didDetect else { return }
            
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue else {
                return
            }
            
            didDetect = true
            
            // Vibrazione leggera (best effort)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Non loggare `value`: può contenere segreti (inviteId/secret ecc.)
            KBLog.navigation.kbInfo("QRCodeScannerView detected QR (redacted)")
            
            parent.onCode(value)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        KBLog.navigation.kbDebug("QRCodeScannerView makeUIViewController")

        let viewController = UIViewController()
        viewController.view.backgroundColor = .black

        // Without this check, a previously-denied camera permission leaves the
        // preview black forever with no feedback: startRunning() just never
        // produces frames. Request/verify access first, then build the session.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession(on: viewController, context: context)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.startSession(on: viewController, context: context)
                    } else {
                        self.showPermissionDeniedMessage(on: viewController)
                    }
                }
            }
        case .denied, .restricted:
            showPermissionDeniedMessage(on: viewController)
        @unknown default:
            showPermissionDeniedMessage(on: viewController)
        }

        return viewController
    }

    private func startSession(on viewController: UIViewController, context: Context) {
        let captureSession = AVCaptureSession()

        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            KBLog.navigation.kbError("QRCodeScannerView: no video device available")
            return
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            KBLog.navigation.kbError("QRCodeScannerView: cannot create video input")
            return
        }

        guard captureSession.canAddInput(videoInput) else {
            KBLog.navigation.kbError("QRCodeScannerView: cannot add video input to session")
            return
        }
        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else {
            KBLog.navigation.kbError("QRCodeScannerView: cannot add metadata output to session")
            return
        }
        captureSession.addOutput(metadataOutput)

        metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = viewController.view.layer.bounds
        viewController.view.layer.addSublayer(previewLayer)

        captureSession.startRunning()
        KBLog.navigation.kbInfo("QRCodeScannerView session started")

        // Manteniamo viva la sessione per la lifetime del VC
        objc_setAssociatedObject(
            viewController,
            "kidbox_qr_session",
            captureSession,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        // Manteniamo viva anche la previewLayer (evita deallocazioni strane)
        objc_setAssociatedObject(
            viewController,
            "kidbox_qr_preview",
            previewLayer,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private func showPermissionDeniedMessage(on viewController: UIViewController) {
        let label = UILabel()
        label.text = "Permesso fotocamera necessario.\nAttivalo dalle Impostazioni per scansionare il QR."
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton(type: .system)
        button.setTitle("Apri Impostazioni", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        viewController.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: viewController.view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: viewController.view.trailingAnchor, constant: -32),
        ])
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Intentionally empty.
        // If you need to reset scanning while the VC stays alive, you'd reset `didDetect`
        // and potentially restart the session — but that's out of scope for the current "fire once" behavior.
    }
}
