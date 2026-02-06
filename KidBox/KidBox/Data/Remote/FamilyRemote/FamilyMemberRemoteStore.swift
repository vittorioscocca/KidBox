//
//  FamilyMemberRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

struct FamilyMemberRemoteDTO {
    let id: String          // docId (di solito uid)
    let familyId: String
    let userId: String
    let role: String
    
    let displayName: String?
    let email: String?
    let photoURL: String?
    
    let updatedAt: Date?
    let updatedBy: String?
    let isDeleted: Bool
}

enum FamilyMemberRemoteChange {
    case upsert(FamilyMemberRemoteDTO)
    case remove(String)
}

final class FamilyMemberRemoteStore {
    private var db: Firestore { Firestore.firestore() }
    
    func listenMembers(
        familyId: String,
        onChange: @escaping ([FamilyMemberRemoteChange]) -> Void
    ) -> ListenerRegistration {
        
        db.collection("families")
            .document(familyId)
            .collection("members")
            .addSnapshotListener { snap, err in
                if let err {
                    KBLog.sync.error("Members listener error: \(err.localizedDescription, privacy: .public)")
                    return
                }
                guard let snap else { return }
                
                let changes: [FamilyMemberRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let data = doc.data()
                    
                    let dto = FamilyMemberRemoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        userId: data["uid"] as? String ?? doc.documentID,
                        role: data["role"] as? String ?? "member",
                        displayName: data["displayName"] as? String,
                        email: data["email"] as? String,
                        photoURL: data["photoURL"] as? String,
                        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue(),
                        updatedBy: data["updatedBy"] as? String,
                        isDeleted: data["isDeleted"] as? Bool ?? false
                    )
                    
                    switch diff.type {
                    case .added, .modified: return .upsert(dto)
                    case .removed: return .remove(doc.documentID)
                    }
                }
                
                if !changes.isEmpty { onChange(changes) }
            }
    }
    
    /// Ensures the current user's member doc has profile fields populated.
    func upsertMyMemberProfileIfNeeded(familyId: String) async {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("members")
            .document(uid)
        
        var data: [String: Any] = [
            "uid": uid,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp(),
            "isDeleted": false
        ]
        
        if let name = user.displayName, !name.isEmpty { data["displayName"] = name }
        if let email = user.email, !email.isEmpty { data["email"] = email }
        if let url = user.photoURL?.absoluteString, !url.isEmpty { data["photoURL"] = url }
        
        // merge=true: non rompe il ruolo esistente
        do {
            try await ref.setData(data, merge: true)
        } catch {
            KBLog.sync.error("upsertMyMemberProfileIfNeeded failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
