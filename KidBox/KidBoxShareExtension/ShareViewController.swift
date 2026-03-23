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
                
                // ✅ Video/movie — PRIMA di tutto il resto.
                //    WhatsApp registra i video con più UTI (movie, file-url, url).
                //    Se public.file-url venisse prima, il file arriverebbe senza estensione
                //    e verrebbe classificato come documento invece che come video.
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    if let url = await loadFileURL(from: provider, type: UTType.movie.identifier) {
                        print("[ShareVC] detected movie file url=\(url)")
                        return KBSharePayload(type: .file(url))
                    }
                }
                
                // Immagine
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let url = await loadURL(from: provider, type: UTType.image.identifier) {
                        print("[ShareVC] detected image url=\(url)")
                        return KBSharePayload(type: .image(url))
                    }
                }
                
                // file-url (documenti da Files/iCloud) — dopo movie e image
                if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                    if let url = await loadFileURL(from: provider, type: "public.file-url") {
                        print("[ShareVC] detected file-url (document) url=\(url)")
                        return KBSharePayload(type: .file(url))
                    }
                }
                
                // URL web (solo se non è un file locale)
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(from: provider, type: UTType.url.identifier) {
                        if url.isFileURL {
                            print("[ShareVC] detected file url via url-type url=\(url)")
                            if let fileURL = await loadFileURL(from: provider, type: "public.file-url") {
                                return KBSharePayload(type: .file(fileURL))
                            }
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
        
        // Helper: calcola estensione dal tipo UTI
        func resolveExt(_ url: URL) -> String {
            if !url.pathExtension.isEmpty { return ".\(url.pathExtension)" }
            let utiToExt: [String: String] = [
                "com.adobe.pdf":                                          ".pdf",
                "org.openxmlformats.wordprocessingml.document":           ".docx",
                "com.microsoft.word.doc":                                 ".doc",
                "org.openxmlformats.spreadsheetml.sheet":                 ".xlsx",
                "com.microsoft.excel.xls":                                ".xls",
                "org.openxmlformats.presentationml.presentation":         ".pptx",
                "com.microsoft.powerpoint.ppt":                           ".ppt",
                "public.plain-text":                                      ".txt",
                "public.rtf":                                             ".rtf",
                "public.html":                                            ".html",
                "com.apple.iwork.pages.pages":                            ".pages",
                "com.apple.iwork.numbers.numbers":                        ".numbers",
                "com.apple.iwork.keynote.key":                            ".key",
                // ✅ Video — necessario perché WhatsApp non sempre fornisce
                //    suggestedName o un srcURL con estensione
                "public.movie":                                           ".mp4",
                "public.mpeg-4":                                          ".mp4",
                "com.apple.quicktime-movie":                              ".mov",
                "public.avi":                                             ".avi",
                "public.3gpp":                                            ".3gp",
                // Foto
                "public.jpeg":                                            ".jpg",
                "public.png":                                             ".png",
                "public.heic":                                            ".heic",
                "public.heif":                                            ".heif",
            ]
            if let mapped = utiToExt[type] { return mapped }
            for uti in provider.registeredTypeIdentifiers {
                if let mapped = utiToExt[uti] { return mapped }
            }
            if let preferred = UTType(type)?.preferredFilenameExtension { return ".\(preferred)" }
            return ""
        }
        
        // Helper: nome sicuro (scarta UUID puri)
        func safeName(from url: URL) -> String {
            if let suggested = provider.suggestedName, !suggested.isEmpty {
                return (suggested as NSString).deletingPathExtension
            }
            let base = url.deletingPathExtension().lastPathComponent
            let uuidPattern = #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#
            let isUUID = base.range(of: uuidPattern, options: .regularExpression) != nil
            if isUUID || ["file url", "document", "untitled", ""].contains(base.lowercased()) {
                return UUID().uuidString
            }
            return base
        }
        
        // STEP 1: loadFileRepresentation (async puro)
        let (fileRepURL, _): (URL?, Error?) = await withCheckedContinuation { cont in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                cont.resume(returning: (url, error))
            }
        }
        
        guard let srcURL = fileRepURL else {
            print("[ShareVC] loadFileURL ABORT — loadFileRepresentation returned nil")
            return nil
        }
        
        let ext  = resolveExt(srcURL)
        let name = safeName(from: srcURL)
        
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmp = tmpDir.appendingPathComponent(name + ext)
        
        print("[ShareVC] loadFileURL suggestedName=\(provider.suggestedName ?? "nil") safeName=\(name) ext=\(ext)")
        
        // STEP 2: leggi dati con NSFileCoordinator
        var coordError: NSError?
        var data: Data? = nil
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: srcURL, options: .withoutChanges, error: &coordError) { coordURL in
            data = try? Data(contentsOf: coordURL)
        }
        print("[ShareVC] loadFileURL coordinator bytes=\(data?.count ?? 0)")
        
        // STEP 3: se ancora pochi byte, prova loadItem (async puro, niente semaphore)
        if (data?.count ?? 0) < 512 {
            print("[ShareVC] loadFileURL trying loadItem fallback")
            let fallbackData: Data? = await withCheckedContinuation { cont in
                provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                    if let d = item as? Data {
                        cont.resume(returning: d)
                    } else if let u = item as? URL, let d = try? Data(contentsOf: u) {
                        cont.resume(returning: d)
                    } else {
                        cont.resume(returning: nil)
                    }
                }
            }
            if let fb = fallbackData, fb.count > (data?.count ?? 0) {
                data = fb
            }
            print("[ShareVC] loadFileURL after loadItem fallback bytes=\(data?.count ?? 0)")
        }
        
        // STEP 4: scrivi il file tmp — anche se sono 198 byte di placeholder,
        // la main app scaricherà il file reale tramite NSFileCoordinator
        guard let finalData = data else {
            print("[ShareVC] loadFileURL ABORT — data nil")
            return nil
        }
        
        do {
            if FileManager.default.fileExists(atPath: tmp.path) {
                try FileManager.default.removeItem(at: tmp)
            }
            try finalData.write(to: tmp, options: .atomic)
            print("[ShareVC] loadFileURL OK bytes=\(finalData.count) path=\(tmp.lastPathComponent)")
            return tmp
        } catch {
            print("[ShareVC] loadFileURL write failed: \(error.localizedDescription)")
            return nil
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
