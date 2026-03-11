//
//  KBShareEditView.swift
//  KidBoxShareExtension
//

import SwiftUI
import UIKit
import os.log

private enum ShareSendResult {
    case completedInExtension
    case deferredToMainApp(urlString: String, showBanner: Bool)
    case videoDeferredToMainApp
}

private struct ParsedEventShare {
    let title: String
    let notes: String
    let detectedDate: Date?
}

struct KBShareEditView: View {
    let destination: KBShareDestination
    let payload: KBSharePayload
    let onDone: () -> Void
    let onOpenApp: (String) -> Void
    weak var extensionContext: NSExtensionContext?
    
    @State private var editedText: String = ""
    @State private var editedTitle: String = ""
    @State private var isSending = false
    @State private var hasSent = false  // evita doppio invio
    @State private var errorMessage: String? = nil
    @State private var remoteImage: UIImage? = nil
    @State private var videoSavedToAppGroup = false
    @State private var deferredBannerDestination: KBShareDestination? = nil
    
    private let appGroupId = "group.it.vittorioscocca.kidbox"
    private let logger = Logger(subsystem: "it.vittorioscocca.KidBox.ShareExtension", category: "KBShareEditView")
    
    private func log(_ message: String) {
        logger.debug("[KBShareEditView] \(message, privacy: .public)")
        print("[KBShareEditView] \(message)")
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            if videoSavedToAppGroup {
                videoSuccessView
            } else if let deferredDestination = deferredBannerDestination {
                deferredSuccessView(for: deferredDestination)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    payloadPreview
                        .padding(.top, 8)
                    
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
        }
        .navigationTitle(destination.label)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { prefillFields() }
    }
    
    // MARK: - Success views
    
