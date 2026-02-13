//
//  DocumentStorageService.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseStorage

enum DocumentStorageServiceError: Error {
    case notAuthenticated
    case invalidData
    case missingURL
}

final class DocumentStorageService {
    private let storage = Storage.storage()
    
    /// Upload del file (PDF/immagine/etc) su Storage e ritorna downloadURL
    /// Upload di file GIÀ CIFRATO (no re-encryption)
    func upload(
        familyId: String,
        docId: String,
        fileName: String,
        originalMimeType: String,
        encryptedData: Data
    ) async throws -> (storagePath: String, downloadURL: String) {
        
        guard Auth.auth().currentUser?.uid != nil else {
            throw DocumentStorageServiceError.notAuthenticated
        }
        guard !encryptedData.isEmpty else {
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
        
        _ = try await ref.putDataAsync(encryptedData, metadata: metadata)
        let url = try await ref.downloadURL()
        return (storagePath: path, downloadURL: url.absoluteString)
    }
    
    func delete(path: String) async throws {
        guard let _ = Auth.auth().currentUser else {
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        let ref = Storage.storage().reference(withPath: path)
        try await ref.delete()
    }
}
