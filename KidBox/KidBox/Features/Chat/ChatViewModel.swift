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

// MARK: - String helper

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        self.isEmpty ? fallback : self
    }
}

// MARK: - ChatViewModel

@MainActor
final class ChatViewModel: NSObject, ObservableObject {
    
    // MARK: - Input
    let familyId: String
    
    // MARK: - Published state
    @Published var messages: [KBChatMessage] = []
    private let draftKey: String
    
    @Published var inputText: String {
        didSet {
            UserDefaults.standard.set(inputText, forKey: draftKey)
        }
    }
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
    @Published var isRecordingLocked: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var waveformSamples: [CGFloat] = []
    
    // Typing
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
    var isEditing:  Bool { editingMessageId != nil }
    
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
    
    // AVAudioEngine recording
    //
    // Pipeline completa su A15 / iOS 26 beta:
    //
    // 1. AVAudioEngine tap → buffer Float32 nativi dell'hardware
    // 2. Scrittura diretta in CAF/Float32 (AVAudioFile, nessuna conversione)
    // 3. Encoding AAC manuale tramite AVAudioConverter (legge il CAF,
    //    scrive frame AAC compressi in un secondo AVAudioFile M4A).
    //
    // Motivazione per l'encoding manuale:
    // - AVAssetExportSession su iOS 26 beta A15 produce M4A da ~1600 bytes
    //   con durata corretta ma audio silenzioso (bug nell'encoder AAC interno).
    // - AVAudioConverter opera a livello di codec puro, non usa la sessione
    //   audio e non è affetto dal bug di AVAssetExportSession.
    //
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    
    // debounce reloadLocal
    private var reloadTask: Task<Void, Never>?
    
    // MARK: - Init
    
    init(familyId: String) {
        self.draftKey = "chatDraft_\(familyId)"
        self.inputText = UserDefaults.standard.string(forKey: draftKey) ?? ""
        self.familyId = familyId
        super.init()
    }
    
    func bind(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func canEditOrDelete(_ message: KBChatMessage) -> Bool {
        Date().timeIntervalSince(message.createdAt) < 5 * 60
    }
    
    // MARK: - Start / Stop listening
    
    func startListening() {
        guard !isObserving else { return }
        isObserving = true
        KBLog.sync.kbInfo("ChatVM startListening familyId=\(familyId)")
        let uid  = Auth.auth().currentUser?.uid ?? ""
        let name = senderDisplayName()
        Task { await remoteStore.setTyping(false, familyId: familyId, uid: uid, displayName: name) }
        listener = FirestoreListenerWrapper(remoteStore.listenMessages(
            familyId: familyId, limit: 150,
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
            familyId: familyId, excludeUID: uid,
            onChange: { [weak self] names in
                guard let self else { return }
                Task { @MainActor in self.scheduleTypingUpdate(names) }
            }
        ))
        reloadLocal()
    }
    
    // MARK: - Send video from Share Extension (App Group path)
    
    /// Invia un video salvato nell'App Group dalla Share Extension.
    /// Usa il path locale invece di Data per evitare di caricare in RAM
    /// file che possono essere molto grandi (>500MB).
    func sendVideo(from url: URL) async {
        guard let modelContext else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            KBLog.data.kbError("ChatVM sendVideo: file not found path=\(url.path)")
            errorText = "File video non trovato."
            return
        }
        
        let uid        = Auth.auth().currentUser?.uid ?? "local"
        let senderName = senderDisplayName()
        let messageId  = UUID().uuidString
        let now        = Date()
        
        isUploadingMedia  = true
        isCompressingMedia = true
        uploadProgress    = 0
        errorText         = nil
        
        // Inserisci subito il messaggio placeholder in SwiftData
        let msg = KBChatMessage(
            id: messageId, familyId: familyId,
            senderId: uid, senderName: senderName,
            type: .video, createdAt: now
        )
        msg.syncState = .pendingUpsert
        modelContext.insert(msg)
        try? modelContext.save()
        reloadLocal()
        
        do {
            // Comprimi il video prima dell'upload
            let compressedURL = try await compressVideoURL(url)
            isCompressingMedia = false
            
            let compressedData = try Data(contentsOf: compressedURL)
            defer { try? FileManager.default.removeItem(at: compressedURL) }
            
            KBLog.data.kbInfo("ChatVM sendVideo upload START bytes=\(compressedData.count)")
            
            let (storagePath, downloadURL) = try await storageService.upload(
                data: compressedData,
                familyId: familyId,
                messageId: messageId,
                fileName: "video.mp4",
                mimeType: "video/mp4",
                progressHandler: { [weak self] p in
                    Task { @MainActor in self?.uploadProgress = p }
                }
            )
            
            msg.mediaStoragePath = storagePath
            msg.mediaURL         = downloadURL
            msg.syncState        = .pendingUpsert
            try? modelContext.save()
            
            let dto = makeDTO(from: msg)
            try await remoteStore.upsert(dto: dto)
            
            msg.syncState     = .synced
            msg.lastSyncError = nil
            try? modelContext.save()
            
            KBLog.data.kbInfo("ChatVM sendVideo OK messageId=\(messageId)")
            
            // Rimuovi il file originale dall'App Group
            try? FileManager.default.removeItem(at: url)
            
        } catch {
            isCompressingMedia = false
            msg.syncState        = .error
            msg.lastSyncError    = error.localizedDescription
            try? modelContext.save()
            errorText = "Invio video fallito: \(error.localizedDescription)"
            KBLog.data.kbError("ChatVM sendVideo ERROR=\(error.localizedDescription)")
        }
        
        isUploadingMedia = false
        uploadProgress   = 0
    }
    
