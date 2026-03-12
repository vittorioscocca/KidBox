//
//  KBFamilyPhoto.swift
//  KidBox
//

import Foundation
import SwiftData

/// SwiftData model for a single family photo or video.
///
/// Encryption model:
/// - Uses the per-family AES-256-GCM master key managed by `FamilyKeychainStore`.
/// - Same key used for documents (`DocumentCryptoService`) — synced across all family
///   members' devices via iCloud Keychain. Any member can decrypt any family photo.
/// - NO per-photo key is stored here; there is nothing to store.
/// - Firebase Storage receives only the encrypted blob (application/octet-stream).
/// - Firestore receives only metadata + thumbnail (no key, no raw pixels).
@Model
final class KBFamilyPhoto {
    
    // MARK: - Identity
    @Attribute(.unique) var id: String
    var familyId: String
    
    // MARK: - File metadata
    var fileName: String
    var mimeType: String        // "image/jpeg" | "image/heic" | "image/png" | "video/mp4"
    var fileSize: Int64
    
    // MARK: - Storage paths
    /// Firebase Storage: families/{familyId}/photos/{id}/original.enc
    var storagePath: String
    /// Download URL returned by Storage after upload
    var downloadURL: String?
    /// Absolute path of the locally cached decrypted file (Caches/KBPhotos/{id})
    var localPath: String?
    
    // MARK: - Display
    /// Small JPEG thumbnail stored inside the Firestore doc — NOT encrypted, for fast grid rendering
    var thumbnailBase64: String?
    var caption: String?
    /// Durata in secondi — valorizzato solo per i video (nil per le immagini).
    var videoDurationSeconds: Double?
    
    // MARK: - Dates
    var takenAt: Date       // EXIF date or upload time
    var createdAt: Date
    var updatedAt: Date
    var createdBy: String   // Firebase UID
    var updatedBy: String
    
    // MARK: - Album membership
    var albumIdsRaw: String   // "albumId1,albumId2"
    
    // MARK: - Sync
    var isDeleted: Bool
    var syncStateRaw: Int
    var lastSyncError: String?
    
    // MARK: - Init
    init(
        id: String = UUID().uuidString,
        familyId: String,
        fileName: String,
        mimeType: String = "image/jpeg",
        fileSize: Int64 = 0,
        storagePath: String = "",
        downloadURL: String? = nil,
        localPath: String? = nil,
        thumbnailBase64: String? = nil,
        caption: String? = nil,
        videoDurationSeconds: Double? = nil,
        takenAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        createdBy: String,
        updatedBy: String,
        albumIdsRaw: String = "",
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.storagePath = storagePath
        self.downloadURL = downloadURL
        self.localPath = localPath
        self.thumbnailBase64 = thumbnailBase64
        self.caption = caption
        self.videoDurationSeconds = videoDurationSeconds
        self.takenAt = takenAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.albumIdsRaw = albumIdsRaw
        self.isDeleted = isDeleted
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
    }
    
    // MARK: - Computed
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .pendingUpsert }
        set { syncStateRaw = newValue.rawValue }
    }
    
    var albumIds: [String] {
        get { albumIdsRaw.isEmpty ? [] : albumIdsRaw.split(separator: ",").map(String.init) }
        set { albumIdsRaw = newValue.joined(separator: ",") }
    }
    
    var thumbnailData: Data? { thumbnailBase64.flatMap { Data(base64Encoded: $0) } }
    
    /// True se il record è un video — controlla mimeType E estensione del fileName
    /// come fallback per record caricati prima dell'aggiunta del supporto video.
    var isVideo: Bool {
        mimeType.hasPrefix("video/") ||
        ["mp4", "mov", "m4v"].contains(fileName.split(separator: ".").last?.lowercased() ?? "")
    }
}




