//
//  DocumentUploadService.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct RemoteDocumentMeta {
    let familyId: String
    let childId: String?
    let categoryId: String?
    let title: String
    let fileName: String
    let mimeType: String
    let fileSize: Int64
}

final class DocumentUploadService {
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    
    func uploadDocument(
        familyId: String,
        documentId: String,
        storagePath: String,
        data: Data,
        mimeType: String,
        meta: RemoteDocumentMeta
    ) async throws -> String {
        
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Storage
        let ref = storage.reference(withPath: storagePath)
        let md = StorageMetadata()
        md.contentType = mimeType
        _ = try await ref.putDataAsync(data, metadata: md)
        
        let url = try await ref.downloadURL()
        let urlString = url.absoluteString
        
        // Firestore metadata
        var payload: [String: Any] = [
            "familyId": meta.familyId,
            "title": meta.title,
            "fileName": meta.fileName,
            "mimeType": meta.mimeType,
            "fileSize": meta.fileSize,
            "storagePath": storagePath,
            "downloadURL": urlString,
            "isDeleted": false,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        if let childId = meta.childId {
            payload["childId"] = childId
        } else {
            payload["childId"] = FieldValue.delete()
        }
        
        if let categoryId = meta.categoryId {
            payload["categoryId"] = categoryId
        } else {
            payload["categoryId"] = FieldValue.delete()
        }
        
        try await db.collection("families")
            .document(familyId)
            .collection("documents")
            .document(documentId)
            .setData(payload, merge: true)
        
        return urlString
    }
}
