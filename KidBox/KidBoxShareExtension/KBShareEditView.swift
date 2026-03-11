//
//  KBShareEditView.swift
//  KidBoxShareExtension
//

import SwiftUI
import UIKit
import os.log

struct KBShareEditView: View {
    let destination: KBShareDestination
    let payload: KBSharePayload
    let onDone: () -> Void
    weak var extensionContext: NSExtensionContext?
    
    @State private var editedText: String = ""
    @State private var editedTitle: String = ""
    @State private var isSending = false
    @State private var errorMessage: String? = nil
    
    private let appGroupId = "group.it.vittorioscocca.kidbox"
    private let logger = Logger(subsystem: "it.vittorioscocca.KidBox.ShareExtension", category: "KBShareEditView")
    
    private func log(_ message: String) {
        logger.debug("[KBShareEditView] \(message, privacy: .public)")
        print("[KBShareEditView] \(message)")
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                payloadPreview.padding(.top, 8)
                editFields
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }
                Spacer(minLength: 40)
                Button {
                    Task { await sendToDestination() }
                } label: {
                    HStack {
                        if isSending {
                            ProgressView().tint(.white)
                            Text("Invio in corso…")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: destination.icon)
                            Text(confirmLabel)
                        }
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(destination.color, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isSending)
            }
            .padding()
        }
        .navigationTitle(destination.label)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { prefillFields() }
    }
    
    // MARK: - Preview
    
    @ViewBuilder
    private var payloadPreview: some View {
        switch payload.type {
        case .image(let url):
            if let url, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(height: 160).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case .text(let t):
            Text(t)
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 10))
        case .url(let u):
            Text(u).font(.caption).foregroundStyle(.blue).lineLimit(2)
        default:
            EmptyView()
        }
    }
    
    // MARK: - Edit fields
    
    @ViewBuilder
    private var editFields: some View {
        switch destination {
        case .todo:
            VStack(alignment: .leading, spacing: 8) {
                Label("Titolo del to-do", systemImage: "checkmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Es. Comprare latte", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
            }
        case .grocery:
            VStack(alignment: .leading, spacing: 8) {
                Label("Aggiungi alla lista spesa", systemImage: "cart")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Es. Latte, pane, uova", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                Text("Ogni riga diventerà un articolo separato")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        case .event:
            VStack(alignment: .leading, spacing: 8) {
                Label("Titolo evento", systemImage: "calendar")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Es. Visita pediatra", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                Label("Note aggiuntive", systemImage: "text.alignleft")
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                TextEditor(text: $editedText)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3)))
            }
        case .note:
            VStack(alignment: .leading, spacing: 8) {
                Label("Titolo nota", systemImage: "note.text")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Titolo", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
            }
        case .chat:
            switch payload.type {
            case .image, .file:
                Text("Il file verrà inviato direttamente nella chat di famiglia.")
                    .font(.subheadline).foregroundStyle(.secondary)
            default:
                TextField("Messaggio", text: $editedText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4)
            }
        case .document:
            Text("Il file verrà salvato nella sezione Documenti.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Confirm label
    
    private var confirmLabel: String {
        switch destination {
        case .chat:     return "Invia in chat"
        case .document: return "Salva nei documenti"
        case .todo:     return "Crea to-do"
        case .grocery:  return "Aggiungi alla spesa"
        case .event:    return "Crea evento"
        case .note:     return "Crea nota"
        }
    }
    
    // MARK: - Prefill
    
    private func prefillFields() {
        switch payload.type {
        case .text(let t):
            editedTitle = t.components(separatedBy: "\n").first ?? t
            editedText  = t
        case .url(let u):
            editedTitle = u
            editedText  = u
        default:
            break
        }
    }
    
    // MARK: - Send
    
    private func sendToDestination() async {
        log("sendToDestination START destination=\(destination.rawStringValue)")
        isSending = true
        errorMessage = nil
        
        do {
            if destination == .chat {
                // ── Invio diretto in chat senza aprire l'app ──
                try await sendDirectToChat()
            } else {
                // ── Altre destinazioni: salva nell'App Group e apri l'app ──
                saveToAppGroup()
                openApp()
            }
            log("sendToDestination OK")
            closeExtension()
        } catch {
            log("sendToDestination ERROR: \(error.localizedDescription)")
            isSending = false
            errorMessage = "Errore: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Chat: invio diretto da extension
    
    private func sendDirectToChat() async throws {
        log("sendDirectToChat START")
        
        // Legge familyId dall'App Group (salvato dall'app principale)
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let familyId = defaults.string(forKey: "activeFamilyId"),
              !familyId.isEmpty else {
            log("sendDirectToChat ERROR: familyId not found in App Group")
            throw ShareError.missingFamilyId
        }
        log("sendDirectToChat familyId=\(familyId)")
        
        let messageId = UUID().uuidString
        let storage   = ChatStorageService()
        let remote    = ChatRemoteStore()
        
        switch payload.type {
            
        case .image(let url):
            guard let sourceURL = url,
                  let data = imageData(from: sourceURL) else {
                throw ShareError.missingFile
            }
            log("sendDirectToChat uploading image bytes=\(data.count)")
            let (storagePath, downloadURL) = try await storage.upload(
                data: data,
                familyId: familyId,
                messageId: messageId,
                fileName: "photo.jpg",
                mimeType: "image/jpeg"
            )
            log("sendDirectToChat upload OK storagePath=\(storagePath)")
            let dto = makeDTO(
                messageId: messageId,
                familyId: familyId,
                typeRaw: "photo",
                mediaStoragePath: storagePath,
                mediaURL: downloadURL
            )
            try await remote.upsert(dto: dto)
            
        case .file(let url):
            let ext = url.pathExtension.lowercased()
            let isVideo = ["mp4", "mov", "m4v"].contains(ext)
            let isImage = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"].contains(ext)
            let (fileName, mimeType, typeRaw): (String, String, String) = {
                if isImage { return ("photo.jpg", "image/jpeg", "photo") }
                if isVideo { return ("video.mp4", "video/mp4", "video") }
                return (url.lastPathComponent, "application/octet-stream", "document")
            }()
            guard let data = try? Data(contentsOf: url) else {
                throw ShareError.missingFile
            }
            log("sendDirectToChat uploading file typeRaw=\(typeRaw) bytes=\(data.count)")
            let (storagePath, downloadURL) = try await storage.upload(
                data: data,
                familyId: familyId,
                messageId: messageId,
                fileName: fileName,
                mimeType: mimeType
            )
            let dto = makeDTO(
                messageId: messageId,
                familyId: familyId,
                typeRaw: typeRaw,
                mediaStoragePath: storagePath,
                mediaURL: downloadURL
            )
            try await remote.upsert(dto: dto)
            
        case .text(let t):
            let text = editedText.isEmpty ? t : editedText
            log("sendDirectToChat sending text=\(text.prefix(50))")
            let dto = makeDTO(
                messageId: messageId,
                familyId: familyId,
                typeRaw: "text",
                text: text
            )
            try await remote.upsert(dto: dto)
            
        case .url(let u):
            let text = editedText.isEmpty ? u : editedText
            log("sendDirectToChat sending url=\(u)")
            let dto = makeDTO(
                messageId: messageId,
                familyId: familyId,
                typeRaw: "text",
                text: text
            )
            try await remote.upsert(dto: dto)
            
        case .unknown:
            log("sendDirectToChat unknown payload — nothing to send")
        }
        let allKeys = defaults.dictionaryRepresentation().keys.sorted()
        log("AppGroup keys: \(allKeys)")
        log("activeFamilyId: \(defaults.string(forKey: "activeFamilyId") ?? "NIL")")
        log("currentUserUID: \(defaults.string(forKey: "currentUserUID") ?? "NIL")")
    }
    
    // MARK: - DTO builder
    
    private func makeDTO(
        messageId: String,
        familyId: String,
        typeRaw: String,
        text: String? = nil,
        mediaStoragePath: String? = nil,
        mediaURL: String? = nil
    ) -> RemoteChatMessageDTO {
        // Legge nome utente dall'App Group (salvato dall'app al login)
        let defaults    = UserDefaults(suiteName: appGroupId)
        let senderName  = defaults?.string(forKey: "currentUserDisplayName") ?? "Utente"
        let senderId    = defaults?.string(forKey: "currentUserUID") ?? "unknown"
        log("makeDTO senderId=\(senderId) senderName=\(senderName)")
        return RemoteChatMessageDTO(
            id:                   messageId,
            familyId:             familyId,
            senderId:             senderId,
            senderName:           senderName,
            typeRaw:              typeRaw,
            text:                 text,
            mediaStoragePath:     mediaStoragePath,
            mediaURL:             mediaURL,
            mediaDurationSeconds: nil,
            mediaThumbnailURL:    nil,
            replyToId:            nil,
            reactionsJSON:        nil,
            readByJSON:           nil,
            createdAt:            Date(),
            editedAt:             nil,
            isDeleted:            false,
            deletedFor:           [],
            latitude:             nil,
            longitude:            nil
        )
    }
    
    // MARK: - App Group (per destinazioni non-chat)
    
    private func saveToAppGroup() {
        var data: [String: String] = [
            "destination": destination.rawStringValue,
            "timestamp":   ISO8601DateFormatter().string(from: Date())
        ]
        switch payload.type {
        case .text(let t):
            data["text"]  = editedText.isEmpty ? t : editedText
            data["title"] = editedTitle
        case .url(let u):
            data["text"]  = u
            data["title"] = editedTitle
        case .image(let url):
            let name = "share_\(UUID().uuidString).jpg"
            if let sourceURL = url, let groupURL = copyFileToAppGroup(sourceURL, name: name) {
                data["sharedFilePath"] = groupURL.path
                data["sharedFileType"] = "image"
            }
            data["title"] = editedTitle
        case .file(let url):
            let name = "share_\(UUID().uuidString)_\(url.lastPathComponent)"
            if let groupURL = copyFileToAppGroup(url, name: name) {
                data["sharedFilePath"] = groupURL.path
                data["sharedFileType"] = "file"
                data["sharedFileName"] = url.lastPathComponent
            }
            data["title"] = editedTitle
        case .unknown:
            break
        }
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        defaults.set(data, forKey: "pendingShare")
        log("saveToAppGroup saved keys=\(data.keys.sorted())")
    }
    
    private func openApp() {
        let urlString = "kidbox://share?destination=\(destination.rawStringValue)"
        if let appURL = URL(string: urlString) {
            log("openApp url=\(urlString)")
            extensionContext?.open(appURL, completionHandler: nil)
        }
    }
    
    private func closeExtension() {
        log("closeExtension")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.onDone() }
        }
    }
    
    // MARK: - Helpers
    
    private func imageData(from url: URL) -> Data? {
        // Prova lettura diretta
        if let data = try? Data(contentsOf: url) { return data }
        // Fallback security-scoped
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
    
    private func copyFileToAppGroup(_ source: URL, name: String) -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else { return nil }
        let dest = container.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        if (try? FileManager.default.copyItem(at: source, to: dest)) != nil { return dest }
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: source),
              (try? data.write(to: dest, options: .atomic)) != nil else { return nil }
        return dest
    }
}

// MARK: - Errors

enum ShareError: LocalizedError {
    case missingFamilyId
    case missingFile
    
    var errorDescription: String? {
        switch self {
        case .missingFamilyId: return "Apri KidBox almeno una volta per configurare la famiglia."
        case .missingFile:     return "Impossibile leggere il file selezionato."
        }
    }
}
