//
//  SyncCenter+Photos.swift
//  KidBox
//
//  Pattern mirrors SyncCenter+DocumentsEvents.swift exactly.
//  Encryption: DocumentCryptoService (family master key via FamilyKeychainStore).
//

import Foundation
import SwiftData
import Combine
import FirebaseAuth
import FirebaseFirestore

extension SyncCenter {
    
    // MARK: - Shared remote store
    static let photoRemote = PhotoRemoteStore()
    
    // MARK: - Listeners
    private static var _photosListener: ListenerRegistration?
    private static var _albumsListener: ListenerRegistration?
    
    // MARK: - Publisher
    private static let _photosChanged = PassthroughSubject<String, Never>()
    var photosChanged: AnyPublisher<String, Never> { Self._photosChanged.eraseToAnyPublisher() }
    
    // MARK: - Start
    
    func startPhotosRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startPhotosRealtime familyId=\(familyId)")
        stopPhotosRealtime()
        
        Self._photosListener = Self.photoRemote.listenPhotos(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyPhotosInbound(changes: changes, familyId: familyId, modelContext: modelContext)
                    Self._photosChanged.send(familyId)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "photos", error: err)
                    }
                }
            }
        )
        
        Self._albumsListener = Self.photoRemote.listenAlbums(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyAlbumsInbound(changes: changes, familyId: familyId, modelContext: modelContext)
                    Self._photosChanged.send(familyId)
                }
            },
            onError: { err in
                KBLog.sync.kbError("Albums listener error: \(err.localizedDescription)")
            }
        )
        
        KBLog.sync.kbInfo("Photos + Albums listeners attached familyId=\(familyId)")
    }
    
    // MARK: - Stop
    
    func stopPhotosRealtime() {
        if Self._photosListener != nil || Self._albumsListener != nil {
            KBLog.sync.kbInfo("stopPhotosRealtime")
        }
        Self._photosListener?.remove(); Self._photosListener = nil
        Self._albumsListener?.remove(); Self._albumsListener = nil
    }
    
    // MARK: - Apply inbound — Photos (LWW)
    // NOTE: No key handling needed — decryption uses DocumentCryptoService at read time.
    
    func applyPhotosInbound(
        changes: [PhotoRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("applyPhotosInbound changes=\(changes.count) familyId=\(familyId)")
        do {
            for change in changes {
                switch change {
                    
                case .upsert(let dto):
                    if dto.isDeleted {
                        if let local = try fetchPhoto(id: dto.id, modelContext: modelContext) {
                            modelContext.delete(local)
                        }
                        continue
                    }
                    
                    let local = try fetchOrCreatePhoto(id: dto.id, familyId: familyId, modelContext: modelContext)
                    let remoteAt = dto.updatedAt ?? Date()
                    let isPlaceholder = local.storagePath.isEmpty
                    KBLog.sync.kbDebug("applyPhotosInbound: upsert id=\(dto.id) storagePath=\(dto.storagePath) thumbPresent=\(dto.thumbnailBase64 != nil) downloadURL=\(dto.downloadURL ?? "nil") isPlaceholder=\(isPlaceholder) remoteAt=\(remoteAt) localUpdatedAt=\(local.updatedAt)")
                    
                    KBLog.sync.kbError("applyPhotosInbound: CHECK id=\(dto.id) isPlaceholder=\(isPlaceholder) remoteAt=\(remoteAt) localAt=\(local.updatedAt) dtoDuration=\(dto.videoDurationSeconds != nil ? String(dto.videoDurationSeconds!) : "nil") isVideo=\(local.isVideo)")
                    if isPlaceholder || remoteAt >= local.updatedAt {
                        local.familyId        = dto.familyId
                        local.fileName        = dto.fileName
                        local.mimeType        = dto.mimeType
                        local.fileSize        = dto.fileSize
                        local.storagePath     = dto.storagePath
                        local.downloadURL     = dto.downloadURL
                        if let t = dto.thumbnailBase64 { local.thumbnailBase64 = t }
                        local.caption                = dto.caption
                        local.albumIdsRaw            = dto.albumIdsRaw
                        // Non sovrascrivere la durata locale se quella remota è nil —
                        // il listener può arrivare prima che upsertMetadata scriva il campo.
                        if let dur = dto.videoDurationSeconds { local.videoDurationSeconds = dur }
                        local.takenAt         = dto.takenAt
                        local.updatedAt       = remoteAt
                        local.updatedBy       = dto.updatedBy
                        if !dto.createdBy.isEmpty { local.createdBy = dto.createdBy }
                        local.isDeleted       = false
                        local.syncState       = .synced
                        local.lastSyncError   = nil
                        KBLog.sync.kbError("applyPhotosInbound: APPLIED id=\(dto.id) duration=\(local.videoDurationSeconds != nil ? String(local.videoDurationSeconds!) : "nil") isVideo=\(local.isVideo)")
                    } else {
                        KBLog.sync.kbError("applyPhotosInbound: SKIPPED id=\(dto.id) remoteAt=\(remoteAt) localAt=\(local.updatedAt)")
                    }
                    
                case .remove(let id):
                    if let local = try fetchPhoto(id: id, modelContext: modelContext) {
                        modelContext.delete(local)
                    }
                }
            }
            try modelContext.save()
            KBLog.sync.kbInfo("Photos inbound applied familyId=\(familyId)")
        } catch {
            KBLog.sync.kbError("applyPhotosInbound failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Apply inbound — Albums (LWW)
    
    private func applyAlbumsInbound(
        changes: [AlbumRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("applyAlbumsInbound changes=\(changes.count)")
        do {
            for change in changes {
                switch change {
                    
                case .upsert(let dto):
                    if dto.isDeleted {
                        let aid = dto.id
                        let desc = FetchDescriptor<KBPhotoAlbum>(predicate: #Predicate { $0.id == aid })
                        if let local = try modelContext.fetch(desc).first { modelContext.delete(local) }
                        continue
                    }
                    let remoteAt = dto.updatedAt ?? Date()
                    let aid = dto.id
                    let desc = FetchDescriptor<KBPhotoAlbum>(predicate: #Predicate { $0.id == aid })
                    
                    if let local = try modelContext.fetch(desc).first {
                        if remoteAt >= local.updatedAt {
                            local.title        = dto.title
                            local.coverPhotoId = dto.coverPhotoId
                            local.sortOrder    = dto.sortOrder
                            local.updatedAt    = remoteAt
                            local.updatedBy    = dto.updatedBy
                            local.isDeleted    = false
                            local.syncState    = .synced
                        }
                    } else {
                        let album = KBPhotoAlbum(
                            id: dto.id, familyId: familyId, title: dto.title,
                            coverPhotoId: dto.coverPhotoId, sortOrder: dto.sortOrder,
                            createdAt: dto.createdAt ?? remoteAt,
                            updatedAt: remoteAt,
                            createdBy: dto.createdBy, updatedBy: dto.updatedBy
                        )
                        album.syncState = .synced
                        modelContext.insert(album)
                    }
                    
                case .remove(let id):
                    let aid = id
                    let desc = FetchDescriptor<KBPhotoAlbum>(predicate: #Predicate { $0.id == aid })
                    if let local = try modelContext.fetch(desc).first { modelContext.delete(local) }
                }
            }
            try modelContext.save()
        } catch {
            KBLog.sync.kbError("applyAlbumsInbound failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Fetch helpers
    
    private func fetchPhoto(id: String, modelContext: ModelContext) throws -> KBFamilyPhoto? {
        let pid = id
        return try modelContext.fetch(FetchDescriptor<KBFamilyPhoto>(predicate: #Predicate { $0.id == pid })).first
    }
    
    private func fetchOrCreatePhoto(id: String, familyId: String, modelContext: ModelContext) throws -> KBFamilyPhoto {
        if let ex = try fetchPhoto(id: id, modelContext: modelContext) { return ex }
        let p = KBFamilyPhoto(id: id, familyId: familyId, fileName: "", createdBy: "remote", updatedBy: "remote")
        p.updatedAt = .distantPast
        p.syncState = .synced
        modelContext.insert(p)
        return p
    }
    
    // MARK: - Direct album upload (non cancellabile)
    
    /// Carica l'album direttamente su Firestore senza passare dall'outbox cancellabile.
    /// Usato da createAlbum/createAlbumAndAddSelected per garantire che la scrittura
    /// non venga annullata da un secondo flushGlobal concorrente.
    func uploadAlbumDirectly(albumId: String, familyId: String, modelContext: ModelContext) {
        Task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            let aid = albumId
            guard let album = try? modelContext.fetch(
                FetchDescriptor<KBPhotoAlbum>(predicate: #Predicate { $0.id == aid })
            ).first else {
                KBLog.sync.kbError("uploadAlbumDirectly: album not found id=\(albumId)")
                return
            }
            do {
                try await Self.photoRemote.upsertAlbum(dto: RemoteAlbumDTO(
                    id: album.id, familyId: album.familyId, title: album.title,
                    coverPhotoId: album.coverPhotoId, sortOrder: album.sortOrder,
                    createdBy: album.createdBy, updatedBy: uid,
                    createdAt: album.createdAt, updatedAt: album.updatedAt,
                    isDeleted: album.isDeleted
                ))
                await MainActor.run {
                    album.syncState = .synced
                    try? modelContext.save()
                }
                KBLog.sync.kbInfo("uploadAlbumDirectly: OK albumId=\(albumId)")
            } catch {
                KBLog.sync.kbError("uploadAlbumDirectly: FAILED albumId=\(albumId) err=\(error.localizedDescription)")
                // Fallback: metti in outbox per retry automatico
                enqueueAlbumUpsert(albumId: albumId, familyId: familyId, modelContext: modelContext)
            }
        }
    }
    
    // MARK: - Outbox enqueue
    
    func enqueuePhotoUpsert(photoId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(familyId: familyId, entityType: "photo", entityId: photoId, opType: "upsert", modelContext: modelContext)
    }
    
    func enqueuePhotoDelete(photoId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(familyId: familyId, entityType: "photo", entityId: photoId, opType: "delete", modelContext: modelContext)
    }
    
    func enqueueAlbumUpsert(albumId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(familyId: familyId, entityType: "photoAlbum", entityId: albumId, opType: "upsert", modelContext: modelContext)
    }
    
    /// Elimina l'album direttamente su Firestore senza passare dall'outbox cancellabile.
    func deleteAlbumDirectly(albumId: String, familyId: String, modelContext: ModelContext) {
        Task {
            do {
                try await Self.photoRemote.softDeleteAlbum(familyId: familyId, albumId: albumId)
                KBLog.sync.kbInfo("deleteAlbumDirectly: OK albumId=\(albumId)")
            } catch {
                KBLog.sync.kbError("deleteAlbumDirectly: FAILED albumId=\(albumId) err=\(error.localizedDescription)")
                // Fallback: outbox per retry automatico
                enqueueAlbumDelete(albumId: albumId, familyId: familyId, modelContext: modelContext)
            }
        }
    }
    
    func enqueueAlbumDelete(albumId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(familyId: familyId, entityType: "photoAlbum", entityId: albumId, opType: "delete", modelContext: modelContext)
    }
    
    // MARK: - Process outbox op
    
    func processPhotoOp(op: KBSyncOp, modelContext: ModelContext) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw PhotoStoreError.notAuthenticated }
        
        switch op.entityTypeRaw {
            
        case "photo":
            let pid = op.entityId
            let photo = try modelContext.fetch(
                FetchDescriptor<KBFamilyPhoto>(predicate: #Predicate { $0.id == pid })
            ).first
            
            switch op.opType {
            case "upsert":
                guard let photo else {
                    KBLog.sync.kbError("processPhotoOp: photo not found in SwiftData photoId=\(pid)")
                    return
                }
                KBLog.sync.kbInfo("processPhotoOp: upsert photoId=\(photo.id) storagePath=\(photo.storagePath) syncState=\(photo.syncStateRaw)")
                photo.syncState = .pendingUpsert
                try modelContext.save()
                try await Self.photoRemote.upsertMetadata(dto: RemotePhotoDTO(
                    id: photo.id, familyId: photo.familyId,
                    fileName: photo.fileName, mimeType: photo.mimeType,
                    fileSize: photo.fileSize, storagePath: photo.storagePath,
                    downloadURL: photo.downloadURL, thumbnailBase64: photo.thumbnailBase64,
                    caption: photo.caption, albumIdsRaw: photo.albumIdsRaw,
                    videoDurationSeconds: photo.videoDurationSeconds,
                    takenAt: photo.takenAt, createdAt: photo.createdAt,
                    updatedAt: photo.updatedAt, createdBy: photo.createdBy,
                    updatedBy: uid, isDeleted: photo.isDeleted
                ))
                photo.syncState = .synced
                photo.lastSyncError = nil
                try modelContext.save()
                KBLog.sync.kbInfo("processPhotoOp: upsert DONE photoId=\(photo.id)")
                
            case "delete":
                KBLog.sync.kbInfo("processPhotoOp: delete photoId=\(pid)")
                // Hard delete: cancella il file da Firebase Storage, rimuove il
                // documento Firestore e sottrae fileSize dal contatore usedBytes.
                // Non esiste un motivo per mantenere un soft-delete per le foto:
                // l'utente le elimina intenzionalmente e lo spazio deve liberarsi
                // immediatamente. Il trigger onPhotoHardDeleted lato Cloud Function
                // si occupa di aggiornare il contatore usedBytes.
                let fileSizeToFree = photo?.fileSize ?? 0
                let storagePath    = photo?.storagePath ?? ""
                try await Self.photoRemote.hardDeletePhoto(
                    familyId: op.familyId,
                    photoId: pid,
                    storagePath: storagePath
                )
                if let photo { modelContext.delete(photo); try modelContext.save() }
                KBLog.sync.kbInfo("processPhotoOp: delete DONE photoId=\(pid) freedBytes=\(fileSizeToFree)")
                
            default: break
            }
            
        case "photoAlbum":
            let aid = op.entityId
            let album = try modelContext.fetch(
                FetchDescriptor<KBPhotoAlbum>(predicate: #Predicate { $0.id == aid })
            ).first
            
            switch op.opType {
            case "upsert":
                guard let album else { return }
                album.syncState = .pendingUpsert
                try modelContext.save()
                try await Self.photoRemote.upsertAlbum(dto: RemoteAlbumDTO(
                    id: album.id, familyId: album.familyId, title: album.title,
                    coverPhotoId: album.coverPhotoId, sortOrder: album.sortOrder,
                    createdBy: album.createdBy, updatedBy: uid,
                    createdAt: album.createdAt, updatedAt: album.updatedAt,
                    isDeleted: album.isDeleted
                ))
                album.syncState = .synced
                try modelContext.save()
                
            case "delete":
                try await Self.photoRemote.softDeleteAlbum(familyId: op.familyId, albumId: aid)
                if let album { modelContext.delete(album); try modelContext.save() }
                
            default: break
            }
            
        default: break
        }
    }
    
#if DEBUG
    func applyPhotosInbound_testable(
        changes: [PhotoRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        applyPhotosInbound(changes: changes, familyId: familyId, modelContext: modelContext)
    }
#endif
}
