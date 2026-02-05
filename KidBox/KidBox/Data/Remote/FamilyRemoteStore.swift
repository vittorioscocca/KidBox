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
    let ownerUid: String
}

struct RemoteChildPayload {
    let id: String
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
            throw NSError(domain: "KidBox", code: -100, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let familyRef = db.collection("families").document(family.id)
        
        let batch = db.batch()
        
        batch.setData([
            "name": family.name,
            "ownerUid": uid,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: familyRef)
        
        let childRef = familyRef.collection("children").document(child.id)
        var childData: [String: Any] = [
            "name": child.name,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let birthDate = child.birthDate {
            childData["birthDate"] = Timestamp(date: birthDate)
        }
        batch.setData(childData, forDocument: childRef)
        
        let memberRef = familyRef.collection("members").document(uid)
        batch.setData([
            "uid": uid,
            "role": "owner",
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: memberRef)
        
        try await batch.commit()
        KBLog.sync.info("Firestore family created id=\(family.id, privacy: .public)")
    }
}
