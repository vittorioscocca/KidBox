//
//  WalletDocumentScannerView.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Wrapper SwiftUI dello scanner di sistema (VisionKit `VNDocumentCameraViewController`):
//  rilevamento bordi automatico e correzione prospettica, con supporto nativo
//  multi-pagina (fronte + retro in un'unica sessione). È lo stesso scanner
//  usato da Note/File — a differenza dello scatto singolo già usato altrove
//  in Documenti (`UIImagePickerController`), qui serve un'acquisizione "pulita"
//  di documenti fisici come la Tessera Sanitaria.
//

import SwiftUI
import VisionKit

struct WalletDocumentScannerView: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var pages: [UIImage] = []
            for i in 0..<scan.pageCount {
                pages.append(scan.imageOfPage(at: i))
            }
            controller.dismiss(animated: true) {
                self.onFinish(pages)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true) {
                self.onCancel()
            }
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            KBLog.ui.kbError("[WalletDocumentScanner] scan failed: \(error.localizedDescription)")
            controller.dismiss(animated: true) {
                self.onCancel()
            }
        }
    }
}
