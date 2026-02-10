//
//  DocumentCategoryRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import OSLog

struct RemoteDocumentCategoryDTO {
    let id: String
    let familyId: String
    let title: String
    let sortOrder: Int
    let parentId: String?
    let isDeleted: Bool
    let updatedAt: Date?
    let updatedBy: String?
}

enum DocumentCategoryRemoteChange {
    case upsert(RemoteDocumentCategoryDTO)
    case remove(String)
}

final class DocumentCategoryRemoteStore {
    private var db: Firestore { Firestore.firestore() }
    
    // MARK: - OUTBOUND (push)
    
    func upsert(dto: RemoteDocumentCategoryDTO) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let ref = db.collection("families")
            .document(dto.familyId)
            .collection("documentCategories")
            .document(dto.id)
        
        var data: [String: Any] = [
            "familyId": dto.familyId,                       // ✅ utile e coerente
            "title": dto.title,
            "sortOrder": dto.sortOrder,
            "isDeleted": dto.isDeleted,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp(),
            
            // ✅ createdAt solo se non esiste già
            "createdAt": FieldValue.serverTimestamp()       // ⚠️ lo sistemiamo sotto con mergeFields
        ]
        
        if let parentId = dto.parentId {
            data["parentId"] = parentId
        } else {
            data["parentId"] = FieldValue.delete()
        }
        
        // ✅ trucco: scriviamo createdAt solo se il doc NON esiste già
        let snap = try await ref.getDocument()
        if snap.exists {
            data.removeValue(forKey: "createdAt")          // ✅ non toccare createdAt
        }
        
        try await ref.setData(data, merge: true)
    }
    
    func softDelete(familyId: String, categoryId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("documentCategories")
            .document(categoryId)
        
        try await ref.setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    //Hard Delete
    func delete(familyId: String, categoryId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("documentCategories")
            .document(categoryId)
        
        try await ref.delete()
    }
    
    // MARK: - INBOUND (realtime)
    
    func listenCategories(
        familyId: String,
        onChange: @escaping ([DocumentCategoryRemoteChange]) -> Void
    ) -> ListenerRegistration {
        
        db.collection("families")
            .document(familyId)
            .collection("documentCategories")
            .addSnapshotListener { snap, err in
                if let err {
                    KBLog.sync.error("DocCategories listener error: \(err.localizedDescription, privacy: .public)")
                    return
                }
                guard let snap else { return }
                
                let changes: [DocumentCategoryRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let data = doc.data()
                    
                    let dto = RemoteDocumentCategoryDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        title: data["title"] as? String ?? "Categoria",
                        sortOrder: data["sortOrder"] as? Int ?? 0,
                        parentId: data["parentId"] as? String,
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
