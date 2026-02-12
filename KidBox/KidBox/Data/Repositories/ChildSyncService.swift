//
//  ChildSyncService.swift
//  KidBox
//
//  Created by vscocca on 12/02/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct ChildSyncService {
    
    private let db = Firestore.firestore()
    
    func upsert(child: KBChild) async throws {
        let fid = child.familyId
        let cid = child.id
        
        var payload: [String: Any] = [
            "id": cid,
            "familyId": fid ?? "",
            "name": child.name,
            "isDeleted": false,
            "createdBy": child.createdBy,
            "createdAt": Timestamp(date: child.createdAt)
        ]
        
        if let birth = child.birthDate {
            payload["birthDate"] = Timestamp(date: birth)
        }
        
        let updatedAt = child.updatedAt ?? Date()
        payload["updatedAt"] = Timestamp(date: updatedAt)
        if let ub = child.updatedBy { payload["updatedBy"] = ub }
        
        try await db
            .collection("families")
            .document(fid ?? "")
            .collection("children")
            .document(cid)
            .setData(payload, merge: true)
    }
    
    /// soft delete remoto (così gli altri device cancellano in inbound)
    func softDeleteChild(familyId: String, childId: String, updatedBy: String?) async throws {
        var payload: [String: Any] = [
            "isDeleted": true,
            "updatedAt": Timestamp(date: Date())
        ]
        if let updatedBy { payload["updatedBy"] = updatedBy }
        
        try await db
            .collection("families")
            .document(familyId)
            .collection("children")
            .document(childId)
            .setData(payload, merge: true)
    }
}
