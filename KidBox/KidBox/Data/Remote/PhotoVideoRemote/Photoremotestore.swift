//
//  PhotoRemoteStore.swift
//  KidBox
//

import Foundation
import CoreGraphics
import ImageIO
import FirebaseAuth
import FirebaseFirestore
import AVFoundation
import FirebaseStorage

// MARK: - DTOs

struct RemotePhotoDTO {
    let id: String
    let familyId: String
    let fileName: String
    let mimeType: String
    let fileSize: Int64
    let storagePath: String
    let downloadURL: String?
    let thumbnailBase64: String?
    let caption: String?
    let albumIdsRaw: String
    var videoDurationSeconds: Double? = nil   // nil per le immagini
    let takenAt: Date
    let createdAt: Date?
    let updatedAt: Date?
    let createdBy: String
    let updatedBy: String
    let isDeleted: Bool
}

struct RemoteAlbumDTO {
    let id: String
    let familyId: String
    let title: String
    let coverPhotoId: String?
    let sortOrder: Int
    let createdBy: String
    let updatedBy: String
    let createdAt: Date?
    let updatedAt: Date?
    let isDeleted: Bool
}

enum PhotoRemoteChange {
    case upsert(RemotePhotoDTO)
    case remove(String)
}

enum AlbumRemoteChange {
    case upsert(RemoteAlbumDTO)
    case remove(String)
}


// MARK: - PhotoRemoteStore

/// Handles Firebase Storage (encrypted) + Firestore (metadata) for family photos and albums.
///
/// Encryption:
/// - Uses `DocumentCryptoService.encrypt/decrypt(familyId:userId:)` which wraps
///   the per-family AES-256-GCM master key stored in `FamilyKeychainStore`.
/// - The same key protects documents AND photos for a given family.
/// - Key syncs across all family members' devices via iCloud Keychain → any member
///   who has the key can decrypt any photo uploaded by anyone in the family.
/// - Firebase Storage receives: encrypted blob, contentType = application/octet-stream.
/// - Firestore receives: plain metadata + thumbnail JPEG (≤200 px) for fast grid display.
final class PhotoRemoteStore {
    
    private var db: Firestore { Firestore.firestore() }
    private var storage: Storage { Storage.storage() }
    
    // MARK: - Thumbnail
    
    /// Generates a JPEG thumbnail ≤ maxDimension px from image data.
    static func makeThumbnail(from data: Data, maxDimension: CGFloat = 200) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        
        let w = CGFloat(cgImg.width), h = CGFloat(cgImg.height)
        let scale = min(maxDimension / max(w, 1), maxDimension / max(h, 1), 1.0)
        let nw = Int(w * scale), nh = Int(h * scale)
        
