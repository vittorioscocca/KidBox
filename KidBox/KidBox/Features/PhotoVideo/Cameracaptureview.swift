//
//  CameraCaptureView.swift
//  KidBox
//
//  Wrapper UIImagePickerController per scattare foto e registrare video
//  direttamente dalla fotocamera.
//
//  Uso:
//    CameraCaptureView { result in
//        switch result {
//        case .photo(let data):   // JPEG Data
//        case .video(let url):    // URL temporaneo del video (mov/mp4)
//        case .cancelled: break
//        }
//    }
//
//  Il chiamante è responsabile di:
//    - copiare/leggere il videoURL prima che la view sia dismessa
//      (il file temporaneo viene cancellato dal sistema)
//    - uplodare i dati con la stessa pipeline di uploadItems()
//

import SwiftUI
import UIKit
import AVFoundation

// MARK: - Result

enum CameraCaptureResult {
    case photo(Data)           // JPEG Data
    case video(URL)            // URL temporaneo (mov / mp4)
    case cancelled
}

// MARK: - Host (presentazione modale corretta della camera)

/// `UIImagePickerController` con `sourceType == .camera` va **presentato modally** in fullscreen
/// da un `UIViewController` nella finestra attiva. Usarlo come root di un `UIViewControllerRepresentable`
/// (es. dentro `fullScreenCover`) spesso rompe scatto / controlli — soprattutto dopo cold open da URL/widget.
private final class CameraPickerHostViewController: UIViewController {
    private let picker: UIImagePickerController
    private var didPresentPicker = false

    init(picker: UIImagePickerController) {
        self.picker = picker
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        view.backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresentPicker else { return }
        didPresentPicker = true
        picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }
}

// MARK: - View

struct CameraCaptureView: UIViewControllerRepresentable {
    
    /// Tipi di media supportati (.photo, .video, o entrambi con .photoAndVideo)
    var mediaTypes: [String] = ["public.image", "public.movie"]
    var onResult: (CameraCaptureResult) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = mediaTypes
        picker.videoQuality = .typeMedium          // equivale a AVAssetExportPresetMediumQuality
        picker.videoMaximumDuration = 300          // max 5 minuti
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return CameraPickerHostViewController(picker: picker)
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onResult: (CameraCaptureResult) -> Void
        
        init(onResult: @escaping (CameraCaptureResult) -> Void) {
            self.onResult = onResult
        }
        
        private func finish(on picker: UIImagePickerController, result: CameraCaptureResult) {
            picker.dismiss(animated: true) { [onResult] in
                onResult(result)
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            finish(on: picker, result: .cancelled)
        }
        
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Video
            if let videoURL = info[.mediaURL] as? URL {
                // Copia in una directory temporanea sicura di nostra proprietà
                // così il file non sparisce quando il picker viene dismesso
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mp4")
                do {
                    try FileManager.default.copyItem(at: videoURL, to: dest)
                    finish(on: picker, result: .video(dest))
                } catch {
                    KBLog.sync.kbError("CameraCaptureView: video copy failed err=\(error.localizedDescription)")
                    finish(on: picker, result: .cancelled)
                }
                return
            }
            
            // Foto
            if let image = info[.originalImage] as? UIImage {
                // Normalizza orientamento e comprimi in JPEG 85%
                let normalized = image.normalizedOrientation()
                if let data = normalized.jpegData(compressionQuality: 0.85) {
                    finish(on: picker, result: .photo(data))
                } else {
                    KBLog.sync.kbError("CameraCaptureView: JPEG compression failed")
                    finish(on: picker, result: .cancelled)
                }
                return
            }
            
            finish(on: picker, result: .cancelled)
        }
    }
}

// MARK: - UIImage orientation helper

private extension UIImage {
    /// Ridisegna l'immagine rispettando il campo .imageOrientation
    /// così che il JPEG salvato sia sempre "dritto" senza EXIF rotation.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return normalized
    }
}

// MARK: - Camera availability

extension CameraCaptureView {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
}
