//
//  CameraPermissionGate.swift
//  KidBox
//
//  Host UIViewController condiviso da tutti i wrapper UIImagePickerController
//  (sourceType == .camera): verifica/richiede il permesso fotocamera PRIMA di
//  presentare il picker, invece di lasciarlo su schermo nero se l'utente ha
//  già negato l'accesso in precedenza.
//
//  Uso: al posto di presentare direttamente `picker`, restituire
//  `CameraPermissionGateViewController(makePicker: { picker })` da
//  `makeUIViewController`.
//

import UIKit
import AVFoundation

final class CameraPermissionGateViewController: UIViewController {

    private let makePicker: () -> UIViewController
    private let onCancelled: (() -> Void)?
    private var didAttemptPresent = false

    init(makePicker: @escaping () -> UIViewController, onCancelled: (() -> Void)? = nil) {
        self.makePicker = makePicker
        self.onCancelled = onCancelled
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        view.backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAttemptPresent else { return }
        didAttemptPresent = true
        resolvePermissionThenPresent()
    }

    private func resolvePermissionThenPresent() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentPicker()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.presentPicker() : self?.showDeniedAlert()
                }
            }
        case .denied, .restricted:
            showDeniedAlert()
        @unknown default:
            showDeniedAlert()
        }
    }

    private func presentPicker() {
        let picker = makePicker()
        picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }

    private func showDeniedAlert() {
        let alert = UIAlertController(
            title: "Fotocamera non disponibile",
            message: "Per scattare foto in KidBox devi consentire l'accesso alla fotocamera dalle Impostazioni.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Apri Impostazioni", style: .default) { [weak self] _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            self?.dismissSelf()
        })
        alert.addAction(UIAlertAction(title: "Annulla", style: .cancel) { [weak self] _ in
            self?.dismissSelf()
        })
        present(alert, animated: true)
    }

    // Dismisso me stesso: essendo la root del contenuto di `.sheet`/`.fullScreenCover`,
    // SwiftUI si accorge della dismissal e riporta il binding `isPresented` a false da
    // solo — non serve propagare lo stato al chiamante.
    private func dismissSelf() {
        onCancelled?()
        presentingViewController?.dismiss(animated: true)
    }
}
