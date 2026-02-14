//
//  DocumentStorageService.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseStorage
import OSLog

/// Errors thrown by `DocumentStorageService`.
enum DocumentStorageServiceError: Error {
    case notAuthenticated
    case invalidData
    case missingURL
}

/// Firebase Storage service for encrypted document blobs.
///
/// Responsibilities:
/// - Upload encrypted data (already encrypted by app) to Firebase Storage
/// - Attach metadata describing encryption and original file properties
/// - Return both `storagePath` and `downloadURL`
/// - Delete a blob by its Storage path
///
/// Security notes:
/// - The service expects `encryptedData` (ciphertext). It does not re-encrypt.
/// - Never log file contents, tokens, or full URLs.
/// - Prefer logging ids and sizes only.
final class DocumentStorageService {
    
    private let storage = Storage.storage()
    
    /// Uploads an encrypted file to Firebase Storage and returns `(storagePath, downloadURL)`.
    ///
    /// Behavior (unchanged):
    /// - Requires an authenticated user.
    /// - Requires non-empty `encryptedData`.
    /// - Stores the file under:
    ///   `families/{familyId}/documents/{docId}/{fileName}.kbenc`
    /// - Sets `contentType = application/octet-stream` (encrypted blob).
    /// - Writes metadata indicating encryption + original mime/name.
    ///
    /// - Returns:
    ///   - `storagePath`: the path used in Firebase Storage (stable identifier)
    ///   - `downloadURL`: absolute URL string to download the blob
    func upload(
        familyId: String,
        docId: String,
        fileName: String,
        originalMimeType: String,
        encryptedData: Data
    ) async throws -> (storagePath: String, downloadURL: String) {
        
        KBLog.sync.kbInfo("Storage upload started familyId=\(familyId) docId=\(docId) bytes=\(encryptedData.count)")
        
        guard Auth.auth().currentUser?.uid != nil else {
            KBLog.auth.kbError("Storage upload failed: not authenticated")
            throw DocumentStorageServiceError.notAuthenticated
        }
        
        guard !encryptedData.isEmpty else {
            KBLog.sync.kbError("Storage upload failed: invalidData (empty encryptedData)")
            throw DocumentStorageServiceError.invalidData
        }
        
        let safeFileName = fileName.isEmpty ? "file.bin" : fileName
        let encryptedFileName = safeFileName + ".kbenc"
        
        let path = "families/\(familyId)/documents/\(docId)/\(encryptedFileName)"
        let ref = storage.reference(withPath: path)
        
        let metadata = StorageMetadata()
        metadata.contentType = "application/octet-stream"
        metadata.customMetadata = [
            "kb_encrypted": "1",
            "kb_alg": "AES-GCM",
            "kb_orig_mime": originalMimeType,
            "kb_orig_name": safeFileName
        ]
        
        KBLog.sync.kbDebug("Uploading encrypted blob to Storage (path set)")
        _ = try await ref.putDataAsync(encryptedData, metadata: metadata)
        
        KBLog.sync.kbDebug("Upload OK, requesting downloadURL")
        let url = try await ref.downloadURL()
        
        KBLog.sync.kbInfo("Storage upload completed familyId=\(familyId) docId=\(docId)")
        return (storagePath: path, downloadURL: url.absoluteString)
    }
    
    /// Deletes a blob from Firebase Storage given its path.
    ///
    /// - Parameter path: Storage path (e.g. `families/{familyId}/documents/{docId}/file.kbenc`)
    func delete(path: String) async throws {
        KBLog.sync.kbInfo("Storage delete started pathPresent=\(!path.isEmpty)")
        
        guard Auth.auth().currentUser != nil else {
            KBLog.auth.kbError("Storage delete failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            KBLog.sync.kbError("Storage delete failed: missing path")
            throw NSError(
                domain: "KidBox",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Missing storage path"]
            )
        }
        
        let ref = Storage.storage().reference(withPath: path)
        try await ref.delete()
        
        KBLog.sync.kbInfo("Storage delete completed")
    }
}
