//
//  LoyaltyCardBarcodeScannerView.swift
//  KidBox
//
//  Created by vscocca on 20/08/26.
//
//  Scanner camera per carte fedeltà: estende `QRCodeScannerView` (limitato a
//  `.qr`) ai formati barcode retail più comuni (EAN-13/8, Code128/39, PDF417,
//  UPC-E, ITF-14, Aztec), mantenendo lo stesso stile "fire once" + vibrazione.
//  Include un link di fallback per l'inserimento manuale, per quando la
//  fotocamera non riesce a leggere il codice (es. carta danneggiata).
//

import SwiftUI
import AVFoundation

struct LoyaltyCardBarcodeScannerView: View {
    /// Formato barcode plausibile per il brand selezionato (solo hint UI, non filtra la lettura).
    var expectedFormat: String?
    /// Chiamato una volta con `(testo, formatoRawValue)` alla prima lettura valida.
    var onDetect: (String, String) -> Void
    /// Chiamato quando l'utente preferisce inserire il codice a mano.
    var onManualFallback: () -> Void

    var body: some View {
        ZStack {
            LoyaltyCardBarcodeScannerRepresentable(onCode: onDetect)
                .ignoresSafeArea()

            VStack {
                Spacer()

                VStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.8), lineWidth: 2)
                        .frame(height: 140)
                        .padding(.horizontal, 32)

                    Text("Inquadra il codice a barre sul retro della carta")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                Button {
                    onManualFallback()
                } label: {
                    Text("La scansione non funziona? Inserisci i dati manualmente")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .underline()
                }
                .padding(.bottom, 32)
            }
        }
        .background(Color.black)
    }
}

/// UIKit representable: sessione AVCapture con `metadataObjectTypes` allargati
/// ai formati barcode retail. Pattern identico a `QRCodeScannerView` (fire
/// once + vibrazione), non ne riusa il codice perché quello è vincolato a
/// `.qr` e non espone i formati come parametro.
private struct LoyaltyCardBarcodeScannerRepresentable: UIViewControllerRepresentable {

    var onCode: (String, String) -> Void

    static let supportedTypes: [AVMetadataObject.ObjectType] = [
        .ean13, .ean8, .code128, .code39, .pdf417, .upce, .itf14, .aztec, .qr
    ]

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: LoyaltyCardBarcodeScannerRepresentable
        var didDetect = false

        init(_ parent: LoyaltyCardBarcodeScannerRepresentable) {
            self.parent = parent
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                             didOutput metadataObjects: [AVMetadataObject],
                             from connection: AVCaptureConnection) {
            guard !didDetect else { return }

            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  LoyaltyCardBarcodeScannerRepresentable.supportedTypes.contains(object.type),
                  let value = object.stringValue else {
                return
            }

            didDetect = true

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            KBLog.navigation.kbInfo("LoyaltyCardBarcodeScannerView detected code type=\(object.type.rawValue) (payload redacted)")

            parent.onCode(value, Self.normalizedFormat(object.type))
        }

        private static func normalizedFormat(_ type: AVMetadataObject.ObjectType) -> String {
            switch type {
            case .ean13: return "ean13"
            case .ean8: return "ean8"
            case .code128: return "code128"
            case .code39: return "code39"
            case .pdf417: return "pdf417"
            case .upce: return "upce"
            case .itf14: return "itf14"
            case .aztec: return "aztec"
            case .qr: return "qr"
            default: return "unknown"
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black

        // Senza questo check, un permesso già negato lascia il preview nero per
        // sempre: startRunning() semplicemente non produce frame, senza errore.
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
            KBLog.navigation.kbError("LoyaltyCardBarcodeScannerView: no video device available")
            return
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            KBLog.navigation.kbError("LoyaltyCardBarcodeScannerView: cannot create video input")
            return
        }

        guard captureSession.canAddInput(videoInput) else {
            KBLog.navigation.kbError("LoyaltyCardBarcodeScannerView: cannot add video input to session")
            return
        }
        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else {
            KBLog.navigation.kbError("LoyaltyCardBarcodeScannerView: cannot add metadata output to session")
            return
        }
        captureSession.addOutput(metadataOutput)

        metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        // Filtra al set effettivamente supportato dal device (evita crash se
        // un formato non è disponibile su un dato modello di iPhone).
        metadataOutput.metadataObjectTypes = Self.supportedTypes.filter {
            metadataOutput.availableMetadataObjectTypes.contains($0)
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = viewController.view.layer.bounds
        viewController.view.layer.addSublayer(previewLayer)

        captureSession.startRunning()
        KBLog.navigation.kbInfo("LoyaltyCardBarcodeScannerView session started")

        objc_setAssociatedObject(viewController, "kidbox_loyalty_scan_session", captureSession, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(viewController, "kidbox_loyalty_scan_preview", previewLayer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func showPermissionDeniedMessage(on viewController: UIViewController) {
        let label = UILabel()
        label.text = "Permesso fotocamera necessario.\nAttivalo dalle Impostazioni per scansionare il codice."
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
        // Fire-once: nessun aggiornamento necessario dopo il setup iniziale.
    }
}
