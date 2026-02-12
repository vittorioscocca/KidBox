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

struct InviteDoc: Codable {
    let familyId: String
    let createdBy: String
    let revoked: Bool
}

final class InviteRemoteStore {
    private var db: Firestore { Firestore.firestore() }
    
    /// Creates an invite code for a family. Retries if collision happens.
    func createInviteCode(familyId: String, ttlDays: Int = 7) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        for _ in 0..<10 {
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
                
                KBLog.sync.info("Invite created code=\(code, privacy: .public)")
                return code
            } catch {
                KBLog.sync.debug("Invite collision, retrying…")
                continue
            }
        }
        
        throw NSError(domain: "KidBox", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to generate unique invite code"])
    }
    
    /// Resolves an invite code to a familyId (validates revoked/expiry).
    func resolveInvite(code: String) async throws -> String {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let snap = try await db.collection("invites").document(code).getDocument()
        guard let data = snap.data() else {
            throw NSError(domain: "KidBox", code: 404, userInfo: [NSLocalizedDescriptionKey: "Codice non valido"])
        }
        
        if (data["revoked"] as? Bool) == true {
            throw NSError(domain: "KidBox", code: 410, userInfo: [NSLocalizedDescriptionKey: "Codice revocato"])
        }
        
        if let expiresAt = data["expiresAt"] as? Timestamp,
           expiresAt.dateValue() < Date() {
            throw NSError(domain: "KidBox", code: 410, userInfo: [NSLocalizedDescriptionKey: "Codice scaduto"])
        }
        
        guard let familyId = data["familyId"] as? String else {
            throw NSError(domain: "KidBox", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invite malformato"])
        }
        
        return familyId
    }
    
    /// Adds current user as member of the family + writes membership index.
    func addMember(familyId: String, role: String = "member") async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
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
        
        KBLog.sync.info("Member added familyId=\(familyId, privacy: .public) uid=\(uid, privacy: .public)")
    }
}
