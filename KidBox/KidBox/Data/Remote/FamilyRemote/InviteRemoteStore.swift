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

/// Firestore document representing an invite code.
struct InviteDoc: Codable {
    let familyId: String
    let createdBy: String
    let revoked: Bool
}

/// Remote store for invite codes + family membership join.
///
/// Responsibilities:
/// - Create invite codes (with collision retry).
/// - Resolve invite codes (validates revoked/expiry).
/// - Add current user as a family member and write membership index.
final class InviteRemoteStore {
    
    /// Firestore handle (computed as in original code).
    private var db: Firestore { Firestore.firestore() }
    
    /// Creates an invite code for a family. Retries if a collision happens.
    ///
    /// Behavior (unchanged):
    /// - Requires authenticated user.
    /// - Tries up to 10 times to generate a unique code.
    /// - Uses a Firestore transaction to ensure uniqueness.
    /// - Stores expiresAt (client computed) + createdAt server timestamp.
    /// - On collision: retries.
    func createInviteCode(familyId: String, ttlDays: Int = 7) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("createInviteCode failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        KBLog.sync.kbInfo("createInviteCode started familyId=\(familyId) ttlDays=\(ttlDays)")
        
        for attempt in 0..<10 {
            let code = InviteCodeGenerator.generate()
            let ref = db.collection("invites").document(code)
            
            do {
                _ = try await db.runTransaction { transaction, errorPointer in
                    do {
                        let snap = try transaction.getDocument(ref)
                        if snap.exists {
                            errorPointer?.pointee = NSError(domain: "KidBox", code: 409)
                            return nil
                        }
                    } catch {
                        errorPointer?.pointee = error as NSError
                        return nil
                    }
                    
                    let expiresAt = Calendar.current.date(byAdding: .day, value: ttlDays, to: Date()) ?? Date()
                    
                    transaction.setData([
                        "familyId": familyId,
                        "createdBy": uid,
                        "revoked": false,
                        "createdAt": FieldValue.serverTimestamp(),
                        "expiresAt": Timestamp(date: expiresAt)
                    ], forDocument: ref)
                    
                    return nil
                }
                
                KBLog.sync.kbInfo("Invite created familyId=\(familyId) code=\(code)")
                return code
                
            } catch {
                // Keep original behavior: treat as collision / retry
                KBLog.sync.kbDebug("Invite collision, retrying attempt=\(attempt + 1)")
                continue
            }
        }
        
        KBLog.sync.kbError("createInviteCode failed: unable to generate unique code familyId=\(familyId)")
        throw NSError(
            domain: "KidBox",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Unable to generate unique invite code"]
        )
    }
    
    /// Resolves an invite code to a `familyId` and validates revoked/expiry.
    ///
    /// Behavior (unchanged):
    /// - Requires authenticated user.
    /// - Throws:
    ///   - 404 if code not found
    ///   - 410 if revoked or expired
    ///   - -3 if malformed doc (missing familyId)
    func resolveInvite(code: String) async throws -> String {
        guard Auth.auth().currentUser != nil else {
            KBLog.auth.kbError("resolveInvite failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        KBLog.sync.kbInfo("resolveInvite started code=\(code)")
        
        let snap = try await db.collection("invites").document(code).getDocument()
        guard let data = snap.data() else {
            KBLog.sync.kbDebug("resolveInvite invalid code=\(code)")
            throw NSError(
                domain: "KidBox",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Codice non valido"]
            )
        }
        
        if (data["revoked"] as? Bool) == true {
            KBLog.sync.kbDebug("resolveInvite revoked code=\(code)")
            throw NSError(
                domain: "KidBox",
                code: 410,
                userInfo: [NSLocalizedDescriptionKey: "Codice revocato"]
            )
        }
        
        if let expiresAt = data["expiresAt"] as? Timestamp,
           expiresAt.dateValue() < Date() {
            KBLog.sync.kbDebug("resolveInvite expired code=\(code)")
            throw NSError(
                domain: "KidBox",
                code: 410,
                userInfo: [NSLocalizedDescriptionKey: "Codice scaduto"]
            )
        }
        
        guard let familyId = data["familyId"] as? String else {
            KBLog.sync.kbError("resolveInvite malformed invite code=\(code)")
            throw NSError(
                domain: "KidBox",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Invite malformato"]
            )
        }
        
        KBLog.sync.kbInfo("resolveInvite OK code=\(code) familyId=\(familyId)")
        return familyId
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
