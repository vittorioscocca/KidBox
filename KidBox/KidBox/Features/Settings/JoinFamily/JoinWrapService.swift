//
//  JoinWrapService.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import CryptoKit
import OSLog

enum JoinInviteError: Error, LocalizedError {
    case invalidPayload
    case expired
    case invalidSecret
    case alreadyUsed
    
    var errorDescription: String? {
        switch self {
        case .invalidPayload: return "QR non valido."
        case .expired: return "Invito scaduto."
        case .invalidSecret: return "Invito non valido."
        case .alreadyUsed: return "Invito già utilizzato."
        }
    }
}

struct JoinWrapService {
    
    struct ParsedPayload {
        let familyId: String
        let inviteId: String
        let secret: Data
    }
    
    /// Parses a KidBox join deep link.
    ///
    /// Expected format:
    /// `kidbox://join?familyId=...&inviteId=...&secret=...`
    ///
    /// - Important: `secret` is sensitive. Do not log it.
    func parse(payload raw: String) -> ParsedPayload? {
        guard let comps = URLComponents(string: raw),
              comps.scheme == "kidbox",
              comps.host == "join",
              let items = comps.queryItems else {
            KBLog.sync.debug("JoinWrapService parse failed: invalid URL components")
            return nil
        }
        
        func get(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        
        guard let familyId = get("familyId"),
              let inviteId = get("inviteId"),
              let secretStr = get("secret"),
              let secret = Data.fromBase64url(secretStr) else {
            KBLog.sync.debug("JoinWrapService parse failed: missing fields")
            return nil
        }
        
        KBLog.sync.info("JoinWrapService parse OK familyId=\(familyId, privacy: .public) inviteId=\(inviteId, privacy: .public)")
        return ParsedPayload(familyId: familyId, inviteId: inviteId, secret: secret)
    }
    
    /// Consumes an encrypted invite, unwraps the family master key, stores it in Keychain,
    /// then deletes the invite document (best effort).
    ///
    /// Flow:
    /// 1) Validate payload + authentication
    /// 2) Firestore transaction: validate invite (expiry/used/secret hash) + mark used
    /// 3) Unwrap family key (KDF + AEAD)
    /// 4) Save to Keychain
    /// 5) Delete invite document (best effort)
    ///
    /// - Important: Avoid logging secrets, ciphertexts, or raw payloads.
    func join(usingQRPayload raw: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.sync.error("JoinWrapService join failed: not authenticated")
            throw NSError(domain: "KidBox.Join", code: -1)
        }
        guard let parsed = parse(payload: raw) else {
            KBLog.sync.error("JoinWrapService join failed: invalid payload")
            throw JoinInviteError.invalidPayload
        }
        
        let familyId = parsed.familyId
        let inviteId = parsed.inviteId
        let secret = parsed.secret
        
        let docRef = Firestore.firestore()
            .collection("families")
            .document(familyId)
            .collection("invites")
            .document(inviteId)
        
        KBLog.sync.info("JoinWrapService join start familyId=\(familyId, privacy: .public) inviteId=\(inviteId, privacy: .public)")
        
        // Transaction: validate + mark used
        let result: Any? = try await Firestore.firestore().runTransaction { txn, errorPointer -> Any? in
            do {
                let snap = try txn.getDocument(docRef)
                guard let d = snap.data() else {
                    throw JoinInviteError.invalidPayload
                }
                
                // expires
                if let exp = (d["expiresAt"] as? Timestamp)?.dateValue(), Date() >= exp {
                    throw JoinInviteError.expired
                }
                
                // used?
                if (d["usedAt"] as? Timestamp) != nil {
                    throw JoinInviteError.alreadyUsed
                }
                
                // secret hash
                let expectedHash = d["secretHash"] as? String ?? ""
                let actualHash = InviteCrypto.sha256Base64(secret)
                guard actualHash == expectedHash else {
                    throw JoinInviteError.invalidSecret
                }
                
                // mark used
                txn.updateData([
                    "usedAt": Timestamp(date: Date()),
                    "usedBy": uid
                ], forDocument: docRef)
                
                return d
            } catch {
                if let pointer = errorPointer {
                    pointer.pointee = error as NSError
                }
                return nil
            }
        }
        
        // ✅ Cast result to [String: Any]
        guard let data = result as? [String: Any] else {
            KBLog.sync.error("JoinWrapService join failed: transaction returned no data familyId=\(familyId, privacy: .public)")
            throw JoinInviteError.invalidPayload
        }
        
        // unwrap key payload fields
        guard
            let saltB64 = data["kdfSalt"] as? String,
            let salt = Data(base64Encoded: saltB64),
            let cipherB64 = data["wrappedKeyCipher"] as? String,
            let nonceB64 = data["wrappedKeyNonce"] as? String,
            let tagB64 = data["wrappedKeyTag"] as? String,
            let cipher = Data(base64Encoded: cipherB64),
            let nonce = Data(base64Encoded: nonceB64),
            let tag = Data(base64Encoded: tagB64)
        else {
            KBLog.sync.error("JoinWrapService join failed: missing wrapped key fields familyId=\(familyId, privacy: .public)")
            throw JoinInviteError.invalidPayload
        }
        
        // Derive wrapping key and unwrap family key
        do {
            let wrapKey = InviteCrypto.deriveWrapKey(secret: secret, salt: salt, familyId: familyId)
            let familyKey = try InviteCrypto.unwrapFamilyKey(cipher: cipher, nonce: nonce, tag: tag, wrapKey: wrapKey)
            
            // save in Keychain
            try FamilyKeychainStore.saveFamilyKey(familyKey, familyId: familyId)
            KBLog.sync.info("JoinWrapService master key saved familyId=\(familyId, privacy: .public)")
            
        } catch {
            KBLog.sync.error("JoinWrapService unwrap/save failed familyId=\(familyId, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
            throw error
        }
        
        // delete invite (best effort)
        do {
            try await docRef.delete()
            KBLog.sync.debug("JoinWrapService invite deleted inviteId=\(inviteId, privacy: .public)")
        } catch {
            KBLog.sync.debug("JoinWrapService invite delete failed (best effort) inviteId=\(inviteId, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
        }
        
        // Verify key presence (do NOT print)
        if FamilyKeychainStore.loadFamilyKey(familyId: familyId) != nil {
            KBLog.sync.info("JoinWrapService keychain verify OK familyId=\(familyId, privacy: .public)")
        } else {
            KBLog.sync.error("JoinWrapService keychain verify FAILED familyId=\(familyId, privacy: .public)")
        }
    }
}
