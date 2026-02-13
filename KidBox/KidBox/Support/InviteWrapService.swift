//
//  InviteWrapService.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import CryptoKit

struct InviteWrapService {
    
    struct Result {
        let inviteId: String
        let secretBase64url: String
        let qrPayload: String
        let expiresAt: Date
    }
    
    /// TTL consigliato: 24h
    func createInvite(familyId: String, ttlSeconds: TimeInterval = 24 * 3600) async throws -> Result {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox.Invite", code: -1)
        }
        
        // 1) Ensure family master key in Keychain (random 32 bytes)
        let familyKey: SymmetricKey
        if let existing = FamilyKeychainStore.loadFamilyKey(familyId: familyId) {
            familyKey = existing
        } else {
            let raw = InviteCrypto.randomBytes(32)
            let created = SymmetricKey(data: raw)
            try FamilyKeychainStore.saveFamilyKey(created, familyId: familyId)
            familyKey = created
        }
        
        // 2) Create invite secret (32 bytes) + salt (16 bytes)
        let inviteId = UUID().uuidString
        let secret = InviteCrypto.randomBytes(32)
        let salt = InviteCrypto.randomBytes(16)
        
        let wrapKey = InviteCrypto.deriveWrapKey(secret: secret, salt: salt, familyId: familyId)
        let wrapped = try InviteCrypto.wrapFamilyKey(familyKey: familyKey, wrapKey: wrapKey)
        
        let expiresAt = Date().addingTimeInterval(ttlSeconds)
        
        // 3) Store invite doc (NO secret in Firestore)
        let secretHash = InviteCrypto.sha256Base64(secret)
        
        let docRef = Firestore.firestore()
            .collection("families")
            .document(familyId)
            .collection("invites")
            .document(inviteId)
        
        try await docRef.setData([
            "createdAt": Timestamp(date: Date()),
            "createdBy": uid,
            "expiresAt": Timestamp(date: expiresAt),
            
            "secretHash": secretHash,
            "kdfSalt": salt.base64EncodedString(),
            
            "wrappedKeyCipher": wrapped.cipher.base64EncodedString(),
            "wrappedKeyNonce": wrapped.nonce.base64EncodedString(),
            "wrappedKeyTag": wrapped.tag.base64EncodedString(),
            
            "usedAt": NSNull(),
            "usedBy": NSNull()
        ], merge: false)
        
        // 4) QR payload contains inviteId + secret (url-safe)
        let secretB64url = secret.base64url()
        let qrPayload = "kidbox://join?familyId=\(familyId)&inviteId=\(inviteId)&secret=\(secretB64url)"
        
        return Result(inviteId: inviteId, secretBase64url: secretB64url, qrPayload: qrPayload, expiresAt: expiresAt)
    }
}
