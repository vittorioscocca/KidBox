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
import AVFoundation
import OSLog

@MainActor
final class ChatViewModel: ObservableObject {
    
    // MARK: - Input
    let familyId: String
    
    // MARK: - Published state
    @Published var messages: [KBChatMessage] = []
    @Published var inputText: String = ""
    @Published var isSending: Bool = false
    @Published var isUploadingMedia: Bool = false
    @Published var uploadProgress: Double = 0
    @Published var errorText: String?
    
    // Audio recording
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    
    // MARK: - Private
    private var modelContext: ModelContext?
    private var listener: (any ListenerRegistrationProtocol)?
    private var cancellables = Set<AnyCancellable>()
    private var isObserving = false
    
    private let proximityRouter = ProximityAudioRouter()
    
    private let remoteStore = ChatRemoteStore()
    private let storageService = ChatStorageService()
    
    // Audio recorder
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingURL: URL?
    
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
        
        listener = FirestoreListenerWrapper(remoteStore.listenMessages(
            familyId: familyId,
            limit: 100,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyRemoteChanges(changes)
                }
            },
            onError: { [weak self] error in
                guard let self else { return }
                Task { @MainActor in
                    self.errorText = error.localizedDescription
                }
            }
        ))
        
        // Carica i messaggi già salvati localmente
        reloadLocal()
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
        isObserving = false
        KBLog.sync.kbInfo("ChatVM stopListening familyId=\(familyId)")
    }
    
    // MARK: - Local fetch
    
    func reloadLocal() {
        guard let modelContext else { return }
        let fid = familyId
        let desc = FetchDescriptor<KBChatMessage>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        messages = (try? modelContext.fetch(desc)) ?? []
        KBLog.data.debug("ChatVM reloadLocal count=\(self.messages.count)")
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
        reloadLocal()
    }
    
    private func applyUpsert(dto: RemoteChatMessageDTO, modelContext: ModelContext) {
        let mid = dto.id
        let desc = FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.id == mid })
        let existing = try? modelContext.fetch(desc).first
        
        if let existing {
            existing.senderName    = dto.senderName
            existing.text          = dto.text
            existing.mediaURL      = dto.mediaURL
            existing.reactionsJSON = dto.reactionsJSON
            // ✅ Per readBy: merge locale + remoto per evitare race condition ottimistica.
            // Se localmente ho già segnato come letto, non perdo quella info.
            let remoteReadBy = dto.readBy
            let localReadBy  = existing.readBy
            let merged = Array(Set(localReadBy + remoteReadBy))
            existing.readBy        = merged
            existing.isDeleted     = dto.isDeleted
            existing.syncState     = .synced
            existing.lastSyncError = nil
        } else {
            guard !dto.isDeleted else { return }
            
            let msg = KBChatMessage(
                id:                   dto.id,
                familyId:             dto.familyId,
                senderId:             dto.senderId,
                senderName:           dto.senderName,
                type:                 KBChatMessageType(rawValue: dto.typeRaw) ?? .text,
                text:                 dto.text,
                mediaStoragePath:     dto.mediaStoragePath,
                mediaURL:             dto.mediaURL,
                mediaDurationSeconds: dto.mediaDurationSeconds,
                mediaThumbnailURL:    dto.mediaThumbnailURL,
                createdAt:            dto.createdAt ?? Date(),
                isDeleted:            false
            )
            msg.reactionsJSON = dto.reactionsJSON
            msg.readByJSON    = dto.readByJSON        // ✅
            msg.syncState     = .synced
            msg.lastSyncError = nil
            modelContext.insert(msg)
        }
    }
    
    // MARK: - ─── SEND TEXT ────────────────────────────────────────────────────
    
    func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        
        inputText = ""
        send(type: .text, text: text)
    }
    
    // MARK: - ─── SEND PHOTO / VIDEO ──────────────────────────────────────────
    
    /// Chiamato dopo che l'utente ha scelto una foto/video dalla libreria o fotocamera.
    func sendMedia(data: Data, type: KBChatMessageType) {
        guard !isUploadingMedia else { return }
        Task { await uploadAndSend(data: data, type: type) }
    }
    
    private func uploadAndSend(data: Data, type: KBChatMessageType) async {
        guard let modelContext else { return }
        
        let uid        = Auth.auth().currentUser?.uid ?? "local"
        let senderName = senderDisplayName()
        let messageId  = UUID().uuidString
        let now        = Date()
        
        let (fileName, mimeType) = ChatStorageService.fileInfo(for: type)
        
        isUploadingMedia = true
        uploadProgress   = 0
        errorText        = nil
        
        // 1) Crea messaggio locale in stato pendingUpsert
        let msg = KBChatMessage(
            id:        messageId,
            familyId:  familyId,
            senderId:  uid,
            senderName: senderName,
            type:      type,
            createdAt: now
        )
        msg.syncState = .pendingUpsert
        modelContext.insert(msg)
        try? modelContext.save()
        reloadLocal()
        
        do {
            // 2) Upload su Storage
            let (storagePath, downloadURL) = try await storageService.upload(
                data:        data,
                familyId:    familyId,
                messageId:   messageId,
                fileName:    fileName,
                mimeType:    mimeType,
                progressHandler: { [weak self] p in
                    Task { @MainActor in self?.uploadProgress = p }
                }
            )
            
            // 3) Aggiorna locale con URL
            msg.mediaStoragePath = storagePath
            msg.mediaURL         = downloadURL
            msg.syncState        = .pendingUpsert
            try? modelContext.save()
            
            // 4) Scrivi su Firestore
            let dto = makeDTO(from: msg)
            try await remoteStore.upsert(dto: dto)
            
            msg.syncState     = .synced
            msg.lastSyncError = nil
            try? modelContext.save()
            
            KBLog.data.info("ChatVM sendMedia OK msgId=\(messageId)")
            
        } catch {
            msg.syncState     = .error
            msg.lastSyncError = error.localizedDescription
            try? modelContext.save()
            errorText = "Invio media fallito: \(error.localizedDescription)"
            KBLog.data.error("ChatVM sendMedia failed: \(error.localizedDescription)")
        }
        
        isUploadingMedia = false
        uploadProgress   = 0
        reloadLocal()
    }
    
    // MARK: - ─── SEND AUDIO ───────────────────────────────────────────────────
    
    /// Avvia la registrazione audio (hold-to-record).
    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        guard (try? session.setCategory(.playAndRecord, mode: .default)) != nil else { return }
        guard (try? session.setActive(true)) != nil else { return }
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat_audio_\(UUID().uuidString).m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey:         Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey:       44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return }
        recorder.record()
        
        audioRecorder  = recorder
        recordingURL   = url
        isRecording    = true
        recordingDuration = 0
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.recordingDuration = self.audioRecorder?.currentTime ?? 0
            }
        }
        
        KBLog.data.info("ChatVM recording started")
    }
    
    /// Ferma e invia il vocale (chiamato quando l'utente rilascia il tasto).
    func stopAndSendRecording() {
        guard isRecording, let recorder = audioRecorder, let url = recordingURL else { return }
        
        // Prendiamo la durata PRIMA di azzerare refs (Double, non Int)
        let seconds = recorder.currentTime
        
        recorder.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Reset stato UI subito (così la barra torna normale anche se upload fallisce)
        isRecording = false
        recordingDuration = 0
        
        audioRecorder = nil
        recordingURL = nil
        
        // Durata minima: evita invii accidentali, ma non blocca vocali brevi
        let minSeconds: TimeInterval = 0.4
        guard seconds >= minSeconds else {
            try? FileManager.default.removeItem(at: url)
            KBLog.data.info("ChatVM audio too short: \(seconds, format: .fixed(precision: 2))s (min=\(minSeconds, format: .fixed(precision: 2))s)")
            return
        }
        
        // Arrotonda a secondi interi (minimo 1)
        let durationSeconds = max(1, Int(seconds.rounded()))
        
        Task {
            do {
                let data = try Data(contentsOf: url)
                KBLog.data.info("ChatVM audio ready bytes=\(data.count) dur=\(durationSeconds)s")
                await uploadAndSendAudio(data: data, duration: durationSeconds)
            } catch {
                await MainActor.run {
                    self.errorText = "Audio non leggibile: \(error.localizedDescription)"
                }
                KBLog.data.error("ChatVM audio read failed: \(error.localizedDescription)")
            }
            
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    /// Annulla la registrazione senza inviare.
    func cancelRecording() {
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer    = nil
        isRecording       = false
        recordingDuration = 0
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL  = nil
        audioRecorder = nil
        KBLog.data.info("ChatVM recording cancelled")
    }
    
    private func uploadAndSendAudio(data: Data, duration: Int) async {
        guard let modelContext else { return }
        
        let uid        = Auth.auth().currentUser?.uid ?? "local"
        let senderName = senderDisplayName()
        let messageId  = UUID().uuidString
        let now        = Date()
        
        isUploadingMedia = true
        uploadProgress   = 0
        
        let msg = KBChatMessage(
            id:                   messageId,
            familyId:             familyId,
            senderId:             uid,
            senderName:           senderName,
            type:                 .audio,
            mediaDurationSeconds: duration,
            createdAt:            now
        )
        msg.syncState = .pendingUpsert
        modelContext.insert(msg)
        try? modelContext.save()
        reloadLocal()
        
        do {
            let (storagePath, downloadURL) = try await storageService.upload(
                data:      data,
                familyId:  familyId,
                messageId: messageId,
                fileName:  "audio.m4a",
                mimeType:  "audio/x-m4a",
                progressHandler: { [weak self] p in
                    Task { @MainActor in self?.uploadProgress = p }
                }
            )
            
            msg.mediaStoragePath     = storagePath
            msg.mediaURL             = downloadURL
            msg.mediaDurationSeconds = duration
            msg.syncState            = .pendingUpsert
            try? modelContext.save()
            
            let dto = makeDTO(from: msg)
            try await remoteStore.upsert(dto: dto)
            
            msg.syncState     = .synced
            msg.lastSyncError = nil
            try? modelContext.save()
            
            KBLog.data.info("ChatVM sendAudio OK msgId=\(messageId)")
            
        } catch {
            msg.syncState     = .error
            msg.lastSyncError = error.localizedDescription
            try? modelContext.save()
            errorText = "Invio audio fallito: \(error.localizedDescription)"
        }
        
        isUploadingMedia = false
        uploadProgress   = 0
        reloadLocal()
    }
    
    // MARK: - ─── SEND (core) ─────────────────────────────────────────────────
    
    private func send(type: KBChatMessageType, text: String? = nil) {
        guard let modelContext else { return }
        
        let uid        = Auth.auth().currentUser?.uid ?? "local"
        let senderName = senderDisplayName()
        let messageId  = UUID().uuidString
        let now        = Date()
        
        isSending = true
        
        let msg = KBChatMessage(
            id:        messageId,
            familyId:  familyId,
            senderId:  uid,
            senderName: senderName,
            type:      type,
            text:      text,
            createdAt: now
        )
        msg.syncState = .pendingUpsert
        
        modelContext.insert(msg)
        try? modelContext.save()
        reloadLocal()
        
        // Firestore immediato
        Task {
            let dto = makeDTO(from: msg)
            do {
                try await remoteStore.upsert(dto: dto)
                msg.syncState     = .synced
                msg.lastSyncError = nil
                try? modelContext.save()
                KBLog.data.info("ChatVM send OK msgId=\(messageId)")
            } catch {
                msg.syncState     = .error
                msg.lastSyncError = error.localizedDescription
                try? modelContext.save()
                errorText = "Invio fallito: \(error.localizedDescription)"
            }
            isSending = false
            reloadLocal()
        }
    }
    
    // MARK: - ─── REAZIONI ────────────────────────────────────────────────────
    
    /// Aggiunge o rimuove una reazione emoji da un messaggio.
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
        
        message.reactions     = reactions
        message.syncState     = .pendingUpsert
        message.lastSyncError = nil
        try? modelContext.save()
        reloadLocal()
        
        // Firestore immediato
        Task {
            do {
                try await remoteStore.updateReactions(
                    familyId:      familyId,
                    messageId:     message.id,
                    reactionsJSON: message.reactionsJSON
                )
                message.syncState = .synced
                try? modelContext.save()
            } catch {
                message.syncState     = .error
                message.lastSyncError = error.localizedDescription
                try? modelContext.save()
            }
        }
    }
    
    // MARK: - ─── CLEAR CHAT ──────────────────────────────────────────────────
    
    /// Elimina TUTTI i messaggi della famiglia — media su Storage + soft delete su Firestore + locale.
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
                KBLog.data.info("ChatVM clearChat done — \(snapshot.count) msgs")
            }
        }
    }
    
    // MARK: - ─── DELETE ───────────────────────────────────────────────────────
    
    /// Elimina un messaggio (soft delete su Firestore + rimozione locale).
    func deleteMessage(_ message: KBChatMessage) {
        guard let modelContext else { return }
        
        Task {
            do {
                // Elimina media dallo Storage se presente
                if let path = message.mediaStoragePath {
                    try? await storageService.delete(storagePath: path)
                }
                // Soft delete su Firestore
                try await remoteStore.softDelete(familyId: familyId, messageId: message.id)
                // Rimozione locale
                modelContext.delete(message)
                try? modelContext.save()
                reloadLocal()
                KBLog.data.info("ChatVM deleteMessage OK msgId=\(message.id)")
            } catch {
                errorText = "Eliminazione fallita: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - ─── READ RECEIPTS ───────────────────────────────────────────────
    
    /// Chiamato da ChatView quando i messaggi diventano visibili.
    /// Segna come letti tutti i messaggi degli altri che l'utente non ha ancora letto.
    func markVisibleMessagesAsRead() {
        let uid = Auth.auth().currentUser?.uid ?? ""
        guard !uid.isEmpty else { return }
        
        // Solo i messaggi di altri, non ancora letti da me, già sincronizzati
        let unread = messages.filter { msg in
            msg.senderId != uid &&
            !msg.readBy.contains(uid) &&
            msg.syncState == .synced
        }
        guard !unread.isEmpty else { return }
        
        let ids = unread.map(\.id)
        
        // Aggiorna localmente subito (UI reattiva)
        guard let modelContext else { return }
        for msg in unread {
            var rb = msg.readBy
            rb.append(uid)
            msg.readBy = rb
        }
        try? modelContext.save()
        reloadLocal()
        
        // Poi su Firestore in background
        Task {
            try? await remoteStore.markAsRead(familyId: familyId, messageIds: ids, uid: uid)
        }
    }
    
    // MARK: - Helpers
    
    private func senderDisplayName() -> String {
        guard let modelContext else { return "Utente" }
        let uid = Auth.auth().currentUser?.uid ?? ""
        let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
        return (try? modelContext.fetch(desc).first)?.displayName ?? "Utente"
    }
    
    private func makeDTO(from msg: KBChatMessage) -> RemoteChatMessageDTO {
        RemoteChatMessageDTO(
            id:                   msg.id,
            familyId:             msg.familyId,
            senderId:             msg.senderId,
            senderName:           msg.senderName,
            typeRaw:              msg.typeRaw,
            text:                 msg.text,
            mediaStoragePath:     msg.mediaStoragePath,
            mediaURL:             msg.mediaURL,
            mediaDurationSeconds: msg.mediaDurationSeconds,
            mediaThumbnailURL:    msg.mediaThumbnailURL,
            reactionsJSON:        msg.reactionsJSON,
            readByJSON:           nil,   // readBy è gestito solo da markAsRead
            createdAt:            msg.createdAt,
            isDeleted:            msg.isDeleted
        )
    }
}

// MARK: - ListenerRegistrationProtocol

/// Protocollo per rendere testabile il listener di Firestore.
protocol ListenerRegistrationProtocol {
    func remove()
}

/// Wrapper concreto che adatta ListenerRegistration al protocollo.
/// Non usiamo extension con inheritance perché ListenerRegistration
/// è una classe Firestore concreta di terze parti.
import FirebaseFirestore
final class FirestoreListenerWrapper: ListenerRegistrationProtocol {
    private let inner: any ListenerRegistration
    init(_ inner: any ListenerRegistration) { self.inner = inner }
    func remove() { inner.remove() }
}
