//
//  DocumentRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import OSLog

struct RemoteDocumentDTO {
    let id: String
    let familyId: String
    let childId: String?
    let categoryId: String
    
    let title: String
    let fileName: String
    let mimeType: String
    let fileSize: Int
    
    let storagePath: String
    let downloadURL: String?
    
    let isDeleted: Bool
    let updatedAt: Date?
    let updatedBy: String?
}

enum DocumentRemoteChange {
    case upsert(RemoteDocumentDTO)
    case remove(String)
}

final class DocumentRemoteStore {
    private var db: Firestore { Firestore.firestore() }
    
    func upsert(dto: RemoteDocumentDTO) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let ref = db.collection("families")
            .document(dto.familyId)
            .collection("documents")
            .document(dto.id)
        
        var data: [String: Any] = [
            "categoryId": dto.categoryId,
            "title": dto.title,
            "fileName": dto.fileName,
            "mimeType": dto.mimeType,
            "fileSize": dto.fileSize,
            "storagePath": dto.storagePath,
            "isDeleted": dto.isDeleted,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        if let childId = dto.childId { data["childId"] = childId } else { data["childId"] = FieldValue.delete() }
        if let downloadURL = dto.downloadURL { data["downloadURL"] = downloadURL }
        
        try await ref.setData(data, merge: true)
    }
    
    func softDelete(familyId: String, docId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("documents")
            .document(docId)
        
        try await ref.setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func delete(familyId: String, docId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("documents")
            .document(docId)
        
        try await ref.delete()
    }
    
    func listenDocuments(
        familyId: String,
        onChange: @escaping ([DocumentRemoteChange]) -> Void
    ) -> ListenerRegistration {
        
        db.collection("families")
            .document(familyId)
            .collection("documents")
            .addSnapshotListener { snap, err in
                if let err {
                    print("❌ DOC LISTENER ERROR:", err.localizedDescription)
                    KBLog.sync.error("Documents listener error: \(err.localizedDescription, privacy: .public)")
                    return
                }
                guard let snap else { return }
                print("📩 DOC SNAP size =", snap.documents.count, "changes =", snap.documentChanges.count)
                
                let changes: [DocumentRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let data = doc.data()
                    
                    let dto = RemoteDocumentDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        childId: data["childId"] as? String,
                        categoryId: data["categoryId"] as? String ?? "",
                        title: data["title"] as? String ?? "",
                        fileName: data["fileName"] as? String ?? "",
                        mimeType: data["mimeType"] as? String ?? "application/octet-stream",
                        fileSize: data["fileSize"] as? Int ?? 0,
                        storagePath: data["storagePath"] as? String ?? "",
                        downloadURL: data["downloadURL"] as? String,
                        isDeleted: data["isDeleted"] as? Bool ?? false,
                        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue(),
                        updatedBy: data["updatedBy"] as? String
                    )
                    
                    switch diff.type {
                    case .added, .modified: return .upsert(dto)
                    case .removed: return .remove(doc.documentID)
                    }
                }
                
                if !changes.isEmpty { onChange(changes) }
            }
    }
}
