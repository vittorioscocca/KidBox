//
//  QRCodeScannerView..swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import SwiftUI
import AVFoundation

struct QRCodeScannerView: UIViewControllerRepresentable {
    
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
            
            // Vibrazione leggera
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            parent.onCode(value)
        }
    }
    
    var onCode: (String) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black
        
        let captureSession = AVCaptureSession()
        
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput) else {
            return viewController
        }
        
        captureSession.addInput(videoInput)
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        guard captureSession.canAddOutput(metadataOutput) else {
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
        
        // Manteniamo viva la sessione
        objc_setAssociatedObject(
            viewController,
            "kidbox_qr_session",
            captureSession,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
}
