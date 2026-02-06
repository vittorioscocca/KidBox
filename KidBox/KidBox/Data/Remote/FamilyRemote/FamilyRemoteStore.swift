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

struct RemoteFamilyPayload {
    let id: String
    let name: String
    let ownerUid: String // puoi passare "ignored", viene sovrascritto con uid corrente
}

struct RemoteChildPayload {
    let id: String
    let name: String
    let birthDate: Date?
}

struct RemoteFamilyUpdatePayload {
    let familyId: String
    let name: String
}

struct RemoteChildUpdatePayload {
    let familyId: String
    let childId: String
    let name: String
    let birthDate: Date?
}

final class FamilyRemoteStore {
    private var db: Firestore { Firestore.firestore() }
    
    func createFamilyWithChild(
        family: RemoteFamilyPayload,
        child: RemoteChildPayload
    ) async throws {
        
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -100,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let familyRef = db.collection("families").document(family.id)
        
        // ---- BATCH 1: family + member + membership index
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
        
        // ---- WRITE 2: child (ora isMember(familyId) è TRUE)
        let childRef = familyRef.collection("children").document(child.id)
        
        var childData: [String: Any] = [
            "name": child.name,
            "isDeleted": false,
            "createdAt": FieldValue.serverTimestamp(),
            // ✅ importantissimo: così gli update inbound hanno sempre un timestamp
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        if let birthDate = child.birthDate {
            childData["birthDate"] = Timestamp(date: birthDate)
        }
        
        try await childRef.setData(childData, merge: false)
        
        KBLog.sync.info("Firestore family created id=\(family.id, privacy: .public)")
    }
}

extension FamilyRemoteStore {
    
    func updateFamilyAndChild(
        family: RemoteFamilyUpdatePayload,
        child: RemoteChildUpdatePayload
    ) async throws {
        
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -100, userInfo: [
                NSLocalizedDescriptionKey: "Not authenticated"
            ])
        }
        
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
            // se vuoi “cancellare” la birthDate su Firestore quando togli il toggle
            childData["birthDate"] = FieldValue.delete()
        }
        
        batch.setData(childData, forDocument: childRef, merge: true)
        
        try await batch.commit()
        KBLog.sync.info("Firestore family+child updated familyId=\(family.familyId, privacy: .public) childId=\(child.childId, privacy: .public)")
    }
}
