//
//  InviteRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

/// Scrive la membership quando si entra in una famiglia.
///
/// I codici invito testuali non esistono più: creavano membri privi della
/// chiave di cifratura, incapaci di leggere password, documenti, wallet e
/// allegati della chat. Si entra dal QR o dal link, che portano entrambi
/// `familyId` e il materiale crittografico.
final class InviteRemoteStore {

    /// Firestore handle (computed as in original code).
    private var db: Firestore { Firestore.firestore() }

    /// Info mostrabili PRIMA del join: nome famiglia e di chi ha invitato.
    struct InvitePreview {
        let familyName: String?
        let inviterDisplayName: String?
    }

    /// Legge il documento invito senza consumarlo, per mostrare a chi riceve
    /// il link "stai per entrare nella famiglia di…" prima che confermi.
    ///
    /// `families/{familyId}/invites/{inviteId}` è leggibile da ogni utente
    /// autenticato (non solo dai membri): è la stessa regola che permette a
    /// QR e link di funzionare per chi non è ancora dentro la famiglia.
    func fetchInvitePreview(familyId: String, inviteId: String) async -> InvitePreview {
        do {
            let doc = try await db.collection("families").document(familyId)
                .collection("invites").document(inviteId)
                .getDocument()
            let data = doc.data() ?? [:]
            return InvitePreview(
                familyName: data["familyName"] as? String,
                inviterDisplayName: data["createdByDisplayName"] as? String
            )
        } catch {
            KBLog.sync.kbError("InviteRemoteStore: fetchInvitePreview failed: \(error.localizedDescription)")
            return InvitePreview(familyName: nil, inviterDisplayName: nil)
        }
    }

    /// Adds current user as member of the family and writes the membership index.
    ///
    /// Behavior (unchanged):
    /// - Requires authenticated user.
    /// - Batch writes:
    ///   - `families/{familyId}/members/{uid}`
    ///   - `users/{uid}/memberships/{familyId}`
    func addMember(familyId: String, role: String = "member") async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("addMember failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        KBLog.sync.kbInfo("addMember started familyId=\(familyId) role=\(role)")
        
        let familyRef = db.collection("families").document(familyId)
        
        let memberRef = familyRef.collection("members").document(uid)
        let membershipRef = db.collection("users")
            .document(uid)
            .collection("memberships")
            .document(familyId)
        
        let batch = db.batch()
        
        batch.setData([
            "uid": uid,
            "role": role,
            "isDeleted": false,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: memberRef, merge: true)
        
        batch.setData([
            "familyId": familyId,
            "role": role,
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: membershipRef, merge: true)
        
        try await batch.commit()
        
        KBLog.sync.kbInfo("addMember OK familyId=\(familyId) role=\(role)")
    }
}
