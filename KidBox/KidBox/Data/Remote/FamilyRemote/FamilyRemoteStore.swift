//
//  FamilyRemoteStore.swift.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

// MARK: - Payloads (Outbound)

/// Payload for creating a family.
/// `ownerUid` is ignored and overwritten with the current authenticated uid.
struct RemoteFamilyPayload {
    let id: String
    let name: String
    let ownerUid: String
}

/// Payload for creating a child under a family.
struct RemoteChildPayload {
    let id: String
    let name: String
    let birthDate: Date?
}

/// Payload for updating a family.
struct RemoteFamilyUpdatePayload {
    let familyId: String
    let name: String
}

/// Payload for updating a child.
struct RemoteChildUpdatePayload {
    let familyId: String
    let childId: String
    let name: String
    let birthDate: Date?
}

// MARK: - Remote store

/// Firestore remote store for creating/updating families and children.
///
/// Responsibilities:
/// - Create a family + owner member doc + membership index (batch)
/// - Create the initial child document after membership exists
/// - Update family + child in one batch
///
/// Notes:
/// - Requires authenticated user.
/// - Uses server timestamps for createdAt/updatedAt fields.
final class FamilyRemoteStore {
    
    private var db: Firestore { Firestore.firestore() }
    
    /// Creates a family with its initial child.
    ///
    /// Flow (unchanged):
    /// 1) Auth check
    /// 2) Batch #1:
    ///    - families/{familyId}
    ///    - families/{familyId}/members/{uid} as owner
    ///    - users/{uid}/memberships/{familyId}
    /// 3) Write #2 (after membership exists):
    ///    - families/{familyId}/children/{childId}
    func createFamilyWithChild(
        family: RemoteFamilyPayload,
        child: RemoteChildPayload
    ) async throws {
        
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("createFamilyWithChild failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -100,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        KBLog.sync.kbInfo("Creating family started familyId=\(family.id)")
        
        let familyRef = db.collection("families").document(family.id)
        
        // ---- BATCH 1: family + member + membership index
        KBLog.sync.kbDebug("Batch#1: family + member + membership index")
        
        let batch1 = db.batch()
        
        batch1.setData([
            "name": family.name,
            "ownerUid": uid,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: familyRef)
        
        let memberRef = familyRef.collection("members").document(uid)
        batch1.setData([
            "uid": uid,
            "role": "owner",
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: memberRef)
        
        let membershipRef = db.collection("users")
            .document(uid)
            .collection("memberships")
            .document(family.id)
        
        batch1.setData([
            "familyId": family.id,
            "role": "owner",
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: membershipRef)
        
        try await batch1.commit()
        KBLog.sync.kbInfo("Batch#1 committed familyId=\(family.id)")
        
        // ---- WRITE 2: child (now membership exists)
        KBLog.sync.kbDebug("Write#2: child document")
        
        let childRef = familyRef.collection("children").document(child.id)
        
        var childData: [String: Any] = [
            "name": child.name,
            "isDeleted": false,
            "createdAt": FieldValue.serverTimestamp(),
            // ensure inbound updates always have a timestamp
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        if let birthDate = child.birthDate {
            childData["birthDate"] = Timestamp(date: birthDate)
        }
        
        try await childRef.setData(childData, merge: false)
        
        KBLog.sync.kbInfo("Family created completed familyId=\(family.id) childId=\(child.id)")
    }
}

extension FamilyRemoteStore {
    
    /// Updates family and child documents in a single batch.
    ///
    /// Flow (unchanged):
    /// 1) Auth check
    /// 2) Batch:
    ///    - families/{familyId} (merge)
    ///    - families/{familyId}/children/{childId} (merge)
    ///    - birthDate is set or deleted depending on payload
    func updateFamilyAndChild(
        family: RemoteFamilyUpdatePayload,
        child: RemoteChildUpdatePayload
    ) async throws {
        
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("updateFamilyAndChild failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -100,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        KBLog.sync.kbInfo("Updating family+child started familyId=\(family.familyId) childId=\(child.childId)")
        
        let familyRef = db.collection("families").document(family.familyId)
        let childRef  = familyRef.collection("children").document(child.childId)
        
        let batch = db.batch()
        
        // family doc
        batch.setData([
            "name": family.name,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: familyRef, merge: true)
        
        // child doc
        var childData: [String: Any] = [
            "name": child.name,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        if let birthDate = child.birthDate {
            childData["birthDate"] = Timestamp(date: birthDate)
        } else {
            // delete birthDate if user removed it
            childData["birthDate"] = FieldValue.delete()
        }
        
        batch.setData(childData, forDocument: childRef, merge: true)
        
        try await batch.commit()
        
        KBLog.sync.kbInfo("Updating family+child completed familyId=\(family.familyId) childId=\(child.childId)")
    }
}
