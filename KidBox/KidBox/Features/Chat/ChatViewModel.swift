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
    @Published var uploadProgress: Double = 0
    @Published var errorText: String?
    
    // Audio recording
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    
    // Typing indicators
    @Published var typingUsers: [String] = []   // nomi degli altri che stanno scrivendo
    
    @Published var editingMessageId: String? = nil
    @Published var editingOriginalText: String = ""
    
    // Reply (WhatsApp-style)
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
    
    private let proximityRouter = ProximityAudioRouter()
    
    private let remoteStore = ChatRemoteStore()
    private let storageService = ChatStorageService()
    
    // Audio recorder
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingURL: URL?
    
    var isEditing: Bool { editingMessageId != nil }
    
    /// Restituisce `true` solo se NON sono ancora trascorsi 5 minuti dall'invio del messaggio.
    func canEditOrDelete(_ message: KBChatMessage) -> Bool {
        let elapsed = Date().timeIntervalSince(message.createdAt)
        return elapsed < 5 * 60
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
        
        listener = FirestoreListenerWrapper(remoteStore.listenMessages(
            familyId: familyId,
            limit: 100,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in self.applyRemoteChanges(changes) }
            },
            onError: { [weak self] error in
                guard let self else { return }
                Task { @MainActor in self.errorText = error.localizedDescription }
            }
        ))
        
        let uid = Auth.auth().currentUser?.uid ?? ""
        typingListener = FirestoreListenerWrapper(remoteStore.listenTyping(
            familyId: familyId,
            excludeUID: uid,
            onChange: { [weak self] names in
                guard let self else { return }
                Task { @MainActor in self.typingUsers = names }
            }
        ))
        
        reloadLocal()
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
        typingListener?.remove()
        typingListener = nil
        isObserving = false
        // Assicura che il nostro indicatore venga rimosso
        Task { try? await remoteStore.setTyping(false, familyId: familyId) }
        KBLog.sync.kbInfo("ChatVM stopListening familyId=\(familyId)")
    }
    
    // MARK: - Local fetch
    
    @MainActor
    func reloadLocal() {
        guard let modelContext else { return }
        
        KBLog.data.kbInfo("reloadLocal: start familyId=\(familyId)")
        logDBStats(reason: "before reloadLocal")
        
        let fam = familyId
        let desc = FetchDescriptor<KBChatMessage>(
            predicate: #Predicate { $0.familyId == fam && $0.isDeleted == false },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        
        do {
            let rows = try modelContext.fetch(desc)
            self.messages = rows
            KBLog.data.kbInfo("reloadLocal: fetched visible messages count=\(rows.count)")
        } catch {
            KBLog.data.kbError("reloadLocal: fetch FAILED error=\(error.localizedDescription)")
        }
        
        logDBStats(reason: "after reloadLocal")
    }
    
    @MainActor
    private func saveContext(_ context: ModelContext, reason: String) {
        do {
            try context.save()
            KBLog.persistence.kbInfo("ChatVM save ok reason=\(reason)")
        } catch {
            KBLog.persistence.kbError("ChatVM save FAILED reason=\(reason) error=\(error.localizedDescription)")
            self.errorText = "Salvataggio locale fallito: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func logDBStats(reason: String) {
        guard let modelContext else { return }
        let fam = familyId
        let all = FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.familyId == fam })
        let del = FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.familyId == fam && $0.isDeleted == true })
        
        let total = (try? modelContext.fetchCount(all)) ?? -1
        let deleted = (try? modelContext.fetchCount(del)) ?? -1
        KBLog.data.kbInfo("ChatVM dbStats reason=\(reason) total=\(total) deleted=\(deleted)")
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
        KBLog.sync.kbInfo("applyUpsert: start id=\(mid) remoteDeleted=\(dto.isDeleted)")
        
        // Controlla se questo messaggio è stato eliminato "per me" lato server
        let myUID = Auth.auth().currentUser?.uid ?? ""
        let deletedForMe = !myUID.isEmpty && dto.deletedFor.contains(myUID)
        
        let desc = FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.id == mid })
        let existing = try? modelContext.fetch(desc).first
        
        if let existing {
            let localBefore = existing.isDeleted
            
            existing.senderName    = dto.senderName
            existing.text          = dto.text
            existing.mediaURL      = dto.mediaURL
            existing.reactionsJSON = dto.reactionsJSON
            
            let merged = Array(Set(existing.readBy + dto.readBy))
            existing.readBy = merged
            
            // ✅ merge tombstone: non resuscitare mai, rispetta deletedFor server-side
            existing.isDeleted = localBefore || dto.isDeleted || deletedForMe
            
            existing.syncState     = .synced
            existing.lastSyncError = nil
            existing.replyToId     = dto.replyToId
            
            KBLog.sync.kbInfo("applyUpsert: merge delete id=\(mid) localWas=\(localBefore) remote=\(dto.isDeleted) deletedForMe=\(deletedForMe) final=\(existing.isDeleted)")
        } else {
            KBLog.sync.kbInfo("applyUpsert: no existing id=\(mid) remoteDeleted=\(dto.isDeleted) deletedForMe=\(deletedForMe)")
            
            // Se eliminato per tutti o per me, non inserire
            guard !dto.isDeleted && !deletedForMe else {
                KBLog.sync.kbInfo("applyUpsert: skipping insert id=\(mid) isDeleted=\(dto.isDeleted) deletedForMe=\(deletedForMe)")
                return
            }
            
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
                isDeleted: false
            )
            msg.replyToId      = dto.replyToId
            msg.reactionsJSON  = dto.reactionsJSON
            msg.readByJSON     = dto.readByJSON
            msg.syncState      = .synced
            msg.lastSyncError  = nil
            
            modelContext.insert(msg)
            KBLog.sync.kbInfo("applyUpsert: inserted id=\(mid)")
        }
    }
    
    // MARK: - ─── SEND TEXT ────────────────────────────────────────────────────
    
    func sendText() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isSending else { return }
        
        // 1) Se sto editando -> salvo modifica (NON invio nuovo)
        if isEditing {
            commitEditing()
            return
        }
        
        // 2) Altrimenti invio nuovo messaggio (con reply opzionale)
        let replyId = replyingToMessageId   // String?
        inputText = ""
        
        if replyId != nil {
            send(type: .text, text: trimmed, replyToId: replyId)
            cancelReply()
        } else {
            send(type: .text, text: trimmed)
        }
    }
    
    func startEditing(_ message: KBChatMessage) {
        guard message.senderId == Auth.auth().currentUser?.uid else { return }
        guard message.type == .text else { return }
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
        guard let modelContext else { return }
        guard let messageId = editingMessageId else { return }
        
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed != editingOriginalText else { cancelEditing(); return }
        guard !isSending else { return }
        
        stopTyping()
        isSending = true
        errorText = nil
        
        // 1) update locale immediato (UI reattiva)
        if let msg = messages.first(where: { $0.id == messageId }) {
            msg.text = trimmed
            msg.syncState = .pendingUpsert
            msg.lastSyncError = nil
            try? modelContext.save()
            reloadLocal()
        }
        
        // 2) update remoto
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
                        self.reloadLocal()
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
                        self.reloadLocal()
                    }
                    self.isSending = false
                    // NON annullo editing: così può riprovare a salvare
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
            replyingPreviewText = "" // lo mostriamo come thumbnail nella bar
        case .video:
            replyingPreviewText = "🎬 Video"
        case .audio:
            let d = message.mediaDurationSeconds ?? 0
            replyingPreviewText = d > 0 ? "Messaggio vocale • \(formatDuration(d))" : "Messaggio vocale"
        case .document:
            replyingPreviewText = "📄 \(message.text ?? "Documento")"
        }
    }
    
    func cancelReply() {
        replyingToMessageId = nil
        replyingPreviewName = ""
        replyingPreviewText = ""
        
        replyingPreviewKind = nil
        replyingPreviewMediaURL = nil
        replyingPreviewAudioDuration = nil
    }
    
    private func formatDuration(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }
    
    // MARK: - ─── TYPING INDICATOR ────────────────────────────────────────────
    
    /// Chiamato dal ChatInputBar ogni volta che il testo cambia.
    /// Usa un debounce di 3s: se l'utente smette di scrivere, rimuove l'indicatore.
    func userIsTyping() {
        typingDebounceTask?.cancel()
        Task { try? await remoteStore.setTyping(true, familyId: familyId) }
        typingDebounceTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { stopTyping() }
        }
    }
    
    func stopTyping() {
        typingDebounceTask?.cancel()
        typingDebounceTask = nil
        Task { try? await remoteStore.setTyping(false, familyId: familyId) }
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
    
    // MARK: - ─── SEND DOCUMENT ───────────────────────────────────────────────
    
    /// Invia un documento scelto dal DocumentPicker.
    /// Usa `asCopy: true` nel picker, quindi l'URL è già accessibile nel sandbox.
    func sendDocument(url: URL) {
        Task { await uploadAndSendDocument(url: url) }
    }
    
    private func uploadAndSendDocument(url: URL) async {
        guard let modelContext else { return }
        
        let uid        = Auth.auth().currentUser?.uid ?? "local"
        let senderName = senderDisplayName()
        let messageId  = UUID().uuidString
        let now        = Date()
        let fileName   = url.lastPathComponent
        let mimeType   = url.mimeType()
        
        isUploadingMedia = true
        uploadProgress   = 0
        errorText        = nil
        
        // 1) Crea messaggio locale placeholder
        let msg = KBChatMessage(
            id:        messageId,
            familyId:  familyId,
            senderId:  uid,
            senderName: senderName,
            type:      .document,
            text:      fileName,      // usiamo text per conservare il nome file
            createdAt: now
        )
        msg.syncState = .pendingUpsert
        modelContext.insert(msg)
        try? modelContext.save()
        reloadLocal()
        
        do {
            // 2) Leggi i byte
            let data = try Data(contentsOf: url)
            
            // 3) Upload su Storage
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
            
            // 4) Aggiorna locale con URL
            msg.mediaStoragePath = storagePath
            msg.mediaURL         = downloadURL
            msg.syncState        = .pendingUpsert
            try? modelContext.save()
            
            // 5) Scrivi su Firestore
            let dto = makeDTO(from: msg)
            try await remoteStore.upsert(dto: dto)
            
            msg.syncState     = .synced
            msg.lastSyncError = nil
            try? modelContext.save()
            
            KBLog.data.info("ChatVM sendDocument OK msgId=\(messageId) file=\(fileName)")
            
        } catch {
            msg.syncState     = .error
            msg.lastSyncError = error.localizedDescription
            try? modelContext.save()
            errorText = "Invio documento fallito: \(error.localizedDescription)"
            KBLog.data.error("ChatVM sendDocument failed: \(error.localizedDescription)")
        }
        
        isUploadingMedia = false
        uploadProgress   = 0
        reloadLocal()
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
    
    /// Variante che include il riferimento al messaggio a cui si sta rispondendo.
    /// Non altera gli altri flussi: crea un nuovo messaggio come sempre, ma valorizza `replyToId`.
    private func send(type: KBChatMessageType, text: String? = nil, replyToId: String?) {
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
        msg.replyToId = replyToId
        msg.syncState = .pendingUpsert
        
        modelContext.insert(msg)
        try? modelContext.save()
        reloadLocal()
        
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
    
    // MARK: - Bulk delete (Selection mode)
    
    /// Elimina "per me": scrive `arrayUnion([myUID])` nel campo `deletedFor` su Firestore,
    /// poi marca il messaggio come `isDeleted = true` localmente.
    /// In questo modo la cancellazione sopravvive a disinstallazioni/reinstallazioni:
    /// al prossimo sync `applyUpsert` vede il proprio UID in `deletedFor` e non mostra il messaggio.
    @MainActor
    func deleteMessagesLocally(ids: [String]) {
        guard let modelContext else { return }
        guard !ids.isEmpty else { return }
        
        let uid = Auth.auth().currentUser?.uid ?? ""
        guard !uid.isEmpty else {
            KBLog.data.kbError("deleteMessagesLocally: no authenticated user, aborting")
            return
        }
        
        KBLog.data.kbInfo("deleteMessagesLocally: start count=\(ids.count) uid=\(uid)")
        
        // 1) Aggiorna subito la UI localmente (ottimistico)
        var found = 0
        var missing = 0
        for id in ids {
            let mid = id
            let desc = FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.id == mid })
            if let msg = try? modelContext.fetch(desc).first {
                found += 1
                msg.isDeleted = true
                msg.syncState = .synced
                msg.lastSyncError = nil
                KBLog.data.debug("deleteMessagesLocally: mark deleted locally id=\(mid)")
            } else {
                missing += 1
                KBLog.data.kbInfo("deleteMessagesLocally: not found locally id=\(mid)")
            }
        }
        saveContext(modelContext, reason: "deleteMessagesLocally-optimistic")
        reloadLocal()
        
        logDBStats(reason: "after deleteMessagesLocally found=\(found) missing=\(missing)")
        
        // 2) Persiste su Firestore: arrayUnion del proprio UID nel campo `deletedFor`
        //    Se Firestore non è raggiungibile, al prossimo avvio il listener ritornerà
        //    il documento senza il nostro UID in deletedFor, ma il record SwiftData
        //    rimarrà isDeleted=true grazie al save ottimistico sopra.
        //    La vera persistenza a prova di reinstallazione avviene quando la scrittura
        //    Firestore ha successo.
        Task {
            await withTaskGroup(of: Void.self) { group in
                for messageId in ids {
                    group.addTask {
                        do {
                            try await self.remoteStore.addToDeletedFor(
                                familyId: self.familyId,
                                messageId: messageId,
                                uid: uid
                            )
                            await KBLog.data.debug("deleteMessagesLocally: Firestore deletedFor ok id=\(messageId)")
                        } catch {
                            await KBLog.data.kbError("deleteMessagesLocally: Firestore deletedFor FAILED id=\(messageId) err=\(error.localizedDescription)")
                            // Non mostriamo errore all'utente: la UI è già aggiornata.
                            // Al prossimo avvio, se SwiftData è intatto, isDeleted rimane true.
                            // Se l'app viene reinstallata e Firestore non ha ancora il flag,
                            // il messaggio potrebbe riapparire — accettabile come edge case.
                        }
                    }
                }
            }
        }
    }
    
    /// Elimina "per tutti": soft delete remoto (Firestore) + pulizia media su Storage + hide locale.
    func deleteMessagesRemotely(ids: [String]) {
        guard let modelContext else {
            KBLog.data.error("deleteMessagesRemotely: modelContext is nil")
            return
        }
        guard !ids.isEmpty else {
            KBLog.data.debug("deleteMessagesRemotely: empty ids → noop")
            return
        }
        
        let uid = Auth.auth().currentUser?.uid ?? ""
        let now = Date()
        
        // Snapshot dei messaggi selezionati (dalla lista UI corrente)
        let selected = messages.filter { ids.contains($0.id) }
        guard !selected.isEmpty else {
            KBLog.data.warning("deleteMessagesRemotely: no selected messages in memory for ids count=\(ids.count, privacy: .public)")
            return
        }
        
        KBLog.data.info("deleteMessagesRemotely: start selected=\(selected.count, privacy: .public)")
        
        // Check difensivo: solo miei + entro 5 minuti
        guard selected.allSatisfy({ $0.senderId == uid }) else {
            KBLog.data.warning("deleteMessagesRemotely: blocked (contains non-owned messages) uid=\(uid, privacy: .private)")
            errorText = "Puoi eliminare per tutti solo messaggi inviati da te."
            return
        }
        
        guard selected.allSatisfy({ now.timeIntervalSince($0.createdAt) <= 300 }) else {
            KBLog.data.warning("deleteMessagesRemotely: blocked (older than 5 min)")
            errorText = "Puoi eliminare per tutti solo entro 5 minuti dall'invio."
            return
        }
        
        Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for msg in selected {
                        group.addTask {
                            // 1) Storage cleanup (best-effort)
                            if let path = msg.mediaStoragePath {
                                await KBLog.data.debug("deleteMessagesRemotely: storage delete start path=\(path, privacy: .private)")
                                do {
                                    try await self.storageService.delete(storagePath: path)
                                    await KBLog.data.debug("deleteMessagesRemotely: storage delete ok path=\(path, privacy: .private)")
                                } catch {
                                    await KBLog.data.warning("deleteMessagesRemotely: storage delete failed path=\(path, privacy: .private) err=\(error.localizedDescription, privacy: .public)")
                                }
                            }
                            
                            // 2) Soft delete remoto
                            await KBLog.data.debug("deleteMessagesRemotely: softDelete start id=\(msg.id, privacy: .private)")
                            try await self.remoteStore.softDelete(
                                familyId: self.familyId,
                                messageId: msg.id
                            )
                            await KBLog.data.debug("deleteMessagesRemotely: softDelete ok id=\(msg.id, privacy: .private)")
                        }
                    }
                    try await group.waitForAll()
                }
                
                await MainActor.run {
                    // Hide locale (tombstone locale)
                    for msg in selected {
                        msg.isDeleted = true
                        msg.syncState = .synced
                        msg.lastSyncError = nil
                    }
                    
                    do {
                        try modelContext.save()
                        KBLog.data.info("deleteMessagesRemotely: local save ok count=\(selected.count, privacy: .public)")
                    } catch {
                        KBLog.data.error("deleteMessagesRemotely: local save failed err=\(error.localizedDescription, privacy: .public)")
                    }
                    
                    self.reloadLocal()
                }
                
            } catch {
                await MainActor.run {
                    KBLog.data.error("deleteMessagesRemotely: remote softDelete failed err=\(error.localizedDescription, privacy: .public)")
                    self.errorText = "Eliminazione per tutti fallita: \(error.localizedDescription)"
                }
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
            replyToId:            msg.replyToId,
            reactionsJSON:        msg.reactionsJSON,
            readByJSON:           nil,   // readBy è gestito solo da markAsRead
            createdAt:            msg.createdAt,
            isDeleted:            msg.isDeleted,
            deletedFor:           []     // gestito solo da addToDeletedFor
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
final class FirestoreListenerWrapper: ListenerRegistrationProtocol {
    private let inner:  ListenerRegistration
    init(_ inner: any ListenerRegistration) { self.inner = inner }
    func remove() { inner.remove() }
}

// MARK: - URL helpers

private extension URL {
    /// Restituisce un MIME type ragionevole basato sull'estensione del file.
    func mimeType() -> String {
        let ext = self.pathExtension.lowercased()
        switch ext {
        case "pdf":             return "application/pdf"
        case "doc":             return "application/msword"
        case "docx":            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls":             return "application/vnd.ms-excel"
        case "xlsx":            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt":             return "application/vnd.ms-powerpoint"
        case "pptx":            return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "txt":             return "text/plain"
        case "csv":             return "text/csv"
        case "zip":             return "application/zip"
        case "rar":             return "application/x-rar-compressed"
        case "png":             return "image/png"
        case "jpg", "jpeg":     return "image/jpeg"
        case "gif":             return "image/gif"
        case "mp3":             return "audio/mpeg"
        case "m4a":             return "audio/x-m4a"
        case "mp4":             return "video/mp4"
        case "mov":             return "video/quicktime"
        default:                return "application/octet-stream"
        }
    }
}