        guard
            let cs = CGColorSpace(name: CGColorSpace.sRGB),
            let ctx = CGContext(
                data: nil, width: nw, height: nh,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return nil }
        
        ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        guard let thumb = ctx.makeImage() else { return nil }
        
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, thumb, [kCGImageDestinationLossyCompressionQuality: 0.55] as CFDictionary)
        CGImageDestinationFinalize(dst)
        return out as Data
    }
    
    // MARK: - Video thumbnail
    
    /// Estrae il primo frame disponibile di un video MP4 come JPEG thumbnail.
    /// Async perché AVURLAsset.load(.tracks) richiede await per garantire che
    /// le tracce siano caricate prima che AVAssetImageGenerator possa operare.
    /// Fallback: genera thumbnail da Data (usato per video già in memoria senza URL disponibile).
    static func makeVideoThumbnail(from data: Data, maxDimension: CGFloat = 200) async -> Data? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        do { try data.write(to: tmp) } catch {
            KBLog.sync.kbError("makeVideoThumbnail(data): write failed: \(error.localizedDescription)")
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        return await makeVideoThumbnail(url: tmp, maxDimension: maxDimension)
    }
    
    /// Overload che accetta direttamente un URL — usato durante l'upload
    /// per evitare di riscrivere su disco un file già disponibile come URL compresso.
    static func makeVideoThumbnail(url: URL, maxDimension: CGFloat = 200) async -> Data? {
        let asset = AVURLAsset(url: url)
        do { _ = try await asset.load(.tracks) } catch {
            KBLog.sync.kbError("makeVideoThumbnail(url): load tracks failed: \(error.localizedDescription)")
            return nil
        }
        return await _generateFrame(from: asset, maxDimension: maxDimension)
    }
    
    /// Core: genera il JPEG da un AVAsset già caricato.
    private static func _generateFrame(from asset: AVAsset, maxDimension: CGFloat) async -> Data? {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter  = CMTime(seconds: 1, preferredTimescale: 600)
        
        var cgImg: CGImage?
        for secs in [0.0, 0.1, 0.5, 1.0] {
            let t = CMTime(seconds: secs, preferredTimescale: 600)
            if let img = try? gen.copyCGImage(at: t, actualTime: nil) { cgImg = img; break }
        }
        guard let cgImg else {
            KBLog.sync.kbError("makeVideoThumbnail: copyCGImage nil for all attempts")
            return nil
        }
        KBLog.sync.kbDebug("makeVideoThumbnail: frame \(cgImg.width)x\(cgImg.height)")
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, cgImg, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        CGImageDestinationFinalize(dst)
        KBLog.sync.kbDebug("makeVideoThumbnail: JPEG bytes=\(out.length)")
        return out as Data
    }
    
    // MARK: - Upload
    
    /// Encrypts with the family master key, uploads to Firebase Storage, writes Firestore metadata.
    ///
    /// - Parameter userId: Current Firebase Auth UID — needed to load the family key from Keychain.
    func upload(
        photoId: String,
        familyId: String,
        userId: String,
        imageData: Data,
        fileName: String,
        mimeType: String,
        takenAt: Date,
        caption: String?,
        albumIds: [String],
        precomputedThumbnailB64: String? = nil,         // passa qui il thumb già pronto (obbligatorio per video)
        precomputedVideoDurationSeconds: Double? = nil,  // durata in secondi (solo video)
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> RemotePhotoDTO {
        
        // 1. Encrypt with family master key (same key used for documents)
        KBLog.sync.kbInfo("PhotoRemoteStore.upload: start photoId=\(photoId) familyId=\(familyId) bytes=\(imageData.count) mimeType=\(mimeType)")
        let encrypted = try DocumentCryptoService.encrypt(imageData, familyId: familyId, userId: userId)
        KBLog.sync.kbDebug("PhotoRemoteStore.upload: encrypted outBytes=\(encrypted.count) photoId=\(photoId)")
        
        // 2. Thumbnail — usa quello precalcolato se disponibile, altrimenti genera da imageData (solo immagini)
        let thumbB64: String?
        if let pre = precomputedThumbnailB64 {
            thumbB64 = pre
            KBLog.sync.kbDebug("PhotoRemoteStore.upload: using precomputed thumbnail photoId=\(photoId)")
        } else {
            thumbB64 = PhotoRemoteStore.makeThumbnail(from: imageData)?.base64EncodedString()
            KBLog.sync.kbDebug("PhotoRemoteStore.upload: thumbnail generated=\(thumbB64 != nil) photoId=\(photoId)")
        }
        
        // 3. Upload encrypted blob to Firebase Storage
        let storagePath = "families/\(familyId)/photos/\(photoId)/original.enc"
        KBLog.sync.kbInfo("PhotoRemoteStore.upload: uploading to Storage path=\(storagePath)")
        let ref = storage.reference().child(storagePath)
        let meta = StorageMetadata()
        meta.contentType = "application/octet-stream"
        
        let downloadURL: String = try await withCheckedThrowingContinuation { cont in
            let task = ref.putData(encrypted, metadata: meta)
            task.observe(.progress) { snap in
                let pct = Double(snap.progress?.completedUnitCount ?? 0)
                / Double(max(snap.progress?.totalUnitCount ?? 1, 1))
                onProgress?(pct)
            }
            task.observe(.success) { _ in
                KBLog.sync.kbDebug("PhotoRemoteStore.upload: Storage putData success, fetching downloadURL photoId=\(photoId)")
                ref.downloadURL { url, err in
                    if let err {
                        KBLog.sync.kbError("PhotoRemoteStore.upload: downloadURL failed photoId=\(photoId) err=\(err.localizedDescription)")
                        cont.resume(throwing: err); return
                    }
                    KBLog.sync.kbDebug("PhotoRemoteStore.upload: downloadURL OK photoId=\(photoId)")
                    cont.resume(returning: url?.absoluteString ?? "")
                }
            }
            task.observe(.failure) { snap in
                let err = snap.error ?? PhotoStoreError.uploadFailed
                KBLog.sync.kbError("PhotoRemoteStore.upload: Storage putData FAILED photoId=\(photoId) err=\(err.localizedDescription)")
                cont.resume(throwing: err)
            }
        }
        
        KBLog.sync.kbInfo("PhotoRemoteStore.upload: Storage OK photoId=\(photoId) path=\(storagePath)")
        
        // 4. Firestore metadata
        let now = Date()
        let dto = RemotePhotoDTO(
            id: photoId, familyId: familyId, fileName: fileName,
            mimeType: mimeType, fileSize: Int64(imageData.count),
            storagePath: storagePath, downloadURL: downloadURL,
            thumbnailBase64: thumbB64, caption: caption,
            albumIdsRaw: albumIds.joined(separator: ","),
            videoDurationSeconds: precomputedVideoDurationSeconds,
            takenAt: takenAt, createdAt: now, updatedAt: now,
            createdBy: userId, updatedBy: userId, isDeleted: false
        )
        KBLog.sync.kbInfo("PhotoRemoteStore.upload: writing Firestore metadata photoId=\(photoId) thumbPresent=\(thumbB64 != nil)")
        try await upsertMetadata(dto: dto)
        KBLog.sync.kbInfo("PhotoRemoteStore.upload: DONE photoId=\(photoId)")
        return dto
    }
    
    // MARK: - Download + decrypt
    
    /// Downloads and decrypts a photo using the family master key.
    ///
    /// - Parameter userId: Current Firebase Auth UID — needed to load the family key from Keychain.
    func download(storagePath: String, familyId: String, userId: String) async throws -> Data {
        KBLog.sync.kbInfo("PhotoRemoteStore.download: start path=\(storagePath) familyId=\(familyId)")
        let ref = storage.reference().child(storagePath)
        let encrypted = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            ref.getData(maxSize: 200 * 1024 * 1024) { data, err in
                if let err {
                    KBLog.sync.kbError("PhotoRemoteStore.download: Storage getData FAILED path=\(storagePath) err=\(err.localizedDescription)")
                    cont.resume(throwing: err); return
                }
                KBLog.sync.kbDebug("PhotoRemoteStore.download: Storage getData OK encryptedBytes=\((data ?? Data()).count)")
                cont.resume(returning: data ?? Data())
            }
        }
        KBLog.sync.kbDebug("PhotoRemoteStore.download: decrypting encryptedBytes=\(encrypted.count) familyId=\(familyId)")
        let decrypted = try DocumentCryptoService.decrypt(encrypted, familyId: familyId, userId: userId)
        KBLog.sync.kbInfo("PhotoRemoteStore.download: decrypt OK decryptedBytes=\(decrypted.count)")
        return decrypted
    }
    
    // MARK: - Firestore metadata
    
    func upsertMetadata(dto: RemotePhotoDTO) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.sync.kbError("PhotoRemoteStore.upsertMetadata: not authenticated photoId=\(dto.id)")
            throw PhotoStoreError.notAuthenticated
        }
        KBLog.sync.kbInfo("PhotoRemoteStore.upsertMetadata: start photoId=\(dto.id) thumbPresent=\(dto.thumbnailBase64 != nil) duration=\(dto.videoDurationSeconds != nil ? String(format: "%.1f", dto.videoDurationSeconds!) : "nil")")
        let ref = db.collection("families").document(dto.familyId)
            .collection("photos").document(dto.id)
        var data: [String: Any] = [
            "fileName":    dto.fileName,
            "mimeType":    dto.mimeType,
            "fileSize":    dto.fileSize,
            "storagePath": dto.storagePath,
            "albumIdsRaw": dto.albumIdsRaw,
            "takenAt":     Timestamp(date: dto.takenAt),
            "isDeleted":   dto.isDeleted,
            "createdBy":   dto.createdBy,
            "updatedBy":   uid,
            "updatedAt":   FieldValue.serverTimestamp(),
            "createdAt":   FieldValue.serverTimestamp()
        ]
        if let v = dto.downloadURL           { data["downloadURL"]           = v }
        if let v = dto.thumbnailBase64       { data["thumbnailBase64"]       = v }
        if let v = dto.caption               { data["caption"]               = v }
        if let v = dto.videoDurationSeconds  { data["videoDurationSeconds"]  = v }
        try await ref.setData(data, merge: true)
        KBLog.sync.kbInfo("PhotoRemoteStore.upsertMetadata: Firestore write OK photoId=\(dto.id)")
    }
    
    func softDeletePhoto(familyId: String, photoId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw PhotoStoreError.notAuthenticated }
        try await db.collection("families").document(familyId)
            .collection("photos").document(photoId)
            .setData(["isDeleted": true, "updatedBy": uid,
                      "updatedAt": FieldValue.serverTimestamp()], merge: true)
    }
    
    /// Hard-delete di una foto/video:
    /// 1. Cancella il blob cifrato da Firebase Storage.
    /// 2. Hard-deletes il documento Firestore (delete reale, non isDeleted=true).
    ///
    /// Il trigger `onPhotoHardDeleted` lato Cloud Functions legge `before.fileSize`
    /// e sottrae i bytes da `stats/storage` — lo spazio viene liberato immediatamente.
    ///
    /// Se il blob è già assente su Storage (404) si procede comunque con il delete
    /// Firestore, in modo che device multipli non si blocchino a vicenda.
    func hardDeletePhoto(familyId: String, photoId: String, storagePath: String) async throws {
        // 1. Cancella il blob da Firebase Storage
        if !storagePath.isEmpty {
            do {
                try await storage.reference().child(storagePath).delete()
                KBLog.sync.kbInfo("hardDeletePhoto: Storage blob deleted path=\(storagePath)")
            } catch let err as NSError where
                        err.domain == StorageErrorDomain &&
                        err.code == StorageErrorCode.objectNotFound.rawValue {
                // Già assente (upload mai completato o rimosso da altro device) — non bloccante.
                KBLog.sync.kbInfo("hardDeletePhoto: blob already absent path=\(storagePath)")
            }
            // Qualsiasi altro errore Storage viene rilanciato → l'outbox riprova.
        }
        
        // 2. Hard-delete il documento Firestore
        // Non usiamo setData(isDeleted:true) — vogliamo un .delete() reale così
        // il trigger onPhotoHardDeleted si attiva e sottrae fileSize da usedBytes.
        try await db.collection("families").document(familyId)
            .collection("photos").document(photoId)
            .delete()
        KBLog.sync.kbInfo("hardDeletePhoto: Firestore doc deleted familyId=\(familyId) photoId=\(photoId)")
    }
    
    // MARK: - Realtime listener — photos
    
    func listenPhotos(
        familyId: String,
        onChange: @escaping ([PhotoRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        KBLog.sync.kbInfo("Photos listener attach familyId=\(familyId)")
        return db.collection("families").document(familyId)
            .collection("photos")
            .addSnapshotListener { snap, err in
                if let err { onError(err); return }
                guard let snap else { return }
                let changes: [PhotoRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document; let d = doc.data()
                    switch diff.type {
                    case .removed: return .remove(doc.documentID)
                    case .added, .modified:
                        return .upsert(RemotePhotoDTO(
                            id: doc.documentID, familyId: familyId,
                            fileName: d["fileName"] as? String ?? "",
                            mimeType: d["mimeType"] as? String ?? "image/jpeg",
                            fileSize: (d["fileSize"] as? NSNumber)?.int64Value ?? 0,
                            storagePath: d["storagePath"] as? String ?? "",
                            downloadURL: d["downloadURL"] as? String,
                            thumbnailBase64: d["thumbnailBase64"] as? String,
                            caption: d["caption"] as? String,
                            albumIdsRaw: d["albumIdsRaw"] as? String ?? "",
                            videoDurationSeconds: d["videoDurationSeconds"] as? Double, takenAt: (d["takenAt"] as? Timestamp)?.dateValue() ?? Date(),
                            createdAt: (d["createdAt"] as? Timestamp)?.dateValue(),
                            updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
                            createdBy: d["createdBy"] as? String ?? "",
                            updatedBy: d["updatedBy"] as? String ?? "",
                            isDeleted: d["isDeleted"] as? Bool ?? false
                        ))
                    }
                }
                KBLog.sync.kbDebug("PhotoRemoteStore.listenPhotos: snapshot changes=\(snap.documentChanges.count) emitting=\(changes.count) familyId=\(familyId)")
                if !changes.isEmpty { onChange(changes) }
            }
    }
    
    // MARK: - Albums CRUD
    
    func upsertAlbum(dto: RemoteAlbumDTO) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw PhotoStoreError.notAuthenticated }
        let ref = db.collection("families").document(dto.familyId)
            .collection("photoAlbums").document(dto.id)
        // familyId salvato esplicitamente — necessario per ricostruire il documento
        // correttamente su device che non hanno ancora l'album in locale.
        // createdAt usa SetOptions merge: non sovrascrivere se già presente.
        var data: [String: Any] = [
            "familyId":  dto.familyId,
            "title":     dto.title,
            "sortOrder": dto.sortOrder,
            "isDeleted": dto.isDeleted,
            "createdBy": dto.createdBy,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let v = dto.coverPhotoId { data["coverPhotoId"] = v }
        // Prima scrittura: imposta anche createdAt
        // Con merge: true, se il documento esiste già createdAt non viene toccato
        // perché usiamo setData con merge solo sui campi presenti — ma serverTimestamp
        // lo sovrascrive comunque. Usiamo una transazione per preservarlo.
        let snap = try await ref.getDocument()
        if !snap.exists {
            data["createdAt"] = FieldValue.serverTimestamp()
        }
        try await ref.setData(data, merge: true)
    }
    
    func softDeleteAlbum(familyId: String, albumId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw PhotoStoreError.notAuthenticated }
        try await db.collection("families").document(familyId)
            .collection("photoAlbums").document(albumId)
            .setData(["isDeleted": true, "updatedBy": uid,
                      "updatedAt": FieldValue.serverTimestamp()], merge: true)
    }
    
    func listenAlbums(
        familyId: String,
        onChange: @escaping ([AlbumRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        KBLog.sync.kbInfo("Albums listener attach familyId=\(familyId)")
        return db.collection("families").document(familyId)
            .collection("photoAlbums")
            .addSnapshotListener { snap, err in
                if let err { onError(err); return }
                guard let snap else { return }
                let changes: [AlbumRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document; let d = doc.data()
                    switch diff.type {
                    case .removed: return .remove(doc.documentID)
                    case .added, .modified:
                        return .upsert(RemoteAlbumDTO(
                            id: doc.documentID,
                            // Legge familyId dal documento (scritto dal fix upsertAlbum).
                            // Fallback al parametro per documenti scritti prima del fix.
                            familyId: d["familyId"] as? String ?? familyId,
                            title: d["title"] as? String ?? "",
                            coverPhotoId: d["coverPhotoId"] as? String,
                            sortOrder: d["sortOrder"] as? Int ?? 0,
                            createdBy: d["createdBy"] as? String ?? "",
                            updatedBy: d["updatedBy"] as? String ?? "",
                            createdAt: (d["createdAt"] as? Timestamp)?.dateValue(),
                            updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
                            isDeleted: d["isDeleted"] as? Bool ?? false
                        ))
                    }
                }
                KBLog.sync.kbDebug("Albums listener snapshot changes=\(snap.documentChanges.count) emitting=\(changes.count) familyId=\(familyId)")
                if !changes.isEmpty { onChange(changes) }
            }
    }
}

// MARK: - Errors

enum PhotoStoreError: LocalizedError {
    case notAuthenticated, uploadFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Utente non autenticato."
        case .uploadFailed:     return "Caricamento foto fallito."
        }
    }
}
