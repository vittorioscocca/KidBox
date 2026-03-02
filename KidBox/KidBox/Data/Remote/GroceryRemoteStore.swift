//
//  GroceryRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

// MARK: - DTOs

struct GroceryRemoteDTO {
    let id: String
    let familyId: String
    let name: String
    let category: String?
    let notes: String?
    let isPurchased: Bool
    let isDeleted: Bool
    let purchasedAt: Date?
    let purchasedBy: String?
    let updatedAt: Date?
    let updatedBy: String?
    let createdBy: String?
}

enum GroceryRemoteChange {
    case upsert(GroceryRemoteDTO)
    case remove(String)
}

// MARK: - Remote store

final class GroceryRemoteStore {
    
    private var db: Firestore { Firestore.firestore() }
    
    // Percorso Firestore: families/{familyId}/groceries/{itemId}
    private func ref(familyId: String, itemId: String) -> DocumentReference {
        db.collection("families")
            .document(familyId)
            .collection("groceries")
            .document(itemId)
    }
    
    private func col(familyId: String) -> CollectionReference {
        db.collection("families")
            .document(familyId)
            .collection("groceries")
    }
    
    // MARK: - Upsert
    
    func upsert(item: KBGroceryItem) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let snap = try await ref(familyId: item.familyId, itemId: item.id).getDocument()
        let isNew = !snap.exists
        
        var data: [String: Any] = [
            "name": item.name,
            "isPurchased": item.isPurchased,
            "isDeleted": false,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        if isNew { data["createdAt"] = FieldValue.serverTimestamp() }
        
        data["category"] = item.category as Any
        data["notes"] = item.notes as Any
        data["purchasedAt"] = item.purchasedAt.map { Timestamp(date: $0) } as Any
        data["purchasedBy"] = item.purchasedBy as Any
        
        if isNew { data["createdBy"] = item.createdBy ?? uid }
        
        try await ref(familyId: item.familyId, itemId: item.id).setData(data, merge: true)
        KBLog.sync.kbInfo("[GroceryRemote] upsert OK id=\(item.id) familyId=\(item.familyId)")
    }
    
    // MARK: - Soft delete
    
    func softDelete(itemId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        try await ref(familyId: familyId, itemId: itemId).setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.sync.kbInfo("[GroceryRemote] softDelete OK id=\(itemId) familyId=\(familyId)")
    }
    
    // MARK: - Realtime listener
    
    func listenGroceries(
        familyId: String,
        onChange: @escaping ([GroceryRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        
        KBLog.sync.kbInfo("[GroceryRemote] listenGroceries ATTACH familyId=\(familyId)")
        
        return col(familyId: familyId)
            .whereField("isDeleted", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[GroceryRemote] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else { return }
                
                KBLog.sync.kbDebug("[GroceryRemote] snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count) fromCache=\(snap.metadata.isFromCache)")
                
                let changes: [GroceryRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let d = doc.data()
                    
                    guard let name = d["name"] as? String, !name.isEmpty else {
                        KBLog.sync.kbDebug("[GroceryRemote] decode FAIL docId=\(doc.documentID)")
                        return nil
                    }
                    
                    let dto = GroceryRemoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        name: name,
                        category: d["category"] as? String,
                        notes: d["notes"] as? String,
                        isPurchased: d["isPurchased"] as? Bool ?? false,
                        isDeleted: d["isDeleted"] as? Bool ?? false,
                        purchasedAt: (d["purchasedAt"] as? Timestamp)?.dateValue(),
                        purchasedBy: d["purchasedBy"] as? String,
                        updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
                        updatedBy: d["updatedBy"] as? String,
                        createdBy: d["createdBy"] as? String
                    )
                    
                    switch diff.type {
                    case .added, .modified: return .upsert(dto)
                    case .removed:          return .remove(doc.documentID)
                    }
                }
                
                if !changes.isEmpty { onChange(changes) }
            }
    }
}
