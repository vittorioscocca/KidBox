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
import FirebaseFirestore

class ShareViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            let firestoreSettings = FirestoreSettings()
            firestoreSettings.cacheSettings = MemoryCacheSettings()
            Firestore.firestore().settings = firestoreSettings
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
                print("[ShareVC] provider registeredTypeIdentifiers=\(provider.registeredTypeIdentifiers)")
                
                // Immagine
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let url = await loadURL(from: provider, type: UTType.image.identifier) {
                        print("[ShareVC] detected image url=\(url)")
                        return KBSharePayload(type: .image(url))
                    }
                }
                
                // ✅ NUOVO: file-url (documenti da Files/iCloud) — usa loadFileURL come per i video
                // Deve stare PRIMA del branch UTType.url per intercettare i PDF/doc prima
                // che vengano trattati come URL web
                if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                    if let url = await loadFileURL(from: provider, type: "public.file-url") {
                        print("[ShareVC] detected file-url (document) url=\(url)")
                        return KBSharePayload(type: .file(url))
                    }
                }
                
                // URL web (solo se non è un file locale)
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(from: provider, type: UTType.url.identifier) {
                        // Se è un file URL, trattalo come file (fallback di sicurezza)
                        if url.isFileURL {
                            print("[ShareVC] detected file url via url-type url=\(url)")
                            if let fileURL = await loadFileURL(from: provider, type: UTType.url.identifier) {
                                return KBSharePayload(type: .file(fileURL))
                            }
                        }
                        print("[ShareVC] detected web url=\(url.absoluteString)")
                        return KBSharePayload(type: .url(url.absoluteString))
                    }
                }
                
                // Testo
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadString(from: provider, type: UTType.plainText.identifier) {
                        print("[ShareVC] detected text")
                        return KBSharePayload(type: .text(text))
                    }
                }
                
                // Video / movie
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    if let url = await loadFileURL(from: provider, type: UTType.movie.identifier) {
                        print("[ShareVC] detected movie file url=\(url)")
                        return KBSharePayload(type: .file(url))
                    }
                }
                
                // File generico
                if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                    if let url = await loadFileURL(from: provider, type: UTType.data.identifier) {
                        print("[ShareVC] detected generic file url=\(url)")
                        return KBSharePayload(type: .file(url))
                    }
                }
            }
        }
        
        print("[ShareVC] payload unknown")
        return KBSharePayload(type: .unknown)
    }
    
    private func loadURL(from provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error {
                    print("[ShareVC] loadURL error type=\(type) error=\(error.localizedDescription)")
                }
                
                if let url = item as? URL {
                    cont.resume(returning: url)
                } else if let img = item as? UIImage,
                          let data = img.jpegData(compressionQuality: 0.9) {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + ".jpg")
                    do {
                        try data.write(to: tmp)
                        cont.resume(returning: tmp)
                    } catch {
                        print("[ShareVC] loadURL write temp image failed: \(error.localizedDescription)")
                        cont.resume(returning: nil)
                    }
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
    
    private func loadFileURL(from provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                if let error {
                    print("[ShareVC] loadFileURL error type=\(type) error=\(error.localizedDescription)")
                }
                
                guard let url else {
                    cont.resume(returning: nil)
                    return
                }
                
                let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ext)
                
                do {
                    if FileManager.default.fileExists(atPath: tmp.path) {
                        try FileManager.default.removeItem(at: tmp)
                    }
                    try FileManager.default.copyItem(at: url, to: tmp)
                    cont.resume(returning: tmp)
                } catch {
                    print("[ShareVC] loadFileURL copy failed: \(error.localizedDescription)")
                    cont.resume(returning: nil)
                }
            }
        }
    }
    
    private func loadString(from provider: NSItemProvider, type: String) async -> String? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error {
                    print("[ShareVC] loadString error type=\(type) error=\(error.localizedDescription)")
                }
                cont.resume(returning: item as? String)
            }
        }
    }
    
    // MARK: - Present SwiftUI sheet
    
    private func presentSheet(payload: KBSharePayload) {
        let ctx = self.extensionContext
        
        let sheet = KBShareSheet(
            payload: payload,
            onDismiss: {
                ctx?.completeRequest(returningItems: [], completionHandler: nil)
            },
            onOpenApp: { urlString in
                guard let url = URL(string: urlString) else {
                    print("[ShareVC] invalid URL string: \(urlString)")
                    ctx?.completeRequest(returningItems: [], completionHandler: nil)
                    return
                }
                
                // extensionContext?.open non funziona nelle Share Extension (restituisce sempre false).
                // La soluzione supportata è risalire il responder chain fino a UIApplication
                // e chiamare open(_:) da lì — funziona su iOS 12+.
                print("[ShareVC] opening host app via responder chain url=\(urlString)")
                
                var responder: UIResponder? = self
                while let r = responder {
                    if let app = r as? UIApplication {
                        app.open(url, options: [:]) { success in
                            print("[ShareVC] responder open result success=\(success)")
                            ctx?.completeRequest(returningItems: [], completionHandler: nil)
                        }
                        return
                    }
                    responder = r.next
                }
                
                // Fallback: se il responder chain non trovasse UIApplication (non dovrebbe succedere)
                print("[ShareVC] responder chain exhausted — completing without opening")
                ctx?.completeRequest(returningItems: [], completionHandler: nil)
            }
        )
        
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
