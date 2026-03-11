//
//  ShareViewController.swift
//  KidBoxShareExtension
//
//  Created by vscocca on 10/03/26.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import FirebaseCore
import FirebaseAuth

class ShareViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        let accessGroup = Bundle.main.object(forInfoDictionaryKey: "KEYCHAIN_ACCESS_GROUP") as? String ?? ""
        do {
            try Auth.auth().useUserAccessGroup(accessGroup)
            let uid = Auth.auth().currentUser?.uid ?? "NIL"
            print("[ShareVC] useUserAccessGroup OK — currentUser uid=\(uid)")
        } catch {
            print("[ShareVC] useUserAccessGroup FAILED: \(error)")
        }
        Task { @MainActor in
            let payload = await buildPayload()
            presentSheet(payload: payload)
        }
    }
    
    // MARK: - Build payload
    
    private func buildPayload() async -> KBSharePayload {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return KBSharePayload(type: .unknown)
        }
        
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                
                // Immagine
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    let url = await loadURL(from: provider, type: UTType.image.identifier)
                    return KBSharePayload(type: .image(url))
                }
                
                // URL
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(from: provider, type: UTType.url.identifier) {
                        return KBSharePayload(type: .url(url.absoluteString))
                    }
                }
                
                // Testo
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadString(from: provider, type: UTType.plainText.identifier) {
                        return KBSharePayload(type: .text(text))
                    }
                }
                
                // File generico
                if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                    if let url = await loadURL(from: provider, type: UTType.data.identifier) {
                        return KBSharePayload(type: .file(url))
                    }
                }
            }
        }
        return KBSharePayload(type: .unknown)
    }
    
    private func loadURL(from provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let url = item as? URL {
                    cont.resume(returning: url)
                } else if let img = item as? UIImage,
                          let data = img.jpegData(compressionQuality: 0.9) {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + ".jpg")
                    try? data.write(to: tmp)
                    cont.resume(returning: tmp)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
    
    private func loadString(from provider: NSItemProvider, type: String) async -> String? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                cont.resume(returning: item as? String)
            }
        }
    }
    
    // MARK: - Present SwiftUI sheet
    
    private func presentSheet(payload: KBSharePayload) {
        let ctx = self.extensionContext
        let sheet = KBShareSheet(payload: payload) {
            ctx?.completeRequest(returningItems: [], completionHandler: nil)
        }
        let host = UIHostingController(rootView: sheet)
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }
}
