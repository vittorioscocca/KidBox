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
    func upload(
        familyId: String,
        docId: String,
        fileName: String,
        mimeType: String,
        data: Data
    ) async throws -> (storagePath: String, downloadURL: String) {
        
        guard Auth.auth().currentUser?.uid != nil else {
            throw DocumentStorageServiceError.notAuthenticated
        }
        guard !data.isEmpty else {
            throw DocumentStorageServiceError.invalidData
        }
        
        let safeFileName = fileName.isEmpty ? "file.bin" : fileName
        let path = "families/\(familyId)/docs/\(docId)/\(safeFileName)"
        let ref = storage.reference(withPath: path)
        
        let metadata = StorageMetadata()
        metadata.contentType = mimeType
        
        _ = try await ref.putDataAsync(data, metadata: metadata)
        
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
