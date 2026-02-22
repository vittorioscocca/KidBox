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
            KBLog.navigation.info("QRCodeScannerView detected QR (redacted)")
            
            parent.onCode(value)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        KBLog.navigation.debug("QRCodeScannerView makeUIViewController")
        
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black
        
        let captureSession = AVCaptureSession()
        
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            KBLog.navigation.error("QRCodeScannerView: no video device available")
            return viewController
        }
        
        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            KBLog.navigation.error("QRCodeScannerView: cannot create video input")
            return viewController
        }
        
        guard captureSession.canAddInput(videoInput) else {
            KBLog.navigation.error("QRCodeScannerView: cannot add video input to session")
            return viewController
        }
        captureSession.addInput(videoInput)
        
        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else {
            KBLog.navigation.error("QRCodeScannerView: cannot add metadata output to session")
            return viewController
        }
        captureSession.addOutput(metadataOutput)
        
        metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = viewController.view.layer.bounds
        viewController.view.layer.addSublayer(previewLayer)
        
        captureSession.startRunning()
        KBLog.navigation.info("QRCodeScannerView session started")
        
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
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Intentionally empty.
        // If you need to reset scanning while the VC stays alive, you'd reset `didDetect`
        // and potentially restart the session — but that's out of scope for the current "fire once" behavior.
    }
}