    private var videoSuccessView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            
            VStack(spacing: 8) {
                Text("Video pronto")
                    .font(.title2.bold())
                
                Text("Apri KidBox per completare l'invio in chat.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                onOpenApp("kidbox://share?destination=chat")
            } label: {
                Label("Apri KidBox", systemImage: "arrow.up.right.app.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
            }
            
            Button("Annulla") {
                UserDefaults(suiteName: appGroupId)?.removeObject(forKey: "pendingShare")
                onDone()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            
            Spacer(minLength: 40)
        }
        .padding(32)
    }
    
    @ViewBuilder
    private func deferredSuccessView(for destination: KBShareDestination) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            
            VStack(spacing: 8) {
                Text("Quasi fatto")
                    .font(.title2.bold())
                
                Text(messageForDeferredBanner(destination))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                onOpenApp("kidbox://share?destination=\(destination.rawStringValue)")
            } label: {
                Label("Apri KidBox", systemImage: "arrow.up.right.app.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(destination.color, in: RoundedRectangle(cornerRadius: 14))
            }
            
            Button("Annulla") {
                UserDefaults(suiteName: appGroupId)?.removeObject(forKey: "pendingShare")
                onDone()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            
            Spacer(minLength: 40)
        }
        .padding(32)
    }
    
    private func messageForDeferredBanner(_ destination: KBShareDestination) -> String {
        switch destination {
        case .chat:
            return "Apri KidBox per completare l’invio in chat."
        case .todo:
            return "Apri KidBox per completare la creazione del to-do."
        case .event:
            return "Apri KidBox per completare la creazione dell’evento."
        case .grocery:
            return "Apri KidBox per completare l’aggiunta alla lista spesa."
        case .document:
            return "Apri KidBox per completare il salvataggio del documento."
        case .note:
            return "Apri KidBox per completare la nota."
        }
    }
    
    // MARK: - Preview
    
    @ViewBuilder
    private var payloadPreview: some View {
        switch payload.type {
        case .image(let url):
            if let url, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
        case .text(let t):
            Text(t)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            
        case .url(let u):
            if let fileURL = URL(string: u), fileURL.isFileURL {
                filePreviewCard(for: fileURL)
            } else if isImageURL(u) {
                Group {
                    if let img = remoteImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 160)
                            .overlay(ProgressView())
                    }
                }
                .task {
                    guard let url = URL(string: u),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          let img = UIImage(data: data) else { return }
                    remoteImage = img
                }
            } else {
                Text(u)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(2)
            }
            
        case .file(let url):
            filePreviewCard(for: url)
            
        case .unknown:
            EmptyView()
        }
    }
    
    private func isImageURL(_ u: String) -> Bool {
        let ext = URL(string: u)?.pathExtension.lowercased() ?? ""
        return ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(ext)
    }
    
    private func filePreviewCard(for url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: fileIcon(for: url))
                .font(.title2)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                
                Text(url.pathExtension.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    
    private func fileIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "doc.richtext.fill"
        case "jpg", "jpeg", "png", "heic":
            return "photo.fill"
        case "mp4", "mov", "m4v":
            return "video.fill"
        case "doc", "docx":
            return "doc.fill"
        case "xls", "xlsx":
            return "tablecells.fill"
        case "zip", "rar":
            return "archivebox.fill"
        default:
            return "doc.fill"
        }
    }
    
    // MARK: - Edit fields
    
    @ViewBuilder
    private var editFields: some View {
        switch destination {
        case .todo:
            VStack(alignment: .leading, spacing: 8) {
                Label("Titolo del to-do", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                TextField("Es. Comprare latte", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
            }
            
        case .grocery:
            VStack(alignment: .leading, spacing: 8) {
                Label("Aggiungi alla lista spesa", systemImage: "cart")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                TextField("Es. Latte, pane, uova", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                
                Text("Ogni riga diventerà un articolo separato")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
        case .event:
            VStack(alignment: .leading, spacing: 8) {
                Label("Titolo evento", systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                TextField("Es. Visita pediatra", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                
                Label("Note aggiuntive", systemImage: "text.alignleft")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                
                TextEditor(text: $editedText)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3))
                    )
            }
            
        case .note:
            VStack(alignment: .leading, spacing: 8) {
                Label("Titolo nota", systemImage: "note.text")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                TextField("Titolo", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                
                if !editedText.isEmpty {
                    Label("Testo", systemImage: "text.alignleft")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    
                    TextEditor(text: $editedText)
                        .frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                }
            }
            
        case .chat:
            switch payload.type {
            case .image, .file:
                Text("Il file verrà inviato direttamente nella chat di famiglia.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
            case .url(let u) where URL(string: u)?.isFileURL == true:
                Text("Il file verrà inviato direttamente nella chat di famiglia.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
            case .url(let u) where isImageURL(u):
                Text("L'immagine verrà inviata direttamente nella chat di famiglia.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
            default:
                TextField("Messaggio", text: $editedText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4)
            }
            
        case .document:
            VStack(alignment: .leading, spacing: 8) {
                Text("Il file verrà salvato nella sezione Documenti.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Label("Titolo documento", systemImage: "folder")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                
                TextField("Es. Referti agosto 2025", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
            }
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
            if destination == .event {
                let parsed = parseEventText(t)
                editedTitle = parsed.title
                editedText = parsed.notes
            } else {
                let lines = t.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                editedTitle = lines.first ?? t
                editedText = lines.dropFirst().joined(separator: "\n")
            }
            
        case .url(let u):
            if let fileURL = URL(string: u), fileURL.isFileURL {
                editedTitle = fileURL.deletingPathExtension().lastPathComponent
            } else {
                editedTitle = u
                editedText = u
            }
            
        case .file(let url):
            editedTitle = url.deletingPathExtension().lastPathComponent
            
        default:
            break
        }
    }
    
    private func parseEventText(_ text: String) -> ParsedEventShare {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        
        var detectedDate: Date?
        var cleanedTitle = trimmed
        
        if let match = detector?.firstMatch(in: trimmed, range: range),
           let date = match.date,
           let swiftRange = Range(match.range, in: trimmed) {
            detectedDate = date
            
            var tmp = trimmed
            tmp.removeSubrange(swiftRange)
            
            cleanedTitle = tmp
                .replacingOccurrences(of: "  ", with: " ")
                .replacingOccurrences(of: " ,", with: ",")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if cleanedTitle.isEmpty {
            cleanedTitle = "Nuovo evento"
        }
        
        return ParsedEventShare(
            title: cleanedTitle,
            notes: trimmed,
            detectedDate: detectedDate
        )
    }
    
    // MARK: - Send
    
    private func sendToDestination() async {
        guard !hasSent else {
            log("sendToDestination SKIPPED — hasSent=true (double-tap guard)")
            return
        }
        hasSent = true
        log("sendToDestination START destination=\(destination.rawStringValue)")
        isSending = true
        errorMessage = nil
        
        do {
            let result: ShareSendResult
            
            switch destination {
            case .chat:
                result = try await sendDirectToChat()
                
            case .note:
                result = try await sendDirectToNote()
                
            case .todo, .event, .grocery:
                saveToAppGroup()
                result = .deferredToMainApp(
                    urlString: "kidbox://share?destination=\(destination.rawStringValue)",
                    showBanner: true
                )
                
            case .document:
                saveToAppGroup()
                result = .deferredToMainApp(
                    urlString: "kidbox://share?destination=\(destination.rawStringValue)",
                    showBanner: false
                )
            }
            
            log("sendToDestination result computed")
            
            switch result {
            case .completedInExtension:
                log("sendToDestination completed in extension → closing")
                onDone()
                
            case .deferredToMainApp(let urlString, let showBanner):
                if showBanner {
                    log("sendToDestination deferred with banner")
                    isSending = false
                    deferredBannerDestination = destination
                } else {
                    log("sendToDestination opening main app url=\(urlString)")
                    onOpenApp(urlString)
                }
                
            case .videoDeferredToMainApp:
                log("sendToDestination video deferred → showing banner")
                isSending = false
                videoSavedToAppGroup = true
            }
            
        } catch {
            log("sendToDestination ERROR: \(error.localizedDescription)")
            isSending = false
            errorMessage = "Errore: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Chat: invio diretto da extension
    
    private func sendDirectToChat() async throws -> ShareSendResult {
        log("sendDirectToChat START")
        
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let familyId = defaults.string(forKey: "activeFamilyId"),
              !familyId.isEmpty else {
            log("sendDirectToChat ERROR: familyId not found in App Group")
            throw ShareError.missingFamilyId
        }
        
        log("sendDirectToChat familyId=\(familyId)")
        
        let messageId = UUID().uuidString
        let storage = ChatStorageService()
        let remote = ChatRemoteStore()
        
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
            return .completedInExtension
            
        case .file(let url):
            let ext = url.pathExtension.lowercased()
            let isVideo = ["mp4", "mov", "m4v"].contains(ext)
            let isImage = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"].contains(ext)
            
            if isVideo {
                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                let maxBytes = 200 * 1024 * 1024
                
                guard fileSize <= maxBytes else {
                    let sizeMB = fileSize / (1024 * 1024)
                    throw ShareError.videoTooLarge(sizeMB: sizeMB)
                }
                
                let name = "share_\(UUID().uuidString)_\(url.lastPathComponent)"
                guard let groupURL = copyFileToAppGroup(url, name: name) else {
                    throw ShareError.missingFile
                }
                
                let pendingData: [String: String] = [
                    "destination": "chat",
                    "sharedFilePath": groupURL.path,
                    "sharedFileType": "video",
                    "sharedFileName": url.lastPathComponent,
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ]
                
                UserDefaults(suiteName: appGroupId)?.set(pendingData, forKey: "pendingShare")
                log("sendDirectToChat video saved to AppGroup path=\(groupURL.path)")
                return .videoDeferredToMainApp
            }
            
            let (fileName, mimeType, typeRaw): (String, String, String) = {
                if isImage { return ("photo.jpg", "image/jpeg", "photo") }
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
                text: typeRaw == "document" ? url.lastPathComponent : nil,
                mediaStoragePath: storagePath,
                mediaURL: downloadURL
            )
            try await remote.upsert(dto: dto)
            return .completedInExtension
            
        case .url(let u):
            if let fileURL = URL(string: u), fileURL.isFileURL {
                let accessed = fileURL.startAccessingSecurityScopedResource()
                defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
                
                guard let data = try? Data(contentsOf: fileURL) else {
                    throw ShareError.missingFile
                }
                
                let fileName = fileURL.lastPathComponent
                log("sendDirectToChat uploading file-url bytes=\(data.count) name=\(fileName)")
                let (storagePath, downloadURL) = try await storage.upload(
                    data: data,
                    familyId: familyId,
                    messageId: messageId,
                    fileName: fileName,
                    mimeType: "application/octet-stream"
                )
                
                let dto = makeDTO(
                    messageId: messageId,
                    familyId: familyId,
                    typeRaw: "document",
                    text: fileName,
                    mediaStoragePath: storagePath,
                    mediaURL: downloadURL
                )
                try await remote.upsert(dto: dto)
                return .completedInExtension
                
            } else if isImageURL(u) {
                guard let imgURL = URL(string: u),
                      let (data, _) = try? await URLSession.shared.data(from: imgURL),
                      !data.isEmpty else {
                    throw ShareError.missingFile
                }
                
                log("sendDirectToChat uploading remote image bytes=\(data.count)")
                let (storagePath, downloadURL) = try await storage.upload(
                    data: data,
                    familyId: familyId,
                    messageId: messageId,
                    fileName: "photo.jpg",
                    mimeType: "image/jpeg"
                )
                
                let dto = makeDTO(
                    messageId: messageId,
                    familyId: familyId,
                    typeRaw: "photo",
                    mediaStoragePath: storagePath,
                    mediaURL: downloadURL
                )
                try await remote.upsert(dto: dto)
                return .completedInExtension
                
            } else {
                let text = editedText.isEmpty ? u : editedText
                log("sendDirectToChat sending url=\(u)")
                let dto = makeDTO(
                    messageId: messageId,
                    familyId: familyId,
                    typeRaw: "text",
                    text: text
                )
                try await remote.upsert(dto: dto)
                return .completedInExtension
            }
            
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
            return .completedInExtension
            
        case .unknown:
            log("sendDirectToChat unknown payload — nothing to send")
            return .completedInExtension
        }
    }
    
    // MARK: - Note: creazione diretta su Firestore dall'extension
    
    private func sendDirectToNote() async throws -> ShareSendResult {
        log("sendDirectToNote START")
        
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let familyId = defaults.string(forKey: "activeFamilyId"),
              !familyId.isEmpty else {
            throw ShareError.missingFamilyId
        }
        
        let uid = defaults.string(forKey: "currentUserUID") ?? ""
        let displayName = defaults.string(forKey: "currentUserDisplayName") ?? ""
        
        guard !uid.isEmpty else {
            log("sendDirectToNote ERROR: uid not found in App Group")
            throw ShareError.missingFamilyId
        }
        
        let title: String
        let body: String
        
        switch payload.type {
        case .text(let t):
            let raw = editedText.isEmpty ? t : editedText
            let lines = raw.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            title = editedTitle.isEmpty ? (lines.first ?? raw) : editedTitle
            body = lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : raw
            
        case .url(let u):
            body = u
            title = editedTitle.isEmpty ? u : editedTitle
            
        default:
            body = editedText
            title = editedTitle
        }
        
        let noteId = UUID().uuidString
        let store = NotesRemoteStore()
        
        try await store.upsertRaw(
            noteId: noteId,
            familyId: familyId,
            title: title,
            body: body,
            uid: uid,
            displayName: displayName
        )
        
        log("sendDirectToNote OK noteId=\(noteId)")
        return .completedInExtension
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
        let defaults = UserDefaults(suiteName: appGroupId)
        let senderName = defaults?.string(forKey: "currentUserDisplayName") ?? "Utente"
        let senderId = defaults?.string(forKey: "currentUserUID") ?? "unknown"
        log("makeDTO senderId=\(senderId) senderName=\(senderName)")
        
        return RemoteChatMessageDTO(
            id: messageId,
            familyId: familyId,
            senderId: senderId,
            senderName: senderName,
            typeRaw: typeRaw,
            text: text,
            mediaStoragePath: mediaStoragePath,
            mediaURL: mediaURL,
            mediaDurationSeconds: nil,
            mediaThumbnailURL: nil,
            replyToId: nil,
            reactionsJSON: nil,
            readByJSON: nil,
            createdAt: Date(),
            editedAt: nil,
            isDeleted: false,
            deletedFor: [],
            latitude: nil,
            longitude: nil
        )
    }
    
    // MARK: - App Group (per destinazioni non-chat)
    
    private func saveToAppGroup() {
        var data: [String: String] = [
            "destination": destination.rawStringValue,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        switch payload.type {
        case .text(let t):
            let finalText = editedText.isEmpty ? t : editedText
            data["text"] = finalText
            data["title"] = editedTitle
            
            if destination == .event {
                let parsed = parseEventText(finalText)
                data["title"] = editedTitle.isEmpty ? parsed.title : editedTitle
                
                if let date = parsed.detectedDate {
                    data["eventStartDate"] = ISO8601DateFormatter().string(from: date)
                }
            }
            
        case .url(let u):
            if let fileURL = URL(string: u), fileURL.isFileURL {
                let name = "share_\(UUID().uuidString)_\(fileURL.lastPathComponent)"
                if let groupURL = copyFileToAppGroup(fileURL, name: name) {
                    data["sharedFilePath"] = groupURL.path
                    data["sharedFileType"] = "file"
                    data["sharedFileName"] = fileURL.lastPathComponent
                }
                data["title"] = editedTitle
            } else {
                data["text"] = u
                
                if destination == .event {
                    let parsed = parseEventText(u)
                    data["title"] = editedTitle.isEmpty ? parsed.title : editedTitle
                    
                    if let date = parsed.detectedDate {
                        data["eventStartDate"] = ISO8601DateFormatter().string(from: date)
                    }
                } else {
                    data["title"] = editedTitle
                }
            }
            
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
    
    // MARK: - Helpers
    
    private func imageData(from url: URL) -> Data? {
        if let data = try? Data(contentsOf: url) { return data }
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
        
        if (try? FileManager.default.copyItem(at: source, to: dest)) != nil {
            return dest
        }
        
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        
        guard let data = try? Data(contentsOf: source),
              (try? data.write(to: dest, options: .atomic)) != nil else {
            return nil
        }
        
        return dest
    }
}

// MARK: - Errors

enum ShareError: LocalizedError {
    case missingFamilyId
    case missingFile
    case videoTooLarge(sizeMB: Int)
    
    var errorDescription: String? {
        switch self {
        case .missingFamilyId:
            return "Apri KidBox almeno una volta per configurare la famiglia."
        case .missingFile:
            return "Impossibile leggere il file selezionato."
        case .videoTooLarge(let sizeMB):
            return "Il video è troppo grande (\(sizeMB) MB). Il limite massimo è 200 MB."
        }
    }
}
