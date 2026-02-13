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
    
    func parse(payload raw: String) -> ParsedPayload? {
        guard let comps = URLComponents(string: raw),
              comps.scheme == "kidbox",
              comps.host == "join",
              let items = comps.queryItems else { return nil }
        
        func get(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        
        guard let familyId = get("familyId"),
              let inviteId = get("inviteId"),
              let secretStr = get("secret"),
              let secret = Data.fromBase64url(secretStr) else { return nil }
        
        return ParsedPayload(familyId: familyId, inviteId: inviteId, secret: secret)
    }
    
    /// Consuma invito (mark used + delete) e salva la master key in Keychain
    func join(usingQRPayload raw: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox.Join", code: -1)
        }
        guard let parsed = parse(payload: raw) else {
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
            throw JoinInviteError.invalidPayload
        }
        
        // unwrap key
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
            throw JoinInviteError.invalidPayload
        }
        
        let wrapKey = InviteCrypto.deriveWrapKey(secret: secret, salt: salt, familyId: familyId)
        let familyKey = try InviteCrypto.unwrapFamilyKey(cipher: cipher, nonce: nonce, tag: tag, wrapKey: wrapKey)
        
        // save in Keychain
        try FamilyKeychainStore.saveFamilyKey(familyKey, familyId: familyId)
        
        // delete invite (best effort)
        try? await docRef.delete()
        // Verifica che la key sia stata salvata
        if let loadedKey = FamilyKeychainStore.loadFamilyKey(familyId: familyId) {
            print("✅ Master key successfully saved to Keychain for: \(familyId)")
        } else {
            print("❌ Master key NOT found in Keychain after join!")
        }
    }
}

