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
internal import os

/// Crea un invito "crypto-wrapped" che permette all'altro genitore di recuperare
/// la master key della famiglia in modo sicuro.
///
/// Flusso:
/// 1) Assicura che esista una master key di famiglia (Keychain, 32 bytes).
/// 2) Genera `secret` (32 bytes) + `salt` (16 bytes) per HKDF.
/// 3) Deriva `wrapKey` con HKDF(secret+salt+familyId) e wrappa la master key con AES-GCM.
/// 4) Salva su Firestore SOLO hash del secret + salt + wrappedKey.
/// 5) Costruisce il QR payload con `secret` URL-safe base64 (non viene mai scritto su Firestore).
///
/// - Important:
///   - Nessun `print`.
///   - Log solo su errori/edge case.
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
            KBLog.auth.error("Invite create failed: not authenticated")
            throw NSError(domain: "KidBox.Invite", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Not authenticated"
            ])
        }
        
        guard !familyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            KBLog.security.error("Invite create failed: empty familyId")
            throw NSError(domain: "KidBox.Invite", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "familyId vuoto"
            ])
        }
        
        let now = Date()
        
        // 1) Ensure family master key in Keychain (random 32 bytes)
        let familyKey: SymmetricKey
        do {
            if let existing = FamilyKeychainStore.loadFamilyKey(familyId: familyId, userId: Auth.auth().currentUser?.uid ?? "local") {
                familyKey = existing
            } else {
                let raw = InviteCrypto.randomBytes(32)
                let created = SymmetricKey(data: raw)
                try FamilyKeychainStore.saveFamilyKey(created, familyId: familyId, userId: Auth.auth().currentUser?.uid ?? "local")
                familyKey = created
                KBLog.security.info("Family master key created for familyId=\(familyId, privacy: .public)")
            }
        } catch {
            KBLog.security.error("Family master key ensure failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        
        // 2) Create invite secret (32 bytes) + salt (16 bytes)
        let inviteId = UUID().uuidString
        let secret = InviteCrypto.randomBytes(32)
        let salt = InviteCrypto.randomBytes(16)
        
        // 3) Wrap family key using derived wrapKey
        let wrapped: (cipher: Data, nonce: Data, tag: Data)
        do {
            let wrapKey = InviteCrypto.deriveWrapKey(secret: secret, salt: salt, familyId: familyId)
            wrapped = try InviteCrypto.wrapFamilyKey(familyKey: familyKey, wrapKey: wrapKey)
        } catch {
            KBLog.security.error("Invite wrap failed inviteId=\(inviteId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
        
        let expiresAt = now.addingTimeInterval(ttlSeconds)
        let secretHash = InviteCrypto.sha256Base64(secret)
        
        // 4) Store invite doc (NO secret in Firestore)
        let docRef = Firestore.firestore()
            .collection("families")
            .document(familyId)
            .collection("invites")
            .document(inviteId)
        
        do {
            try await docRef.setData([
                "createdAt": Timestamp(date: now),
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
        } catch {
            KBLog.sync.error("Invite Firestore write failed inviteId=\(inviteId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
        
        // 5) QR payload contains inviteId + secret (url-safe)
        let secretB64url = secret.base64url()
        let qrPayload = "kidbox://join?familyId=\(familyId)&inviteId=\(inviteId)&secret=\(secretB64url)"
        
        KBLog.security.info("Invite created inviteId=\(inviteId, privacy: .public) familyId=\(familyId, privacy: .public)")
        
        return Result(
            inviteId: inviteId,
            secretBase64url: secretB64url,
            qrPayload: qrPayload,
            expiresAt: expiresAt
        )
    }
}
