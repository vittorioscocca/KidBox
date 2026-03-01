//
//  ChatViewModel.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//

import Foundation
import SwiftUI
import SwiftData
import Combine
import FirebaseAuth
import FirebaseFirestore
import AVFoundation
import OSLog

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        self.isEmpty ? fallback : self
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    
    // MARK: - Input
    let familyId: String
    
    // MARK: - Published state
    @Published var messages: [KBChatMessage] = []
    @Published var inputText: String = ""
    @Published var isSending: Bool = false
    @Published var isUploadingMedia: Bool = false
    @Published var isCompressingMedia: Bool = false
    @Published var uploadProgress: Double = 0
    @Published var errorText: String?
    @Published var replyingPreviewLatitude: Double?
    @Published var replyingPreviewLongitude: Double?
    
    // Paginazione
    @Published var isLoadingOlder: Bool = false
    @Published var hasMoreMessages: Bool = true
    @Published var isPaginating: Bool = false
    
    // Audio recording
    @Published var isRecording: Bool = false
    // FIX 2: recordingDuration non è più @Published.
    var recordingDuration: TimeInterval = 0
    
    // FIX 3: typingUsers aggiornato con throttle
    @Published var typingUsers: [String] = []
    private var pendingTypingUsers: [String]? = nil
    private var typingThrottleTask: Task<Void, Never>? = nil
    
    @Published var editingMessageId: String? = nil
    @Published var editingOriginalText: String = ""
    
    // Reply
    @Published var replyingToMessageId: String? = nil
    @Published var replyingPreviewName: String = ""
    @Published var replyingPreviewText: String = ""
    @Published var replyingPreviewKind: KBChatMessageType? = nil
    @Published var replyingPreviewMediaURL: String? = nil
    @Published var replyingPreviewAudioDuration: Int? = nil
    
    var isReplying: Bool { replyingToMessageId != nil }
    
    // MARK: - Private
    private var modelContext: ModelContext?
    private var listener: (any ListenerRegistrationProtocol)?
    private var typingListener: (any ListenerRegistrationProtocol)?
    private var typingDebounceTask: Task<Void, Never>? = nil
    private var cancellables = Set<AnyCancellable>()
    private var isObserving = false
    private var oldestDocument: DocumentSnapshot? = nil
    private let proximityRouter = ProximityAudioRouter()
    private let remoteStore = ChatRemoteStore()
    private let storageService = ChatStorageService()
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingURL: URL?
    
    // FIX 4: debounce reloadLocal per evitare stutter mentre scrolli
    private var reloadTask: Task<Void, Never>?
    
    var isEditing: Bool { editingMessageId != nil }
    
    func canEditOrDelete(_ message: KBChatMessage) -> Bool {
        Date().timeIntervalSince(message.createdAt) < 5 * 60
    }
    
    // MARK: - Init
    
    init(familyId: String) {
        self.familyId = familyId
    }
    
    func bind(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Start / Stop
    
    func startListening() {
        guard !isObserving else { return }
        isObserving = true
        
        KBLog.sync.kbInfo("ChatVM startListening familyId=\(familyId)")
        
        let uid = Auth.auth().currentUser?.uid ?? ""
        let name = senderDisplayName()
        Task { await remoteStore.setTyping(false, familyId: familyId, uid: uid, displayName: name) }
        
        listener = FirestoreListenerWrapper(remoteStore.listenMessages(
            familyId: familyId,
            limit: 150,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in self.applyRemoteChanges(changes) }
            },
            onOldestDocument: { [weak self] snapshot in
                guard let self else { return }
                Task { @MainActor in
                    if self.oldestDocument == nil {
                        self.oldestDocument = snapshot
                        KBLog.sync.kbInfo("ChatVM cursor set to \(snapshot.documentID)")
                    }
                }
            },
            onError: { [weak self] error in
                guard let self else { return }
                Task { @MainActor in self.errorText = error.localizedDescription }
            }
        ))
        
        typingListener = FirestoreListenerWrapper(remoteStore.listenTyping(
            familyId: familyId,
            excludeUID: uid,
            onChange: { [weak self] names in
                guard let self else { return }
                Task { @MainActor in self.scheduleTypingUpdate(names) }
            }
        ))
        
        // Primo load
        reloadLocal()
    }
    
    // FIX 3: accumula gli update e pubblica al massimo una volta ogni 500ms
    private func scheduleTypingUpdate(_ names: [String]) {
        pendingTypingUsers = names
        guard typingThrottleTask == nil else { return }
        typingThrottleTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if let pending = pendingTypingUsers {
                typingUsers = pending
                pendingTypingUsers = nil
            }
            typingThrottleTask = nil
        }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
        
        typingListener?.remove()
        typingListener = nil
        
        typingThrottleTask?.cancel()
        typingThrottleTask = nil
        
        reloadTask?.cancel()
        reloadTask = nil
        
        isObserving = false
        oldestDocument = nil
        hasMoreMessages = true
        
        let uid = Auth.auth().currentUser?.uid ?? ""
        let name = senderDisplayName()
        Task { await remoteStore.setTyping(false, familyId: familyId, uid: uid, displayName: name) }
        
        KBLog.sync.kbInfo("ChatVM stopListening familyId=\(familyId)")
    }
    
    // MARK: - Paginazione
    
    @MainActor
    func loadOlderMessages() {
        guard !isLoadingOlder,
              hasMoreMessages,
              let cursor = oldestDocument,
              let modelContext else { return }
        
        isLoadingOlder = true
        isPaginating = true
        
        Task {
            do {
                let (dtos, newCursor) = try await remoteStore.fetchOlderMessages(
                    familyId: familyId,
                    before: cursor,
                    limit: 150
                )
                
                await MainActor.run {
                    if dtos.isEmpty {
                        self.hasMoreMessages = false
                    } else {
                        for dto in dtos {
                            self.applyUpsert(dto: dto, modelContext: modelContext)
                        }
                        try? modelContext.save()
                        
                        self.oldestDocument = newCursor
                        if newCursor == nil { self.hasMoreMessages = false }
                        
                        // FIX 4: debounce reload dopo paginazione (non sparare fetch multipli)
                        self.requestReloadLocal(debounceMs: 120, reason: "pagination")
                    }
                    
                    self.isLoadingOlder = false
                    self.isPaginating = false
                }
            } catch {
                await MainActor.run {
                    self.errorText = "Errore caricamento messaggi: \(error.localizedDescription)"
                    self.isLoadingOlder = false
                    self.isPaginating = false
                }
            }
        }
    }
    
    // MARK: - Local fetch
    
    /// FIX 4: chiamalo nei punti "caldi" invece di reloadLocal() diretto
    func requestReloadLocal(debounceMs: Int = 120, reason: String = "") {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(debounceMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.reloadLocal()
            }
        }
    }
    
    @MainActor
    func reloadLocal() {
        guard let modelContext else { return }
        
        let fam = familyId
        let desc = FetchDescriptor<KBChatMessage>(
            predicate: #Predicate { $0.familyId == fam && $0.isDeleted == false },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        
        do {
            let rows = try modelContext.fetch(desc)
            
            // IMPORTANTISSIMO: se l'ordine e gli id sono identici,
            // NON sostituire l'array => niente jump / niente re-layout massivo.
            let newIds  = rows.map(\.id)
            let currIds = messages.map(\.id)
            if newIds == currIds {
                return
            }
            
            self.messages = rows
            KBLog.data.kbInfo("reloadLocal: fetched \(rows.count) messages familyId=\(familyId)")
        } catch {
            KBLog.data.kbError("reloadLocal: FAILED error=\(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func saveContext(_ context: ModelContext, reason: String) {
        do {
            try context.save()
        } catch {
            KBLog.persistence.kbError("ChatVM save FAILED reason=\(reason) error=\(error.localizedDescription)")
            self.errorText = "Salvataggio locale fallito: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Apply remote changes
    
    private func applyRemoteChanges(_ changes: [ChatRemoteChange]) {
        guard let modelContext else { return }
        
        for change in changes {
            switch change {
            case .upsert(let dto):
                applyUpsert(dto: dto, modelContext: modelContext)
                
            case .remove(let id):
                let mid = id
                let desc = FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.id == mid })
                if let local = try? modelContext.fetch(desc).first {
                    modelContext.delete(local)
                }
            }
        }
        
        try? modelContext.save()
        
        // FIX 4: invece di reloadLocal immediato (che può scattare durante scroll)
        requestReloadLocal(debounceMs: 120, reason: "applyRemoteChanges")
    }
    
    private func applyUpsert(dto: RemoteChatMessageDTO, modelContext: ModelContext) {
        let mid = dto.id
        let myUID = Auth.auth().currentUser?.uid ?? ""
        let deletedForMe = !myUID.isEmpty && dto.deletedFor.contains(myUID)
        
        let desc = FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.id == mid })
        
        if let existing = try? modelContext.fetch(desc).first {
            let localBefore = existing.isDeleted
            
            existing.senderName    = dto.senderName
            existing.text          = dto.text
            existing.editedAt      = dto.editedAt
            existing.mediaURL      = dto.mediaURL
            existing.reactionsJSON = dto.reactionsJSON
            
            existing.readBy = Array(Set(existing.readBy + dto.readBy))
            existing.isDeleted = localBefore || dto.isDeleted || deletedForMe
            
            existing.syncState     = .synced
            existing.lastSyncError = nil
            
            existing.replyToId  = dto.replyToId
            existing.latitude   = dto.latitude
            existing.longitude  = dto.longitude
            
        } else {
            guard !dto.isDeleted && !deletedForMe else { return }
            
            let msg = KBChatMessage(
                id: dto.id,
                familyId: dto.familyId,
                senderId: dto.senderId,
                senderName: dto.senderName,
                type: KBChatMessageType(rawValue: dto.typeRaw) ?? .text,
                text: dto.text,
                mediaStoragePath: dto.mediaStoragePath,
                mediaURL: dto.mediaURL,
                mediaDurationSeconds: dto.mediaDurationSeconds,
                mediaThumbnailURL: dto.mediaThumbnailURL,
                createdAt: dto.createdAt ?? Date(),
                editedAt: dto.editedAt,
                isDeleted: false
            )
            msg.replyToId     = dto.replyToId
            msg.reactionsJSON = dto.reactionsJSON
            msg.readByJSON    = dto.readByJSON
            msg.syncState     = .synced
            msg.lastSyncError = nil
            msg.latitude      = dto.latitude
            msg.longitude     = dto.longitude
            
            modelContext.insert(msg)
        }
    }
    
    // MARK: - ─── SEND TEXT ───────────────────────────────────────────────────
    
    func sendText() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        
        if isEditing {
            commitEditing()
            return
        }
        
        let replyId = replyingToMessageId
        inputText = ""
        
        if replyId != nil {
            send(type: .text, text: trimmed, replyToId: replyId)
            cancelReply()
        } else {
            send(type: .text, text: trimmed)
        }
    }
    
    func startEditing(_ message: KBChatMessage) {
        guard message.senderId == Auth.auth().currentUser?.uid,
              message.type == .text else { return }
        
        guard canEditOrDelete(message) else {
            errorText = "Puoi modificare un messaggio solo entro 5 minuti dall'invio."
            return
        }
        
        editingMessageId = message.id
        editingOriginalText = message.text ?? ""
        inputText = editingOriginalText
    }
    
    func cancelEditing() {
        editingMessageId = nil
        editingOriginalText = ""
        inputText = ""
    }
    
    func commitEditing() {
        guard let modelContext,
              let messageId = editingMessageId else { return }
        
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed != editingOriginalText else { cancelEditing(); return }
        guard !isSending else { return }
        
        stopTyping()
        isSending = true
        errorText = nil
        
        // update locale immediato
        if let msg = messages.first(where: { $0.id == messageId }) {
            msg.text = trimmed
            msg.editedAt = Date()
            msg.syncState = .pendingUpsert
            msg.lastSyncError = nil
            try? modelContext.save()
            // NON serve reloadLocal: @Model si aggiorna da sola
        }
        
        Task {
            do {
                try await remoteStore.updateMessageText(
                    familyId: familyId,
                    messageId: messageId,
                    text: trimmed
                )
                
                await MainActor.run {
                    if let msg = self.messages.first(where: { $0.id == messageId }) {
                        msg.syncState = .synced
                        try? modelContext.save()
                    }
                    self.isSending = false
                    self.cancelEditing()
                }
            } catch {
                await MainActor.run {
                    if let msg = self.messages.first(where: { $0.id == messageId }) {
                        msg.syncState = .error
                        msg.lastSyncError = error.localizedDescription
                        try? modelContext.save()
                    }
                    self.isSending = false
                    self.errorText = error.localizedDescription
                }
            }
        }
    }
    
    func startReply(to message: KBChatMessage) {
        if isEditing { cancelEditing() }
        
        replyingToMessageId = message.id
        
        let name = message.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        replyingPreviewName = name.isEmpty ? "Utente" : name
        
        replyingPreviewKind = message.type
        replyingPreviewMediaURL = message.mediaURL
        replyingPreviewAudioDuration = message.mediaDurationSeconds
        
        switch message.type {
        case .text:
            replyingPreviewText = (message.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .ifEmpty("Messaggio")
        case .photo:
            replyingPreviewText = ""
        case .video:
            replyingPreviewText = "🎬 Video"
        case .audio:
            let d = message.mediaDurationSeconds ?? 0
            replyingPreviewText = d > 0 ? "Messaggio vocale • \(formatDuration(d))" : "Messaggio vocale"
        case .document:
            replyingPreviewText = "📄 \(message.text ?? "Documento")"
        case .location:
            replyingPreviewText = "📍 Posizione condivisa"
            replyingPreviewLatitude = message.latitude
            replyingPreviewLongitude = message.longitude
        }
    }
    
    func cancelReply() {
        replyingToMessageId = nil
        replyingPreviewName = ""
        replyingPreviewText = ""
        replyingPreviewKind = nil
        replyingPreviewMediaURL = nil
        replyingPreviewAudioDuration = nil
        replyingPreviewLatitude = nil
        replyingPreviewLongitude = nil
    }
    
    private func formatDuration(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }
    
    // MARK: - ─── TYPING ──────────────────────────────────────────────────────
    
    func userIsTyping() {
        typingDebounceTask?.cancel()
        let uid = Auth.auth().currentUser?.uid ?? ""
        let name = senderDisplayName()
        Task { await remoteStore.setTyping(true, familyId: familyId, uid: uid, displayName: name) }
        
        typingDebounceTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { stopTyping() }
        }
    }
    
    func stopTyping() {
        typingDebounceTask?.cancel()
        typingDebounceTask = nil
        
        let uid = Auth.auth().currentUser?.uid ?? ""
        let name = senderDisplayName()
        Task { await remoteStore.setTyping(false, familyId: familyId, uid: uid, displayName: name) }
    }
    
    // MARK: - ─── SEND PHOTO / VIDEO ──────────────────────────────────────────
    
    func sendMedia(data: Data, type: KBChatMessageType) {
        guard !isUploadingMedia else { return }
        Task { await uploadAndSend(data: data, type: type) }
    }
    
    private func uploadAndSend(data: Data, type: KBChatMessageType) async {
        guard let modelContext else { return }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let senderName = senderDisplayName()
        let messageId = UUID().uuidString
        let now = Date()
        let (fileName, mimeType) = ChatStorageService.fileInfo(for: type)
        
        errorText = nil
        
        let uploadData: Data
        do {
            switch type {
            case .photo:
                isCompressingMedia = true
                uploadData = await compressPhoto(data: data)
                isCompressingMedia = false
            case .video:
                isCompressingMedia = true
                uploadData = try await compressVideo(data: data)
                isCompressingMedia = false
            default:
                uploadData = data
            }
        } catch {
            isCompressingMedia = false
            errorText = "Compressione fallita: \(error.localizedDescription)"
            return
        }
        
        isUploadingMedia = true
        uploadProgress = 0
        
        let msg = KBChatMessage(
            id: messageId,
            familyId: familyId,
            senderId: uid,
            senderName: senderName,
            type: type,
            createdAt: now
        )
        msg.syncState = .pendingUpsert
        modelContext.insert(msg)
        try? modelContext.save()
        
        // mostra subito il placeholder in lista
        reloadLocal()
        
        do {
            let (storagePath, downloadURL) = try await storageService.upload(
                data: uploadData,
                familyId: familyId,
                messageId: messageId,
                fileName: fileName,
                mimeType: mimeType,
                progressHandler: { [weak self] p in
                    Task { @MainActor in self?.uploadProgress = p }
                }
            )
            
            msg.mediaStoragePath = storagePath
            msg.mediaURL = downloadURL
            msg.syncState = .pendingUpsert
            try? modelContext.save()
            
            // qui serve per far apparire la thumb/immagine
            reloadLocal()
            
            let dto = makeDTO(from: msg)
            try await remoteStore.upsert(dto: dto)
            
            msg.syncState = .synced
            msg.lastSyncError = nil
            try? modelContext.save()
            
        } catch {
            msg.syncState = .error
            msg.lastSyncError = error.localizedDescription
            try? modelContext.save()
            errorText = "Invio media fallito: \(error.localizedDescription)"
        }
        
        isUploadingMedia = false
        uploadProgress = 0
    }
    
    // MARK: - ─── COMPRESSION ─────────────────────────────────────────────────
    
    private func compressPhoto(data: Data) async -> Data {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
            
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let w = (props?[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0
            let h = (props?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
            
            let maxSide: CGFloat = 1920
            let scale = (max(w, h) > maxSide && max(w, h) > 0) ? (maxSide / max(w, h)) : 1.0
            let targetMaxPixel = Int((max(w, h) * scale).rounded())
            
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: max(targetMaxPixel, 1),
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
            
            guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return data
            }
            
            return UIImage(cgImage: cgThumb).jpegData(compressionQuality: 0.75) ?? data
        }.value
    }
    
    private func compressVideo(data: Data) async throws -> Data {
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        try data.write(to: inputURL)
        defer { try? FileManager.default.removeItem(at: inputURL) }
        
        let asset = AVURLAsset(url: inputURL)
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetMediumQuality
        ) else { return data }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        
        do {
            try await session.export(to: outputURL, as: .mp4, isolation: .none)
        } catch {
            return data
        }
        
        return (try? Data(contentsOf: outputURL)) ?? data
    }
    
    // MARK: - ─── SEND AUDIO ──────────────────────────────────────────────────
    
    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        guard (try? session.setCategory(.playAndRecord, mode: .default)) != nil,
              (try? session.setActive(true)) != nil else { return }
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat_audio_\(UUID().uuidString).m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return }
        recorder.record()
        
        audioRecorder = recorder
        recordingURL = url
        isRecording = true
        recordingDuration = 0
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.recordingDuration = self.audioRecorder?.currentTime ?? 0
            }
        }
    }
    
    func stopAndSendRecording() {
        guard isRecording,
              let recorder = audioRecorder,
              let url = recordingURL else { return }
        
        let seconds = recorder.currentTime
        
        recorder.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        isRecording = false
        recordingDuration = 0
        audioRecorder = nil
        recordingURL = nil
        
        guard seconds >= 0.4 else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        
        let durationSeconds = max(1, Int(seconds.rounded()))
        
        Task {
            do {
                let data = try Data(contentsOf: url)
                await uploadAndSendAudio(data: data, duration: durationSeconds)
            } catch {
                await MainActor.run {
                    self.errorText = "Audio non leggibile: \(error.localizedDescription)"
                }
            }
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    func cancelRecording() {
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        isRecording = false
        recordingDuration = 0
        
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        audioRecorder = nil
    }
    
    private func uploadAndSendAudio(data: Data, duration: Int) async {
        guard let modelContext else { return }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let senderName = senderDisplayName()
        let messageId = UUID().uuidString
        let now = Date()
        
        isUploadingMedia = true
        uploadProgress = 0
        
        let msg = KBChatMessage(
            id: messageId,
            familyId: familyId,
            senderId: uid,
            senderName: senderName,
            type: .audio,
            mediaDurationSeconds: duration,
            createdAt: now
        )
        msg.syncState = .pendingUpsert
        modelContext.insert(msg)
        try? modelContext.save()
        reloadLocal()
        
        do {
            let (storagePath, downloadURL) = try await storageService.upload(
                data: data,
                familyId: familyId,
                messageId: messageId,
                fileName: "audio.m4a",
                mimeType: "audio/x-m4a",
                progressHandler: { [weak self] p in
                    Task { @MainActor in self?.uploadProgress = p }
                }
            )
            
            msg.mediaStoragePath = storagePath
            msg.mediaURL = downloadURL
            msg.mediaDurationSeconds = duration
            msg.syncState = .pendingUpsert
            try? modelContext.save()
            
            let dto = makeDTO(from: msg)
            try await remoteStore.upsert(dto: dto)
            
            msg.syncState = .synced
            msg.lastSyncError = nil
            try? modelContext.save()
            
        } catch {
            msg.syncState = .error
            msg.lastSyncError = error.localizedDescription
            try? modelContext.save()
            errorText = "Invio audio fallito: \(error.localizedDescription)"
        }
        
        isUploadingMedia = false
        uploadProgress = 0
    }
    
    // MARK: - ─── SEND DOCUMENT ───────────────────────────────────────────────
    
    func sendDocument(url: URL) {
        Task { await uploadAndSendDocument(url: url) }
    }
    
    private func uploadAndSendDocument(url: URL) async {
        guard let modelContext else { return }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let senderName = senderDisplayName()
        let messageId = UUID().uuidString
        let now = Date()
        
        let fileName = url.lastPathComponent
        let mimeType = url.mimeType()
        
        isUploadingMedia = true
        uploadProgress = 0
        errorText = nil
        
        let msg = KBChatMessage(
            id: messageId,
            familyId: familyId,
            senderId: uid,
            senderName: senderName,
            type: .document,
            text: fileName,
            createdAt: now
        )
        msg.syncState = .pendingUpsert
        modelContext.insert(msg)
        try? modelContext.save()
        reloadLocal()
        
        do {
            let data = try Data(contentsOf: url)
            
            let (storagePath, downloadURL) = try await storageService.upload(
                data: data,
                familyId: familyId,
                messageId: messageId,
                fileName: fileName,
                mimeType: mimeType,
                progressHandler: { [weak self] p in
                    Task { @MainActor in self?.uploadProgress = p }
                }
            )
            
            msg.mediaStoragePath = storagePath
            msg.mediaURL = downloadURL
            msg.syncState = .pendingUpsert
            try? modelContext.save()
            
            let dto = makeDTO(from: msg)
            try await remoteStore.upsert(dto: dto)
            
            msg.syncState = .synced
            msg.lastSyncError = nil
            try? modelContext.save()
            
        } catch {
            msg.syncState = .error
            msg.lastSyncError = error.localizedDescription
            try? modelContext.save()
            errorText = "Invio documento fallito: \(error.localizedDescription)"
        }
        
        isUploadingMedia = false
        uploadProgress = 0
    }
    
    // MARK: - ─── SEND (core) ─────────────────────────────────────────────────
    
    private func send(type: KBChatMessageType, text: String? = nil) {
        guard let modelContext else { return }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let senderName = senderDisplayName()
        let messageId = UUID().uuidString
        let now = Date()
        
        isSending = true
        
        let msg = KBChatMessage(
            id: messageId,
            familyId: familyId,
            senderId: uid,
            senderName: senderName,
            type: type,
            text: text,
            createdAt: now
        )
        msg.syncState = .pendingUpsert
        
        modelContext.insert(msg)
        try? modelContext.save()
        reloadLocal()
        
        Task {
            let dto = makeDTO(from: msg)
            do {
                try await remoteStore.upsert(dto: dto)
                msg.syncState = .synced
                msg.lastSyncError = nil
                try? modelContext.save()
            } catch {
                msg.syncState = .error
                msg.lastSyncError = error.localizedDescription
                try? modelContext.save()
                errorText = "Invio fallito: \(error.localizedDescription)"
            }
            isSending = false
        }
    }
    
    private func send(type: KBChatMessageType, text: String? = nil, replyToId: String?) {
        guard let modelContext else { return }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let senderName = senderDisplayName()
        let messageId = UUID().uuidString
        let now = Date()
        
        isSending = true
        
        let msg = KBChatMessage(
            id: messageId,
            familyId: familyId,
            senderId: uid,
            senderName: senderName,
            type: type,
            text: text,
            createdAt: now
        )
        msg.replyToId = replyToId
        msg.syncState = .pendingUpsert
        
        modelContext.insert(msg)
        try? modelContext.save()
        reloadLocal()
        
        Task {
            let dto = makeDTO(from: msg)
            do {
                try await remoteStore.upsert(dto: dto)
                msg.syncState = .synced
                msg.lastSyncError = nil
                try? modelContext.save()
            } catch {
                msg.syncState = .error
                msg.lastSyncError = error.localizedDescription
                try? modelContext.save()
                errorText = "Invio fallito: \(error.localizedDescription)"
            }
            isSending = false
        }
    }
    
    // MARK: - ─── REAZIONI ────────────────────────────────────────────────────
    
    func toggleReaction(_ emoji: String, on message: KBChatMessage) {
        guard let modelContext else { return }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        var reactions = message.reactions
        
        if reactions[emoji]?.contains(uid) == true {
            reactions[emoji]?.removeAll { $0 == uid }
            if reactions[emoji]?.isEmpty == true { reactions.removeValue(forKey: emoji) }
        } else {
            reactions[emoji, default: []].append(uid)
        }
        
        message.reactions = reactions
        message.syncState = .pendingUpsert
        message.lastSyncError = nil
        try? modelContext.save()
        
        Task {
            do {
                try await remoteStore.updateReactions(
                    familyId: familyId,
                    messageId: message.id,
                    reactionsJSON: message.reactionsJSON
                )
                message.syncState = .synced
                try? modelContext.save()
            } catch {
                message.syncState = .error
                message.lastSyncError = error.localizedDescription
                try? modelContext.save()
            }
        }
    }
    
    // MARK: - ─── CLEAR / DELETE ──────────────────────────────────────────────
    
    func clearChat() {
        guard let modelContext else { return }
        let snapshot = messages
        
        Task {
            await withTaskGroup(of: Void.self) { group in
                for msg in snapshot {
                    group.addTask {
                        if let path = msg.mediaStoragePath {
                            try? await self.storageService.delete(storagePath: path)
                        }
                        try? await self.remoteStore.softDelete(
                            familyId: self.familyId,
                            messageId: msg.id
                        )
                    }
                }
            }
            
            await MainActor.run {
                for msg in snapshot { modelContext.delete(msg) }
                try? modelContext.save()
                reloadLocal()
            }
        }
    }
    
    func deleteMessage(_ message: KBChatMessage) {
        guard let modelContext else { return }
        
        Task {
            do {
                if let path = message.mediaStoragePath {
                    try? await storageService.delete(storagePath: path)
                }
                try await remoteStore.softDelete(familyId: familyId, messageId: message.id)
                modelContext.delete(message)
                try? modelContext.save()
                reloadLocal()
            } catch {
                errorText = "Eliminazione fallita: \(error.localizedDescription)"
            }
        }
    }
    
    @MainActor
    func deleteMessagesLocally(ids: [String]) {
        guard let modelContext, !ids.isEmpty else { return }
        
        let uid = Auth.auth().currentUser?.uid ?? ""
        guard !uid.isEmpty else { return }
        
        for id in ids {
            let mid = id
            let desc = FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.id == mid })
            if let msg = try? modelContext.fetch(desc).first {
                msg.isDeleted = true
                msg.syncState = .synced
                msg.lastSyncError = nil
            }
        }
        
        saveContext(modelContext, reason: "deleteMessagesLocally-optimistic")
        reloadLocal()
        
        Task {
            await withTaskGroup(of: Void.self) { group in
                for messageId in ids {
                    group.addTask {
                        try? await self.remoteStore.addToDeletedFor(
                            familyId: self.familyId,
                            messageId: messageId,
                            uid: uid
                        )
                    }
                }
            }
        }
    }
    
    func deleteMessagesRemotely(ids: [String]) {
        guard let modelContext, !ids.isEmpty else { return }
        
        let uid = Auth.auth().currentUser?.uid ?? ""
        let now = Date()
        
        let selected = messages.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        
        guard selected.allSatisfy({ $0.senderId == uid }) else {
            errorText = "Puoi eliminare per tutti solo messaggi inviati da te."
            return
        }
        
        guard selected.allSatisfy({ now.timeIntervalSince($0.createdAt) <= 300 }) else {
            errorText = "Puoi eliminare per tutti solo entro 5 minuti dall'invio."
            return
        }
        
        Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for msg in selected {
                        group.addTask {
                            if let path = msg.mediaStoragePath {
                                try? await self.storageService.delete(storagePath: path)
                            }
                            try await self.remoteStore.softDelete(
                                familyId: self.familyId,
                                messageId: msg.id
                            )
                        }
                    }
                    try await group.waitForAll()
                }
                
                await MainActor.run {
                    for msg in selected {
                        msg.isDeleted = true
                        msg.syncState = .synced
                        msg.lastSyncError = nil
                    }
                    try? modelContext.save()
                    self.reloadLocal()
                }
            } catch {
                await MainActor.run {
                    self.errorText = "Eliminazione per tutti fallita: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - ─── READ RECEIPTS ───────────────────────────────────────────────
    
    func markVisibleMessagesAsRead() {
        let uid = Auth.auth().currentUser?.uid ?? ""
        guard !uid.isEmpty else { return }
        
        let unread = messages.filter {
            $0.senderId != uid &&
            !$0.readBy.contains(uid) &&
            $0.syncState == .synced
        }
        guard !unread.isEmpty else { return }
        
        let ids = unread.map(\.id)
        guard let modelContext else { return }
        
        for msg in unread {
            var rb = msg.readBy
            rb.append(uid)
            msg.readBy = rb
        }
        try? modelContext.save()
        
        // IMPORTANT: niente reloadLocal qui (è una delle cause di stutter)
        Task {
            try? await remoteStore.markAsRead(
                familyId: familyId,
                messageIds: ids,
                uid: uid
            )
        }
    }
    
    // MARK: - ─── SEND LOCATION ───────────────────────────────────────────────
    
    func sendLocation(latitude: Double, longitude: Double) {
        guard let modelContext,
              !familyId.isEmpty,
              let uid = Auth.auth().currentUser?.uid else { return }
        
        let senderName = senderDisplayName()
        let messageId = UUID().uuidString
        let now = Date()
        
        isSending = true
        
        let msg = KBChatMessage(
            id: messageId,
            familyId: familyId,
            senderId: uid,
            senderName: senderName,
            type: .location,
            text: nil,
            createdAt: now
        )
        
        msg.latitude = latitude
        msg.longitude = longitude
        msg.syncState = .pendingUpsert
        
        modelContext.insert(msg)
        try? modelContext.save()
        reloadLocal()
        
        Task {
            let dto = makeDTO(from: msg)
            do {
                try await remoteStore.upsert(dto: dto)
                await MainActor.run {
                    msg.syncState = .synced
                    msg.lastSyncError = nil
                    try? modelContext.save()
                    self.isSending = false
                }
            } catch {
                await MainActor.run {
                    msg.syncState = .error
                    msg.lastSyncError = error.localizedDescription
                    try? modelContext.save()
                    self.errorText = "Invio posizione fallito: \(error.localizedDescription)"
                    self.isSending = false
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func senderDisplayName() -> String {
        guard let modelContext else { return "Utente" }
        
        let uid = Auth.auth().currentUser?.uid ?? ""
        guard !uid.isEmpty else { return "Utente" }
        
        let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
        guard let profile = try? modelContext.fetch(desc).first else { return "Utente" }
        
        let first = (profile.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last  = (profile.lastName  ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        
        let stored = (profile.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        let chosen: String
        if !canonical.isEmpty {
            chosen = canonical
        } else if !stored.isEmpty {
            chosen = stored
        } else {
            chosen = "Utente"
        }
        
        if !canonical.isEmpty, canonical != stored {
            profile.displayName = canonical
            profile.updatedAt = Date()
            try? modelContext.save()
        }
        
        return chosen
    }
    
    private func makeDTO(from msg: KBChatMessage) -> RemoteChatMessageDTO {
        RemoteChatMessageDTO(
            id: msg.id,
            familyId: msg.familyId,
            senderId: msg.senderId,
            senderName: msg.senderName,
            typeRaw: msg.typeRaw,
            text: msg.text,
            mediaStoragePath: msg.mediaStoragePath,
            mediaURL: msg.mediaURL,
            mediaDurationSeconds: msg.mediaDurationSeconds,
            mediaThumbnailURL: msg.mediaThumbnailURL,
            replyToId: msg.replyToId,
            reactionsJSON: msg.reactionsJSON,
            readByJSON: nil,
            createdAt: msg.createdAt,
            editedAt: msg.editedAt,
            isDeleted: msg.isDeleted,
            deletedFor: [],
            latitude: msg.latitude,
            longitude: msg.longitude
        )
    }
}

// MARK: - ListenerRegistrationProtocol

protocol ListenerRegistrationProtocol {
    func remove()
}

final class FirestoreListenerWrapper: ListenerRegistrationProtocol {
    private let inner: ListenerRegistration
    init(_ inner: any ListenerRegistration) { self.inner = inner }
    func remove() { inner.remove() }
}

// MARK: - URL helpers

private extension URL {
    func mimeType() -> String {
        switch pathExtension.lowercased() {
        case "pdf":         return "application/pdf"
        case "doc":         return "application/msword"
        case "docx":        return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls":         return "application/vnd.ms-excel"
        case "xlsx":        return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt":         return "application/vnd.ms-powerpoint"
        case "pptx":        return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "txt":         return "text/plain"
        case "csv":         return "text/csv"
        case "zip":         return "application/zip"
        case "rar":         return "application/x-rar-compressed"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "mp3":         return "audio/mpeg"
        case "m4a":         return "audio/x-m4a"
        case "mp4":         return "video/mp4"
        case "mov":         return "video/quicktime"
        default:            return "application/octet-stream"
        }
    }
}
