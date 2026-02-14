//
//  ChildSyncService.swift
//  KidBox
//
//  Created by vscocca on 12/02/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

/// Handles remote synchronization for `KBChild` entities.
///
/// This service writes directly to Firestore and is designed to be used
/// by a higher-level Sync layer (e.g. SyncCenter).
///
/// Conventions:
/// - Uses merge writes (`setData(..., merge: true)`).
/// - Implements soft delete (`isDeleted = true`) instead of hard delete.
/// - Timestamps are always written explicitly (no serverTimestamp here).
struct ChildSyncService {
    
    // MARK: - Dependencies
    
    private let db = Firestore.firestore()
    
    // MARK: - Upsert
    
    /// Creates or updates a child document in Firestore.
    ///
    /// Behavior (unchanged):
    /// - Writes full payload using merge=true.
    /// - Always sets `isDeleted = false`.
    /// - Uses local `createdAt` and `updatedAt` (no serverTimestamp).
    func upsert(child: KBChild) async throws {
        let fid = child.familyId
        let cid = child.id
        
        KBLog.sync.kbInfo("ChildSyncService upsert start childId=\(cid) familyId=\(fid ?? "nil")")
        
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
        
        if let ub = child.updatedBy {
            payload["updatedBy"] = ub
        }
        
        try await db
            .collection("families")
            .document(fid ?? "")
            .collection("children")
            .document(cid)
            .setData(payload, merge: true)
        
        KBLog.sync.kbDebug("ChildSyncService upsert completed childId=\(cid)")
    }
    
    // MARK: - Soft delete
    
    /// Soft deletes a child remotely.
    ///
    /// Behavior (unchanged):
    /// - Sets `isDeleted = true`.
    /// - Updates `updatedAt` to current Date().
    /// - Other devices will hard-delete locally during inbound sync.
    func softDeleteChild(familyId: String, childId: String, updatedBy: String?) async throws {
        KBLog.sync.kbInfo("ChildSyncService softDelete start childId=\(childId) familyId=\(familyId)")
        
        var payload: [String: Any] = [
            "isDeleted": true,
            "updatedAt": Timestamp(date: Date())
        ]
        
        if let updatedBy {
            payload["updatedBy"] = updatedBy
        }
        
        try await db
            .collection("families")
            .document(familyId)
            .collection("children")
            .document(childId)
            .setData(payload, merge: true)
        
        KBLog.sync.kbDebug("ChildSyncService softDelete completed childId=\(childId)")
    }
}
