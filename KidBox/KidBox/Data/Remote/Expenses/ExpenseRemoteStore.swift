//
//  ExpenseRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 23/03/26.
//

import Foundation
import FirebaseFirestore

// MARK: - DTO

struct RemoteExpenseDTO {
    let id:                 String
    let familyId:           String
    let title:              String
    let amount:             Double
    let date:               Date
    let categoryId:         String?
    let notes:              String?
    let attachedDocumentId: String?
    let isDeleted:          Bool
    let createdByUid:       String?
    let updatedBy:          String
    let createdAt:          Date
    let updatedAt:          Date
}

// MARK: - Change type (per il listener realtime)

enum ExpenseRemoteChange {
    case upsert(RemoteExpenseDTO)
    case remove(String)          // documentId Firestore
}

// MARK: - Store

final class ExpenseRemoteStore {
    
    private let db = Firestore.firestore()
    
    // MARK: - Collection ref
    
    /// `families/{familyId}/expenses`
    private func col(familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("expenses")
    }
    
    // MARK: - Upsert
    
    func upsert(dto: RemoteExpenseDTO) async throws {
        var data: [String: Any] = [
            "id":        dto.id,
            "familyId":  dto.familyId,
            "title":     dto.title,
            "amount":    dto.amount,
            "isDeleted": dto.isDeleted,
            "updatedBy": dto.updatedBy,
            "date":      Timestamp(date: dto.date),
            "createdAt": Timestamp(date: dto.createdAt),
            "updatedAt": Timestamp(date: dto.updatedAt),
        ]
        
        // Campi opzionali: quando nil eliminiamo la chiave così Firestore rimane pulito
        data["categoryId"]         = dto.categoryId         ?? FieldValue.delete()
        data["notes"]              = dto.notes               ?? FieldValue.delete()
        data["attachedDocumentId"] = dto.attachedDocumentId  ?? FieldValue.delete()
        data["createdByUid"]       = dto.createdByUid        ?? FieldValue.delete()
        
        try await col(familyId: dto.familyId)
            .document(dto.id)
            .setData(data, merge: true)
    }
    
    // MARK: - Soft delete
    
    func softDelete(familyId: String, expenseId: String) async throws {
        try await col(familyId: familyId)
            .document(expenseId)
            .updateData([
                "isDeleted": true,
                "updatedAt": Timestamp(date: Date())
            ])
    }
    
    // MARK: - Realtime listener (family-wide)
    
    func listen(
        familyId: String,
        onChange: @escaping ([ExpenseRemoteChange]) -> Void,
        onError:  @escaping (Error) -> Void
    ) -> ListenerRegistration {
        col(familyId: familyId)
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                guard let snapshot else { return }
                
                let changes: [ExpenseRemoteChange] = snapshot.documentChanges.compactMap { diff in
                    if diff.type == .removed {
                        return .remove(diff.document.documentID)
                    }
                    guard let dto = ExpenseRemoteStore.parseDTO(doc: diff.document) else { return nil }
                    return .upsert(dto)
                }
                
                // FIX 3: Allineato a VisitRemoteStore — non invocare onChange con
                // un array vuoto. Evita processing inutile e potenziali side-effect
                // nel SyncCenter quando lo snapshot non porta novità reali.
                guard !changes.isEmpty else { return }
                onChange(changes)
            }
    }
    
    // MARK: - Parse
    
    static func parseDTO(doc: QueryDocumentSnapshot) -> RemoteExpenseDTO? {
        let d = doc.data()
        
        guard
            let id       = d["id"]       as? String,
            let familyId = d["familyId"] as? String,
            let title    = d["title"]    as? String,
            let amount   = d["amount"]   as? Double,
            let dateTS   = d["date"]     as? Timestamp
        else { return nil }
        
        func ts(_ key: String) -> Date? {
            (d[key] as? Timestamp)?.dateValue()
        }
        
        return RemoteExpenseDTO(
            id:                 id,
            familyId:           familyId,
            title:              title,
            amount:             amount,
            date:               dateTS.dateValue(),
            categoryId:         d["categoryId"]         as? String,
            notes:              d["notes"]               as? String,
            attachedDocumentId: d["attachedDocumentId"]  as? String,
            isDeleted:          d["isDeleted"]           as? Bool   ?? false,
            createdByUid:       d["createdByUid"]        as? String,
            updatedBy:          d["updatedBy"]           as? String ?? "",
            createdAt:          ts("createdAt") ?? Date(),
            updatedAt:          ts("updatedAt") ?? Date()
        )
    }
}
