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

/// DTO representing a family member document stored in Firestore.
struct FamilyMemberRemoteDTO {
    let id: String          // docId (usually uid)
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

/// Realtime change types for family members.
enum FamilyMemberRemoteChange {
    case upsert(FamilyMemberRemoteDTO)
    case remove(String)
}

/// Firestore remote store for family members.
///
/// Responsibilities:
/// - INBOUND: listen to realtime updates under `families/{familyId}/members`.
/// - OUTBOUND: best-effort upsert of the current user's profile fields into their member doc.
///
/// Notes:
/// - Listener maps `.added/.modified` → `.upsert`, `.removed` → `.remove` (unchanged).
/// - `upsertMyMemberProfileIfNeeded` merges fields and does not overwrite role (merge=true).
final class FamilyMemberRemoteStore {
    
    private var db: Firestore { Firestore.firestore() }
    
    // MARK: - INBOUND (Realtime)
    
    /// Starts a realtime listener for family members.
    ///
    /// - Parameters:
    ///   - familyId: Family identifier.
    ///   - onChange: Callback invoked with mapped changes.
    /// - Returns: Firestore `ListenerRegistration` used to stop listening.
    func listenMembers(
        familyId: String,
        onChange: @escaping ([FamilyMemberRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        
        KBLog.sync.kbInfo("Members listener attach familyId=\(familyId)")
        
        return db.collection("families")
            .document(familyId)
            .collection("members")
            .addSnapshotListener { snap, err in
                if let err {
                    KBLog.sync.kbError("Members listener error: \(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else {
                    KBLog.sync.kbDebug("Members listener snapshot nil")
                    return
                }
                
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
                    case .added, .modified:
                        return .upsert(dto)
                    case .removed:
                        return .remove(doc.documentID)
                    }
                }
                
                if !changes.isEmpty {
                    KBLog.sync.kbDebug("Members listener changes=\(changes.count)")
                    onChange(changes)
                }
            }
    }
    
    // MARK: - OUTBOUND (Profile hydration)
    
    /// Ensures the current user's member doc has profile fields populated.
    ///
    /// - Parameter displayName: Il nome canonico da `KBUserProfile` (firstName + lastName).
    ///   Se nil o vuoto, si usa `Auth.currentUser.displayName` come fallback.
    ///   Passare sempre il valore da SwiftData per evitare che Firebase Auth
    ///   (che non viene aggiornato al cambio profilo) sovrascriva il nome corretto.
    func upsertMyMemberProfileIfNeeded(familyId: String, displayName: String? = nil) async {
        guard let user = Auth.auth().currentUser else {
            KBLog.auth.kbDebug("upsertMyMemberProfileIfNeeded skipped: no authenticated user")
            return
        }
        
        let uid = user.uid
        KBLog.sync.kbInfo("Upserting my member profile (merge) familyId=\(familyId)")
        
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
        
        // Priorità: nome passato da KBUserProfile > Auth.currentUser.displayName
        // Auth.currentUser.displayName NON viene aggiornato quando l'utente cambia
        // il nome nell'app, quindi usarlo causerebbe il ripristino del nome vecchio.
        let resolvedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = resolvedName, !name.isEmpty, name != "Utente" {
            data["displayName"] = name
        } else if let name = user.displayName, !name.isEmpty {
            data["displayName"] = name
        }
        
        if let email = user.email, !email.isEmpty { data["email"] = email }
        if let url = user.photoURL?.absoluteString, !url.isEmpty { data["photoURL"] = url }
        
        do {
            try await ref.setData(data, merge: true)
            KBLog.sync.kbInfo("Upsert my member profile completed familyId=\(familyId) displayName=\(resolvedName ?? "nil")")
        } catch {
            KBLog.sync.kbError("upsertMyMemberProfileIfNeeded failed: \(error.localizedDescription)")
        }
    }
}