    /// Comprime un video da un URL locale senza caricarlo interamente in RAM.
    private func compressVideoURL(_ sourceURL: URL) async throws -> URL {
        return  await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: sourceURL)
            guard let session = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetMediumQuality
            ) else {
                // Se non riusciamo a comprimere, usiamo l'originale
                return sourceURL
            }
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mp4")
            do {
                try await session.export(to: outputURL, as: .mp4, isolation: .none)
                return outputURL
            } catch {
                // Fallback: usa il file originale non compresso
                KBLog.data.kbError("compressVideoURL fallback to original: \(error.localizedDescription)")
                return sourceURL
            }
        }.value
    }
    
    private func scheduleTypingUpdate(_ names: [String]) {
        pendingTypingUsers = names
        guard typingThrottleTask == nil else { return }
        typingThrottleTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if let pending = pendingTypingUsers { typingUsers = pending; pendingTypingUsers = nil }
            typingThrottleTask = nil
        }
    }
    
    func stopListening() {
        listener?.remove();      listener      = nil
        typingListener?.remove(); typingListener = nil
        typingThrottleTask?.cancel(); typingThrottleTask = nil
        reloadTask?.cancel();    reloadTask    = nil
        stopEngineRecording()
        isObserving = false; oldestDocument = nil; hasMoreMessages = true
        let uid  = Auth.auth().currentUser?.uid ?? ""
        let name = senderDisplayName()
        Task { await remoteStore.setTyping(false, familyId: familyId, uid: uid, displayName: name) }
        KBLog.sync.kbInfo("ChatVM stopListening familyId=\(familyId)")
    }
    
    // MARK: - Paginazione
    
    func loadOlderMessages() {
        guard !isLoadingOlder, hasMoreMessages, let cursor = oldestDocument, let modelContext else { return }
        isLoadingOlder = true; isPaginating = true
        Task {
            do {
                let (dtos, newCursor) = try await remoteStore.fetchOlderMessages(
                    familyId: familyId, before: cursor, limit: 150)
                await MainActor.run {
                    if dtos.isEmpty {
                        self.hasMoreMessages = false
                    } else {
                        for dto in dtos { self.applyUpsert(dto: dto, modelContext: modelContext) }
                        try? modelContext.save()
                        self.oldestDocument = newCursor
                        if newCursor == nil { self.hasMoreMessages = false }
                        self.requestReloadLocal(debounceMs: 120, reason: "pagination")
                    }
                    self.isLoadingOlder = false; self.isPaginating = false
                }
            } catch {
                await MainActor.run {
                    self.errorText = "Errore caricamento messaggi: \(error.localizedDescription)"
                    self.isLoadingOlder = false; self.isPaginating = false
                }
            }
        }
    }
    
    // MARK: - Local fetch
    
    func requestReloadLocal(debounceMs: Int = 120, reason: String = "") {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(debounceMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.reloadLocal() }
        }
    }
    
    func reloadLocal() {
        guard let modelContext else { return }
        let fam  = familyId
        // Include messages deleted for everyone (tombstones) but exclude
        // messages deleted only for me (isDeleted = true, isDeletedForEveryone = false).
        let desc = FetchDescriptor<KBChatMessage>(
            predicate: #Predicate { $0.familyId == fam && ($0.isDeleted == false || $0.isDeletedForEveryone == true) },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        do {
            let rows    = try modelContext.fetch(desc)
            let newIds  = rows.map(\.id)
            let currIds = messages.map(\.id)
            if newIds == currIds { return }
            self.messages = rows
            KBLog.data.kbInfo("reloadLocal: fetched \(rows.count) messages familyId=\(familyId)")
        } catch {
            KBLog.data.kbError("reloadLocal: FAILED error=\(error.localizedDescription)")
        }
    }
    
    private func saveContext(_ context: ModelContext, reason: String) {
        do { try context.save() } catch {
            KBLog.persistence.kbError("ChatVM save FAILED reason=\(reason) error=\(error.localizedDescription)")
            self.errorText = "Salvataggio locale fallito: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Apply remote changes
    
    private func applyRemoteChanges(_ changes: [ChatRemoteChange]) {
        guard let modelContext else { return }
        for change in changes {
            switch change {
            case .upsert(let dto): applyUpsert(dto: dto, modelContext: modelContext)
            case .remove(let id):
                let mid  = id
                let desc = FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.id == mid })
                if let local = try? modelContext.fetch(desc).first { modelContext.delete(local) }
            }
        }
        try? modelContext.save()
        requestReloadLocal(debounceMs: 120, reason: "applyRemoteChanges")
    }
    
    private func applyUpsert(dto: RemoteChatMessageDTO, modelContext: ModelContext) {
        let mid          = dto.id
        let myUID        = Auth.auth().currentUser?.uid ?? ""
        let deletedForMe = !myUID.isEmpty && dto.deletedFor.contains(myUID)
        let desc = FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.id == mid })
        if let existing = try? modelContext.fetch(desc).first {
            let localBefore        = existing.isDeleted
            existing.senderName    = dto.senderName
            existing.text          = dto.text
            existing.editedAt      = dto.editedAt
            existing.mediaURL      = dto.mediaURL
            existing.reactionsJSON = dto.reactionsJSON
            existing.readBy        = Array(Set(existing.readBy + dto.readBy))
            // isDeletedForEveryone is signalled by dto.isDeleted (softDelete sets this on Firestore).
            // Once a message is a tombstone it stays a tombstone.
            if dto.isDeleted && !existing.isDeletedForEveryone {
                existing.isDeletedForEveryone = true
                existing.isDeleted = false   // keep in local store for tombstone display
            } else {
                existing.isDeleted = localBefore || deletedForMe
            }
            existing.syncState     = .synced; existing.lastSyncError = nil
            existing.replyToId     = dto.replyToId
            existing.latitude      = dto.latitude; existing.longitude = dto.longitude
            if existing.type == .audio, existing.senderId != myUID,
               existing.mediaURL != nil, existing.transcriptStatus == .none {
                startTranscriptIfNeeded(for: existing, modelContext: modelContext)
            }
        } else {
            guard !dto.isDeleted && !deletedForMe else { return }
            let msg = KBChatMessage(
                id: dto.id, familyId: dto.familyId,
                senderId: dto.senderId, senderName: dto.senderName,
                type: KBChatMessageType(rawValue: dto.typeRaw) ?? .text,
                text: dto.text, mediaStoragePath: dto.mediaStoragePath,
                mediaURL: dto.mediaURL, mediaDurationSeconds: dto.mediaDurationSeconds,
                mediaThumbnailURL: dto.mediaThumbnailURL,
                createdAt: dto.createdAt ?? Date(), editedAt: dto.editedAt, isDeleted: false
            )
            msg.replyToId = dto.replyToId; msg.reactionsJSON = dto.reactionsJSON
            msg.readByJSON = dto.readByJSON; msg.syncState = .synced; msg.lastSyncError = nil
            msg.latitude = dto.latitude; msg.longitude = dto.longitude
            modelContext.insert(msg)
            if msg.type == .audio, msg.senderId != myUID,
               msg.mediaURL != nil, msg.transcriptStatus == .none {
                startTranscriptIfNeeded(for: msg, modelContext: modelContext)
            }
        }
    }
    
    // MARK: - Send text
    
    func sendText() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        if isEditing { commitEditing(); return }
        let replyId = replyingToMessageId
        inputText = ""
        UserDefaults.standard.removeObject(forKey: draftKey) // ← pulisci il draft
        if replyId != nil { send(type: .text, text: trimmed, replyToId: replyId); cancelReply() }
        else { send(type: .text, text: trimmed) }
    }
    
    func startEditing(_ message: KBChatMessage) {
        guard message.senderId == Auth.auth().currentUser?.uid, message.type == .text else { return }
        guard canEditOrDelete(message) else {
            errorText = "Puoi modificare un messaggio solo entro 5 minuti dall'invio."; return
        }
        editingMessageId = message.id; editingOriginalText = message.text ?? ""; inputText = editingOriginalText
    }
    
    func cancelEditing() { editingMessageId = nil; editingOriginalText = ""; inputText = "" }
    
    func commitEditing() {
        guard let modelContext, let messageId = editingMessageId else { return }
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed != editingOriginalText else { cancelEditing(); return }
        guard !isSending else { return }
        stopTyping(); isSending = true; errorText = nil
        if let msg = messages.first(where: { $0.id == messageId }) {
            msg.text = trimmed; msg.editedAt = Date(); msg.syncState = .pendingUpsert; msg.lastSyncError = nil
            try? modelContext.save()
        }
        Task {
            do {
                try await remoteStore.updateMessageText(familyId: familyId, messageId: messageId, text: trimmed)
                await MainActor.run {
                    if let msg = self.messages.first(where: { $0.id == messageId }) {
                        msg.syncState = .synced; try? modelContext.save()
                    }
                    self.isSending = false; self.cancelEditing()
                }
            } catch {
                await MainActor.run {
                    if let msg = self.messages.first(where: { $0.id == messageId }) {
                        msg.syncState = .error; msg.lastSyncError = error.localizedDescription
                        try? modelContext.save()
                    }
                    self.isSending = false; self.errorText = error.localizedDescription
                }
            }
        }
    }
    
    func startReply(to message: KBChatMessage) {
        if isEditing { cancelEditing() }
        replyingToMessageId = message.id
        let name = message.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        replyingPreviewName = name.isEmpty ? "Utente" : name
        replyingPreviewKind = message.type; replyingPreviewMediaURL = message.mediaURL
        replyingPreviewAudioDuration = message.mediaDurationSeconds
        switch message.type {
        case .text:
            replyingPreviewText = (message.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("Messaggio")
        case .photo:    replyingPreviewText = ""
        case .video:    replyingPreviewText = "🎬 Video"
        case .audio:
            let d = message.mediaDurationSeconds ?? 0
            replyingPreviewText = d > 0 ? "Messaggio vocale • \(formatDuration(d))" : "Messaggio vocale"
        case .document: replyingPreviewText = "📄 \(message.text ?? "Documento")"
        case .location:
            replyingPreviewText = "📍 Posizione condivisa"
            replyingPreviewLatitude = message.latitude; replyingPreviewLongitude = message.longitude
        }
    }
    
    func cancelReply() {
        replyingToMessageId = nil; replyingPreviewName = ""; replyingPreviewText = ""
        replyingPreviewKind = nil; replyingPreviewMediaURL = nil; replyingPreviewAudioDuration = nil
        replyingPreviewLatitude = nil; replyingPreviewLongitude = nil
    }
    
    private func formatDuration(_ sec: Int) -> String { String(format: "%d:%02d", sec / 60, sec % 60) }
    
    // MARK: - Typing
    
    func userIsTyping() {
        typingDebounceTask?.cancel()
        let uid = Auth.auth().currentUser?.uid ?? ""; let name = senderDisplayName()
        Task { await remoteStore.setTyping(true, familyId: familyId, uid: uid, displayName: name) }
        typingDebounceTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { stopTyping() }
        }
    }
    
    func stopTyping() {
        typingDebounceTask?.cancel(); typingDebounceTask = nil
        let uid = Auth.auth().currentUser?.uid ?? ""; let name = senderDisplayName()
        Task { await remoteStore.setTyping(false, familyId: familyId, uid: uid, displayName: name) }
    }
    
    // MARK: - Send photo / video
    
    /// Resetta lo stato di upload bloccato (es. dopo un errore o da share extension).
    func resetUploadStateIfStuck() {
        guard isUploadingMedia else { return }
        isUploadingMedia = false
        isCompressingMedia = false
        uploadProgress = 0
        KBLog.data.kbInfo("ChatVM resetUploadStateIfStuck called")
    }
    
    func sendMedia(data: Data, type: KBChatMessageType) {
        guard !isUploadingMedia else { return }
        Task { await uploadAndSend(data: data, type: type) }
    }
    
    private func uploadAndSend(data: Data, type: KBChatMessageType) async {
        guard let modelContext else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let senderName = senderDisplayName()
        let messageId  = UUID().uuidString; let now = Date()
        let (fileName, mimeType) = ChatStorageService.fileInfo(for: type)
        errorText = nil
        let uploadData: Data
        do {
            switch type {
            case .photo:
                isCompressingMedia = true; uploadData = await compressPhoto(data: data); isCompressingMedia = false
            case .video:
                isCompressingMedia = true; uploadData = try await compressVideo(data: data); isCompressingMedia = false
            default: uploadData = data
            }
        } catch { isCompressingMedia = false; errorText = "Compressione fallita: \(error.localizedDescription)"; return }
        isUploadingMedia = true; uploadProgress = 0
        let msg = KBChatMessage(id: messageId, familyId: familyId, senderId: uid, senderName: senderName, type: type, createdAt: now)
        msg.syncState = .pendingUpsert; modelContext.insert(msg); try? modelContext.save(); reloadLocal()
        do {
            let (storagePath, downloadURL) = try await storageService.upload(
                data: uploadData, familyId: familyId, messageId: messageId, fileName: fileName, mimeType: mimeType,
                progressHandler: { [weak self] p in Task { @MainActor in self?.uploadProgress = p } })
            msg.mediaStoragePath = storagePath; msg.mediaURL = downloadURL
            msg.syncState = .pendingUpsert; try? modelContext.save(); reloadLocal()
            let dto = makeDTO(from: msg); try await remoteStore.upsert(dto: dto)
            msg.syncState = .synced; msg.lastSyncError = nil; try? modelContext.save()
        } catch {
            msg.syncState = .error; msg.lastSyncError = error.localizedDescription
            try? modelContext.save(); errorText = "Invio media fallito: \(error.localizedDescription)"
        }
        isUploadingMedia = false; uploadProgress = 0
    }
    
    // MARK: - Compression
    
    private func compressPhoto(data: Data) async -> Data {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let w = (props?[kCGImagePropertyPixelWidth]  as? CGFloat) ?? 0
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
            guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return data }
            return UIImage(cgImage: cgThumb).jpegData(compressionQuality: 0.75) ?? data
        }.value
    }
    
    private func compressVideo(data: Data) async throws -> Data {
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try data.write(to: inputURL); defer { try? FileManager.default.removeItem(at: inputURL) }
        let asset = AVURLAsset(url: inputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else { return data }
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        do { try await session.export(to: outputURL, as: .mp4, isolation: .none) } catch { return data }
        return (try? Data(contentsOf: outputURL)) ?? data
    }
    
    // MARK: - Send audio – AVAudioEngine recording
    
    func startRecording() {
        logAudio("startRecording BEGIN familyId=\(familyId)")
        describeAudioSession("beforeConfig")
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            logAudio("startRecording session configured OK")
        } catch {
            logAudio("startRecording session configure ERROR=\(error.localizedDescription)")
            errorText = "Impossibile configurare l'audio: \(error.localizedDescription)"; return
        }
        describeAudioSession("afterConfig")
        
        let recordingId = UUID().uuidString
        let url: URL
        do {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dir  = docs.appendingPathComponent("ChatAudio", isDirectory: true)
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            url = dir.appendingPathComponent("rec_\(recordingId).caf")
        } catch {
            logAudio("startRecording dir create ERROR=\(error.localizedDescription)")
            errorText = "Impossibile creare la cartella audio: \(error.localizedDescription)"; return
        }
        logAudio("startRecording recordingURL=\(url.path)")
        
        let engine    = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        logAudio("startRecording inputFormat=\(inputFormat)")
        
        // Scrivi nel formato nativo Float32 — nessuna conversione nel tap.
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: inputFormat.settings)
        } catch {
            logAudio("startRecording AVAudioFile create ERROR=\(error.localizedDescription)")
            errorText = "Impossibile creare il file audio: \(error.localizedDescription)"; return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            do { try audioFile.write(from: buffer) } catch {
                Task { @MainActor in self.logAudio("tapCallback write ERROR=\(error.localizedDescription)") }
            }
        }
        
        proximityRouter.isRecordingActive = true
        do {
            try engine.start()
            logAudio("startRecording engine.start() OK")
        } catch {
            logAudio("startRecording engine.start() ERROR=\(error.localizedDescription)")
            inputNode.removeTap(onBus: 0); proximityRouter.isRecordingActive = false
            errorText = "Impossibile avviare la registrazione: \(error.localizedDescription)"; return
        }
        
        self.audioEngine = engine; self.audioFile = audioFile
        self.recordingURL = url; self.recordingStartTime = Date()
        waveformSamples = []; isRecordingLocked = false; isRecording = true; recordingDuration = 0
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(timeInterval: 0.05, target: self,
                                              selector: #selector(handleRecordingTimerTick),
                                              userInfo: nil, repeats: true)
        logAudio("startRecording engine running OK")
    }
    
    @objc private func handleRecordingTimerTick() {
        guard isRecording, let start = recordingStartTime else { return }
        recordingDuration = Date().timeIntervalSince(start)
        waveformSamples.append(CGFloat.random(in: 0.05...0.9))
        if waveformSamples.count > 95 { waveformSamples.removeFirst() }
    }
    
    private func stopEngineRecording() {
        recordingTimer?.invalidate(); recordingTimer = nil
        isRecording = false; isRecordingLocked = false; recordingDuration = 0; recordingStartTime = nil
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0); engine.stop()
            logAudio("stopEngineRecording engine stopped")
        }
        audioEngine = nil; audioFile = nil   // chiude il file → flush
        proximityRouter.isRecordingActive = false
    }
    
    func stopAndSendRecording() {
        guard isRecording, let url = recordingURL, let start = recordingStartTime else {
            logAudio("stopAndSendRecording guard FAILED"); return
        }
        let seconds = Date().timeIntervalSince(start)
        logAudio("stopAndSendRecording BEGIN seconds=\(seconds)")
        logFileInfo(url, prefix: "beforeStop")
        stopEngineRecording();
        recordingURL = nil
        let rms = (try? checkCAFHasAudio(url)) ?? 0
        logAudio("CAF audio check RMS=\(rms) hasAudio=\(rms > 0.0001)")
        
        if seconds < 0.4 {
            try? FileManager.default.removeItem(at: url)
            logAudio("stopAndSendRecording discardedTooShort seconds=\(seconds)"); return
        }
        
        let durationSecs = max(1, Int(seconds.rounded()))
        Task { @MainActor in
            self.logFileInfo(url, prefix: "afterStop")
            await self.logAudioAssetInfo(url, prefix: "afterStop")
            
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard fileSize > 4096 else {
                try? FileManager.default.removeItem(at: url)
                self.logAudio("stopAndSendRecording ABORTED fileSize=\(fileSize)")
                self.errorText = "Registrazione non riuscita. Riprova."; return
            }
            
            do {
                // Encoding AAC manuale: bypassa AVAssetExportSession che su
                // iOS 26 beta A15 produce M4A silenzioso (~1600 bytes).
                let m4aURL = try await self.encodeCAFtoM4A(from: url)
                self.logAudio("stopAndSendRecording encode OK")
                self.logFileInfo(m4aURL, prefix: "afterEncode")
                await self.logAudioAssetInfo(m4aURL, prefix: "afterEncode")
                self.testLocalPlayback(m4aURL, prefix: "afterEncode")
                let data = try Data(contentsOf: m4aURL)
                self.logAudio("stopAndSendRecording data.count=\(data.count)")
                await self.uploadAndSendAudio(data: data, duration: durationSecs, sourceURL: m4aURL)
            } catch {
                self.logAudio("stopAndSendRecording encode ERROR=\(error.localizedDescription)")
                self.errorText = "Encoding audio fallito: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
    
    func cancelRecording() {
        let url = recordingURL; logAudio("cancelRecording BEGIN")
        stopEngineRecording(); recordingURL = nil
        if let url { try? FileManager.default.removeItem(at: url) }
        logAudio("cancelRecording done")
    }
    
    func lockRecording() { guard isRecording else { return }; isRecordingLocked = true }
    func finishLockedRecording() { guard isRecordingLocked else { return }; isRecordingLocked = false; stopAndSendRecording() }
    func cancelLockedRecording() { guard isRecordingLocked else { return }; isRecordingLocked = false; cancelRecording() }
    
    private func checkCAFHasAudio(_ url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: 4096) else { return 0 }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(buffer.frameLength))
        logAudio("CAF RMS check: frameLength=\(buffer.frameLength) rms=\(rms)")
        return rms
    }
    
    // MARK: - CAF/Float32 → M4A/AAC encoding via ExtAudioFile (Core Audio)
    //
    // AVAssetExportSession su iOS 26 beta A15 produce M4A silenzioso (~1600 bytes).
    // AVAudioConverter + AVAudioCompressedBuffer non è compatibile con AVAudioFile.write().
    // ExtAudioFile opera a livello Core Audio puro, bypassa la sessione audio completamente.
    
    private func encodeCAFtoM4A(from cafURL: URL) async throws -> URL {
        return try await Task.detached(priority: .userInitiated) {
            
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dir  = docs.appendingPathComponent("ChatAudio", isDirectory: true)
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let m4aURL = dir.appendingPathComponent("enc_\(UUID().uuidString).m4a")
            
            // --- Apri sorgente CAF ---
            var sourceRef: ExtAudioFileRef?
            var status = ExtAudioFileOpenURL(cafURL as CFURL, &sourceRef)
            guard status == noErr, let srcFile = sourceRef else {
                throw NSError(domain: "ChatVM", code: 50,
                              userInfo: [NSLocalizedDescriptionKey: "ExtAudioFile open source failed: \(status)"])
            }
            defer { ExtAudioFileDispose(srcFile) }
            
            // Leggi il formato client (PCM Float32) dalla sorgente
            var clientFormat = AudioStreamBasicDescription()
            var propSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            status = ExtAudioFileGetProperty(srcFile,
                                             kExtAudioFileProperty_FileDataFormat,
                                             &propSize, &clientFormat)
            guard status == noErr else {
                throw NSError(domain: "ChatVM", code: 51,
                              userInfo: [NSLocalizedDescriptionKey: "ExtAudioFile get format failed: \(status)"])
            }
            
            let sampleRate    = clientFormat.mSampleRate
            let channelCount  = clientFormat.mChannelsPerFrame
            
            // --- Formato di output AAC in container M4A ---
            var outputFormat = AudioStreamBasicDescription(
                mSampleRate:       sampleRate,
                mFormatID:         kAudioFormatMPEG4AAC,
                mFormatFlags:      0,
                mBytesPerPacket:   0,
                mFramesPerPacket:  1024,
                mBytesPerFrame:    0,
                mChannelsPerFrame: channelCount,
                mBitsPerChannel:   0,
                mReserved:         0
            )
            
            // --- Crea file di output M4A ---
            var destRef: ExtAudioFileRef?
            status = ExtAudioFileCreateWithURL(
                m4aURL as CFURL,
                kAudioFileM4AType,
                &outputFormat,
                nil,
                AudioFileFlags.eraseFile.rawValue,
                &destRef
            )
            guard status == noErr, let dstFile = destRef else {
                throw NSError(domain: "ChatVM", code: 52,
                              userInfo: [NSLocalizedDescriptionKey: "ExtAudioFile create dest failed: \(status)"])
            }
            defer { ExtAudioFileDispose(dstFile) }
            
            // Imposta il formato client PCM Float32 non-interleaved su entrambi i file
            var pcmFormat = AudioStreamBasicDescription(
                mSampleRate:       sampleRate,
                mFormatID:         kAudioFormatLinearPCM,
                mFormatFlags:      kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket:   4,
                mFramesPerPacket:  1,
                mBytesPerFrame:    4,
                mChannelsPerFrame: channelCount,
                mBitsPerChannel:   32,
                mReserved:         0
            )
            propSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            ExtAudioFileSetProperty(srcFile, kExtAudioFileProperty_ClientDataFormat, propSize, &pcmFormat)
            ExtAudioFileSetProperty(dstFile, kExtAudioFileProperty_ClientDataFormat, propSize, &pcmFormat)
            
            // --- Imposta bitrate AAC 64kbps ---
            var bitRate: UInt32 = 64_000
            ExtAudioFileSetProperty(dstFile, kExtAudioFileProperty_CodecManufacturer,
                                    UInt32(MemoryLayout<UInt32>.size), &bitRate)
            
            // --- Copia frame per frame ---
            let blockFrames  = UInt32(8192)
            let bufferSize   = blockFrames * 4 // Float32 = 4 bytes
            let channelInt   = Int(channelCount)
            
            // Alloca buffer per ogni canale
            let channelBuffers = (0..<channelInt).map { _ in
                UnsafeMutablePointer<Float>.allocate(capacity: Int(blockFrames))
            }
            defer { channelBuffers.forEach { $0.deallocate() } }
            
            var bufferList = AudioBufferList()
            bufferList.mNumberBuffers = channelCount
            
            try withUnsafeMutablePointer(to: &bufferList) { blPtr in
                let ablPtr = UnsafeMutableAudioBufferListPointer(blPtr)
                
                var framesRead = blockFrames
                while framesRead == blockFrames {
                    // Configura AudioBufferList per questo blocco
                    for ch in 0..<channelInt {
                        ablPtr[ch].mNumberChannels = 1
                        ablPtr[ch].mDataByteSize   = bufferSize
                        ablPtr[ch].mData           = UnsafeMutableRawPointer(channelBuffers[ch])
                    }
                    
                    framesRead = blockFrames
                    let readStatus = ExtAudioFileRead(srcFile, &framesRead, blPtr)
                    guard readStatus == noErr else {
                        throw NSError(domain: "ChatVM", code: 53,
                                      userInfo: [NSLocalizedDescriptionKey: "ExtAudioFileRead failed: \(readStatus)"])
                    }
                    guard framesRead > 0 else { break }
                    
                    // Aggiorna dataByteSize con i frame effettivamente letti
                    for ch in 0..<channelInt {
                        ablPtr[ch].mDataByteSize = framesRead * 4
                    }
                    
                    let writeStatus = ExtAudioFileWrite(dstFile, framesRead, blPtr)
                    guard writeStatus == noErr else {
                        throw NSError(domain: "ChatVM", code: 54,
                                      userInfo: [NSLocalizedDescriptionKey: "ExtAudioFileWrite failed: \(writeStatus)"])
                    }
                }
            }
            
            try? FileManager.default.removeItem(at: cafURL)
            return m4aURL
            
        }.value
    }
    
    // MARK: - Send audio – upload
    
    private func uploadAndSendAudio(data: Data, duration: Int, sourceURL: URL? = nil) async {
        guard let modelContext else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let senderName = senderDisplayName()
        let messageId  = UUID().uuidString; let now = Date()
        logAudio("uploadAndSendAudio BEGIN messageId=\(messageId) duration=\(duration) data.count=\(data.count)")
        isUploadingMedia = true; uploadProgress = 0
        let localAudioURL: URL
        do {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dir  = docs.appendingPathComponent("ChatAudio", isDirectory: true)
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let dest = dir.appendingPathComponent("\(messageId).m4a")
            if let src = sourceURL, FileManager.default.fileExists(atPath: src.path) {
                try FileManager.default.moveItem(at: src, to: dest)
                logAudio("uploadAndSendAudio moved sourceURL → dest")
            } else {
                try data.write(to: dest, options: .atomic)
                logAudio("uploadAndSendAudio wrote data to dest")
            }
            localAudioURL = dest
            logFileInfo(localAudioURL, prefix: "uploadAndSendAudio.localCopy")
            await logAudioAssetInfo(localAudioURL, prefix: "uploadAndSendAudio.localCopy")
            testLocalPlayback(localAudioURL, prefix: "uploadAndSendAudio.localCopy")
        } catch {
            isUploadingMedia = false; uploadProgress = 0
            logAudio("uploadAndSendAudio local save ERROR=\(error.localizedDescription)")
            errorText = "Salvataggio audio locale fallito: \(error.localizedDescription)"; return
        }
        let msg = KBChatMessage(
            id: messageId, familyId: familyId, senderId: uid, senderName: senderName,
            type: .audio, mediaDurationSeconds: duration,
            transcriptText: nil, mediaLocalPath: localAudioURL.path,
            transcriptStatus: .processing, transcriptSource: .appleSpeechAnalyzer,
            transcriptLocaleIdentifier: "it-IT", transcriptIsFinal: false,
            transcriptUpdatedAt: now, createdAt: now
        )
        msg.syncState = .pendingUpsert; modelContext.insert(msg); try? modelContext.save(); reloadLocal()
        do {
            logAudio("uploadAndSendAudio upload START mimeType=audio/m4a")
            let (storagePath, downloadURL) = try await storageService.upload(
                data: data, familyId: familyId, messageId: messageId,
                fileName: "audio.m4a", mimeType: "audio/m4a",
                progressHandler: { [weak self] p in Task { @MainActor in self?.uploadProgress = p } })
            logAudio("uploadAndSendAudio upload OK storagePath=\(storagePath)")
            logAudio("uploadAndSendAudio upload OK downloadURL=\(downloadURL)")
            msg.mediaStoragePath = storagePath; msg.mediaURL = downloadURL
            msg.mediaDurationSeconds = duration; msg.syncState = .pendingUpsert
            try? modelContext.save()
            let dto = makeDTO(from: msg); try await remoteStore.upsert(dto: dto)
            logAudio("uploadAndSendAudio remote upsert OK messageId=\(messageId)")
            msg.syncState = .synced; msg.lastSyncError = nil; try? modelContext.save()
        } catch {
            logAudio("uploadAndSendAudio ERROR=\(error.localizedDescription)")
            msg.syncState = .error; msg.lastSyncError = error.localizedDescription
            try? modelContext.save(); errorText = "Invio audio fallito: \(error.localizedDescription)"
        }
        isUploadingMedia = false; uploadProgress = 0
    }
    
    // MARK: - Send document
    
    func sendDocument(url: URL) { Task { await uploadAndSendDocument(url: url) } }
    
    private func uploadAndSendDocument(url: URL) async {
        guard let modelContext else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"; let senderName = senderDisplayName()
        let messageId = UUID().uuidString; let now = Date()
        let fileName = url.lastPathComponent; let mimeType = url.mimeType()
        isUploadingMedia = true; uploadProgress = 0; errorText = nil
        let msg = KBChatMessage(id: messageId, familyId: familyId, senderId: uid, senderName: senderName,
                                type: .document, text: fileName, createdAt: now)
        msg.syncState = .pendingUpsert; modelContext.insert(msg); try? modelContext.save(); reloadLocal()
        do {
            let data = try Data(contentsOf: url)
            let (storagePath, downloadURL) = try await storageService.upload(
                data: data, familyId: familyId, messageId: messageId, fileName: fileName, mimeType: mimeType,
                progressHandler: { [weak self] p in Task { @MainActor in self?.uploadProgress = p } })
            msg.mediaStoragePath = storagePath; msg.mediaURL = downloadURL
            msg.syncState = .pendingUpsert; try? modelContext.save()
            let dto = makeDTO(from: msg); try await remoteStore.upsert(dto: dto)
            msg.syncState = .synced; msg.lastSyncError = nil; try? modelContext.save()
        } catch {
            msg.syncState = .error; msg.lastSyncError = error.localizedDescription
            try? modelContext.save(); errorText = "Invio documento fallito: \(error.localizedDescription)"
        }
        isUploadingMedia = false; uploadProgress = 0
    }
    
    // MARK: - Send core
    
    private func send(type: KBChatMessageType, text: String? = nil) {
        guard let modelContext else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"; let senderName = senderDisplayName()
        let messageId = UUID().uuidString; let now = Date()
        isSending = true
        let msg = KBChatMessage(id: messageId, familyId: familyId, senderId: uid, senderName: senderName,
                                type: type, text: text, createdAt: now)
        msg.syncState = .pendingUpsert; modelContext.insert(msg); try? modelContext.save(); reloadLocal()
        Task {
            let dto = makeDTO(from: msg)
            do {
                try await remoteStore.upsert(dto: dto)
                msg.syncState = .synced; msg.lastSyncError = nil; try? modelContext.save()
            } catch {
                msg.syncState = .error; msg.lastSyncError = error.localizedDescription
                try? modelContext.save(); errorText = "Invio fallito: \(error.localizedDescription)"
            }
            isSending = false
        }
    }
    
    private func send(type: KBChatMessageType, text: String? = nil, replyToId: String?) {
        guard let modelContext else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"; let senderName = senderDisplayName()
        let messageId = UUID().uuidString; let now = Date()
        isSending = true
        let msg = KBChatMessage(id: messageId, familyId: familyId, senderId: uid, senderName: senderName,
                                type: type, text: text, createdAt: now)
        msg.replyToId = replyToId; msg.syncState = .pendingUpsert
        modelContext.insert(msg); try? modelContext.save(); reloadLocal()
        Task {
            let dto = makeDTO(from: msg)
            do {
                try await remoteStore.upsert(dto: dto)
                msg.syncState = .synced; msg.lastSyncError = nil; try? modelContext.save()
            } catch {
                msg.syncState = .error; msg.lastSyncError = error.localizedDescription
                try? modelContext.save(); errorText = "Invio fallito: \(error.localizedDescription)"
            }
            isSending = false
        }
    }
    
    // MARK: - Reactions
    
    func toggleReaction(_ emoji: String, on message: KBChatMessage) {
        guard let modelContext else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        var reactions = message.reactions
        if reactions[emoji]?.contains(uid) == true {
            reactions[emoji]?.removeAll { $0 == uid }
            if reactions[emoji]?.isEmpty == true { reactions.removeValue(forKey: emoji) }
        } else { reactions[emoji, default: []].append(uid) }
        message.reactions = reactions; message.syncState = .pendingUpsert; message.lastSyncError = nil
        try? modelContext.save()
        Task {
            do {
                try await remoteStore.updateReactions(familyId: familyId, messageId: message.id,
                                                      reactionsJSON: message.reactionsJSON)
                message.syncState = .synced; try? modelContext.save()
            } catch {
                message.syncState = .error; message.lastSyncError = error.localizedDescription
                try? modelContext.save()
            }
        }
    }
    
    // MARK: - Clear / Delete
    
    func clearChat() {
        guard let modelContext else { return }
        let snapshot = messages
        Task {
            await withTaskGroup(of: Void.self) { group in
                for msg in snapshot {
                    group.addTask {
                        if let path = msg.mediaStoragePath { try? await self.storageService.delete(storagePath: path) }
                        try? await self.remoteStore.softDelete(familyId: self.familyId, messageId: msg.id)
                    }
                }
            }
            await MainActor.run { for msg in snapshot { modelContext.delete(msg) }; try? modelContext.save(); reloadLocal() }
        }
    }
    
    func deleteMessage(_ message: KBChatMessage) {
        guard let modelContext else { return }
        Task {
            do {
                if let path = message.mediaStoragePath { try? await storageService.delete(storagePath: path) }
                try await remoteStore.softDelete(familyId: familyId, messageId: message.id)
                modelContext.delete(message); try? modelContext.save(); reloadLocal()
            } catch { errorText = "Eliminazione fallita: \(error.localizedDescription)" }
        }
    }
    
    func deleteMessagesLocally(ids: [String]) {
        guard let modelContext, !ids.isEmpty else { return }
        let uid = Auth.auth().currentUser?.uid ?? ""; guard !uid.isEmpty else { return }
        for id in ids {
            let mid  = id
            let desc = FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.id == mid })
            if let msg = try? modelContext.fetch(desc).first {
                msg.isDeleted = true; msg.syncState = .synced; msg.lastSyncError = nil
            }
        }
        saveContext(modelContext, reason: "deleteMessagesLocally-optimistic"); reloadLocal()
        Task {
            await withTaskGroup(of: Void.self) { group in
                for messageId in ids {
                    group.addTask {
                        try? await self.remoteStore.addToDeletedFor(familyId: self.familyId, messageId: messageId, uid: uid)
                    }
                }
            }
        }
    }
    
    func deleteMessagesRemotely(ids: [String]) {
        guard let modelContext, !ids.isEmpty else { return }
        let uid = Auth.auth().currentUser?.uid ?? ""; let now = Date()
        let selected = messages.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        guard selected.allSatisfy({ $0.senderId == uid }) else {
            errorText = "Puoi eliminare per tutti solo messaggi inviati da te."; return
        }
        guard selected.allSatisfy({ now.timeIntervalSince($0.createdAt) <= 300 }) else {
            errorText = "Puoi eliminare per tutti solo entro 5 minuti dall'invio."; return
        }
        Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for msg in selected {
                        group.addTask {
                            if let path = msg.mediaStoragePath { try? await self.storageService.delete(storagePath: path) }
                            try await self.remoteStore.softDelete(familyId: self.familyId, messageId: msg.id)
                        }
                    }
                    try await group.waitForAll()
                }
                await MainActor.run {
                    for msg in selected {
                        msg.isDeletedForEveryone = true
                        msg.isDeleted = false      // keep visible as tombstone
                        msg.syncState = .synced; msg.lastSyncError = nil
                    }
                    try? modelContext.save(); self.reloadLocal()
                }
            } catch {
                await MainActor.run { self.errorText = "Eliminazione per tutti fallita: \(error.localizedDescription)" }
            }
        }
    }
    
    // MARK: - Read receipts
    
    func markVisibleMessagesAsRead() {
        let uid = Auth.auth().currentUser?.uid ?? ""; guard !uid.isEmpty else { return }
        let unread = messages.filter { $0.senderId != uid && !$0.readBy.contains(uid) && $0.syncState == .synced }
        guard !unread.isEmpty, let modelContext else { return }
        let ids = unread.map(\.id)
        for msg in unread { var rb = msg.readBy; rb.append(uid); msg.readBy = rb }
        try? modelContext.save()
        Task { try? await remoteStore.markAsRead(familyId: familyId, messageIds: ids, uid: uid) }
    }
    
    // MARK: - Send location
    
    func sendLocation(latitude: Double, longitude: Double) {
        guard let modelContext, !familyId.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        let senderName = senderDisplayName(); let messageId = UUID().uuidString; let now = Date()
        isSending = true
        let msg = KBChatMessage(id: messageId, familyId: familyId, senderId: uid, senderName: senderName,
                                type: .location, text: nil, createdAt: now)
        msg.latitude = latitude; msg.longitude = longitude; msg.syncState = .pendingUpsert
        modelContext.insert(msg); try? modelContext.save(); reloadLocal()
        Task {
            let dto = makeDTO(from: msg)
            do {
                try await remoteStore.upsert(dto: dto)
                await MainActor.run {
                    msg.syncState = .synced; msg.lastSyncError = nil; try? modelContext.save(); self.isSending = false
                }
            } catch {
                await MainActor.run {
                    msg.syncState = .error; msg.lastSyncError = error.localizedDescription; try? modelContext.save()
                    self.errorText = "Invio posizione fallito: \(error.localizedDescription)"; self.isSending = false
                }
            }
        }
    }
    
    // MARK: - Transcript
    
    @MainActor
    private func startTranscriptIfNeeded(for message: KBChatMessage, modelContext: ModelContext) {
        guard message.type == .audio else { return }
        let myUID = Auth.auth().currentUser?.uid ?? ""
        guard message.senderId != myUID else { return }
        guard message.transcriptStatus != .processing, message.transcriptStatus != .completed else { return }
        // Rispetta la preferenza utente: se la trascrizione è disabilitata nelle impostazioni, non avviarla.
        let transcriptionEnabled = UserDefaults.standard.object(forKey: "kb_audioTranscriptionEnabled") as? Bool ?? true
        guard transcriptionEnabled else {
            KBLog.data.kbInfo("[TRANSCRIPT] skipped — transcription disabled by user preference")
            return
        }
        message.transcriptStatus = .processing; message.transcriptUpdatedAt = Date()
        try? modelContext.save(); reloadLocal()
        Task {
            do {
                let localURL: URL
                if let localPath = message.mediaLocalPath, !localPath.isEmpty {
                    localURL = URL(fileURLWithPath: localPath)
                } else if let mediaURLString = message.mediaURL, let remoteURL = URL(string: mediaURLString) {
                    localURL = try await downloadAudioLocally(from: remoteURL, messageId: message.id)
                    await MainActor.run { message.mediaLocalPath = localURL.path; try? modelContext.save() }
                } else {
                    throw NSError(domain: "Chat", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio non disponibile per la trascrizione"])
                }
                self.logFileInfo(localURL, prefix: "transcript.input")
                await self.logAudioAssetInfo(localURL, prefix: "transcript.input")
                self.testLocalPlayback(localURL, prefix: "transcript.input")
                if #available(iOS 26.0, *) {
                    let result = try await SpeechTranscriptionService.shared.transcribeFile(at: localURL, localeIdentifier: "it-IT")
                    await MainActor.run {
                        message.transcriptText = result.text; message.transcriptStatus = .completed
                        message.transcriptSource = .appleSpeechAnalyzer; message.transcriptLocaleIdentifier = result.localeIdentifier
                        message.transcriptIsFinal = result.isFinal; message.transcriptUpdatedAt = Date()
                        message.transcriptErrorMessage = nil; try? modelContext.save(); reloadLocal()
                    }
                } else {
                    await MainActor.run {
                        message.transcriptStatus = .failed
                        message.transcriptErrorMessage = "SpeechAnalyzer richiede iOS 26 o successivo"
                        message.transcriptUpdatedAt = Date(); try? modelContext.save(); reloadLocal()
                    }
                }
            } catch {
                await MainActor.run {
                    message.transcriptStatus = .failed; message.transcriptErrorMessage = error.localizedDescription
                    message.transcriptUpdatedAt = Date(); try? modelContext.save(); reloadLocal()
                }
            }
        }
    }
    
    private func downloadAudioLocally(from remoteURL: URL, messageId: String) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir  = docs.appendingPathComponent("ChatAudio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let fileURL = dir.appendingPathComponent("\(messageId).m4a")
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
        return fileURL
    }
    
    // MARK: - Audio logging helpers
    
    private func logAudio(_ message: String) { KBLog.data.kbInfo("[AUDIO] \(message)") }
    
    private func describeAudioSession(_ prefix: String) {
        let session = AVAudioSession.sharedInstance()
        logAudio("\(prefix) session.category=\(session.category.rawValue)")
        logAudio("\(prefix) session.mode=\(session.mode.rawValue)")
        logAudio("\(prefix) session.sampleRate=\(session.sampleRate)")
        logAudio("\(prefix) session.ioBufferDuration=\(session.ioBufferDuration)")
        logAudio("\(prefix) session.inputAvailable=\(session.isInputAvailable)")
        if #available(iOS 17.0, *) {
            logAudio("\(prefix) session.recordPermission=\(AVAudioApplication.shared.recordPermission.rawValue)")
        } else {
            logAudio("\(prefix) session.recordPermission=\(session.recordPermission.rawValue)")
        }
        let inputs = session.availableInputs?.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ") ?? "none"
        logAudio("\(prefix) session.availableInputs=\(inputs)")
        let ins  = session.currentRoute.inputs .map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
        let outs = session.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
        logAudio("\(prefix) session.currentRoute.inputs=\(ins)")
        logAudio("\(prefix) session.currentRoute.outputs=\(outs)")
    }
    
    private func logFileInfo(_ url: URL, prefix: String) {
        let exists = FileManager.default.fileExists(atPath: url.path)
        logAudio("\(prefix) url=\(url.path)"); logAudio("\(prefix) exists=\(exists)"); logAudio("\(prefix) ext=\(url.pathExtension)")
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isRegularFileKey])
            logAudio("\(prefix) fileSize=\(values.fileSize ?? -1)")
            logAudio("\(prefix) creationDate=\(values.creationDate?.description ?? "nil")")
            logAudio("\(prefix) modificationDate=\(values.contentModificationDate?.description ?? "nil")")
            logAudio("\(prefix) isRegularFile=\(values.isRegularFile?.description ?? "nil")")
        } catch { logAudio("\(prefix) resourceValues ERROR=\(error.localizedDescription)") }
    }
    
    private func logAudioAssetInfo(_ url: URL, prefix: String) async {
        let asset = AVURLAsset(url: url)
        do { let d = try await asset.load(.duration); logAudio("\(prefix) asset.durationSeconds=\(CMTimeGetSeconds(d))") }
        catch { logAudio("\(prefix) asset.duration ERROR=\(error.localizedDescription)") }
        do { let t = try await asset.loadTracks(withMediaType: .audio); logAudio("\(prefix) asset.audioTracks=\(t.count)") }
        catch { logAudio("\(prefix) asset.audioTracks ERROR=\(error.localizedDescription)") }
    }
    
    private func testLocalPlayback(_ url: URL, prefix: String) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            let ok = player.prepareToPlay()
            logAudio("\(prefix) AVAudioPlayer.init=OK prepareToPlay=\(ok) duration=\(player.duration)")
        } catch { logAudio("\(prefix) AVAudioPlayer ERROR=\(error.localizedDescription)") }
    }
    
    // MARK: - Helpers
    
    private func senderDisplayName() -> String {
        guard let modelContext else { return "Utente" }
        let uid = Auth.auth().currentUser?.uid ?? ""; guard !uid.isEmpty else { return "Utente" }
        let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
        guard let profile = try? modelContext.fetch(desc).first else { return "Utente" }
        let first     = (profile.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last      = (profile.lastName  ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        let stored    = (profile.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen: String
        if !canonical.isEmpty { chosen = canonical } else if !stored.isEmpty { chosen = stored } else { chosen = "Utente" }
        if !canonical.isEmpty, canonical != stored {
            profile.displayName = canonical; profile.updatedAt = Date(); try? modelContext.save()
        }
        return chosen
    }
    
    private func makeDTO(from msg: KBChatMessage) -> RemoteChatMessageDTO {
        RemoteChatMessageDTO(
            id: msg.id, familyId: msg.familyId, senderId: msg.senderId, senderName: msg.senderName,
            typeRaw: msg.typeRaw, text: msg.text, mediaStoragePath: msg.mediaStoragePath,
            mediaURL: msg.mediaURL, mediaDurationSeconds: msg.mediaDurationSeconds,
            mediaThumbnailURL: msg.mediaThumbnailURL, replyToId: msg.replyToId,
            reactionsJSON: msg.reactionsJSON, readByJSON: nil,
            createdAt: msg.createdAt, editedAt: msg.editedAt,
            isDeleted: msg.isDeleted, deletedFor: [],
            latitude: msg.latitude, longitude: msg.longitude
        )
    }
    
    func retryFailedMessages() {
        guard let modelContext else { return }
        
        let fid = familyId
        
        // syncStateRaw è Int: error = 3, pendingUpsert = 1
        let errorRaw   = KBSyncState.error.rawValue         // 3
        let pendingRaw = KBSyncState.pendingUpsert.rawValue  // 1
        
        let descError = FetchDescriptor<KBChatMessage>(
            predicate: #Predicate<KBChatMessage> {
                $0.familyId == fid &&
                $0.syncStateRaw == errorRaw &&
                $0.isDeleted == false
            },
            sortBy: [SortDescriptor(\KBChatMessage.createdAt, order: .forward)]
        )
        
        let descPending = FetchDescriptor<KBChatMessage>(
            predicate: #Predicate<KBChatMessage> {
                $0.familyId == fid &&
                $0.syncStateRaw == pendingRaw &&
                $0.isDeleted == false
            },
            sortBy: [SortDescriptor(\KBChatMessage.createdAt, order: .forward)]
        )
        
        let errorMsgs   = (try? modelContext.fetch(descError))   ?? []
        let pendingMsgs = (try? modelContext.fetch(descPending)) ?? []
        let failed      = (errorMsgs + pendingMsgs)
            .sorted { $0.createdAt < $1.createdAt }
        
        guard !failed.isEmpty else { return }
        
        KBLog.sync.kbInfo("ChatVM retryFailedMessages count=\(failed.count)")
        
        Task {
            for msg in failed {
                // I messaggi media (foto/video/audio) con mediaURL nil
                // hanno fallito anche l'upload su Storage — non possiamo
                // ritentare solo Firestore, saltiamo per ora.
                if msg.type != .text && msg.type != .location && msg.mediaURL == nil {
                    KBLog.sync.kbDebug("ChatVM retry skip — mediaURL nil msgId=\(msg.id)")
                    continue
                }
                do {
                    let dto = makeDTO(from: msg)
                    try await remoteStore.upsert(dto: dto)
                    msg.syncState = .synced
                    msg.lastSyncError = nil
                    try? modelContext.save()
                    KBLog.sync.kbInfo("ChatVM retry OK msgId=\(msg.id)")
                } catch {
                    msg.syncState = .error
                    msg.lastSyncError = error.localizedDescription
                    try? modelContext.save()
                    KBLog.sync.kbError("ChatVM retry failed msgId=\(msg.id): \(error.localizedDescription)")
                }
            }
            await MainActor.run { reloadLocal() }
        }
    }
}

// MARK: - ListenerRegistrationProtocol

protocol ListenerRegistrationProtocol { func remove() }

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
        case "m4a":         return "audio/m4a"
        case "mp4":         return "video/mp4"
        case "mov":         return "video/quicktime"
        default:            return "application/octet-stream"
        }
    }
}
