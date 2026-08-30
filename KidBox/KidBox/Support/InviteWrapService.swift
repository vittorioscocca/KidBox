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
        /// Universal Link condivisibile (WhatsApp, mail, messaggi).
        let shareLink: String
        let expiresAt: Date
    }

    /// Dominio degli inviti. Deve combaciare con l'entitlement
    /// `associated-domains` e con `apple-app-site-association`.
    static let inviteLinkBaseURL = "https://kidboxapp.com/join"

    /// Costruisce il link d'invito con il segreto nel **frammento**.
    ///
    /// Il segreto sta dopo `#` e non nella query per una ragione precisa: i
    /// browser non inviano mai il frammento al server. Così il materiale che
    /// sblocca la chiave di famiglia non finisce nei log di hosting né — cosa
    /// più importante — viene visto dai bot che generano le anteprime dei link.
    /// WhatsApp, iMessage e i client di posta scaricano l'URL condiviso per
    /// mostrare il riquadro di anteprima: con il segreto nella query lo
    /// manderemmo alla loro infrastruttura, con il frammento no.
    ///
    /// `familyId` e `inviteId` restano nella query: da soli non aprono nulla,
    /// perché senza segreto la chiave non è ricostruibile.
    static func shareLink(familyId: String, inviteId: String, secretBase64url: String) -> String {
        "\(inviteLinkBaseURL)?familyId=\(familyId)&inviteId=\(inviteId)#k=\(secretBase64url)"
    }
    
    /// TTL consigliato: 24h
    ///
    /// `familyName`/`inviterDisplayName` sono denormalizzati sul documento
    /// invito così chi riceve il link può leggerli PRIMA di entrare — la
    /// regola di `families/{familyId}` richiede membership, ma quella di
    /// `invites/{inviteId}` è aperta a ogni utente autenticato. Sono
    /// informativi (nome famiglia, nome di chi invita), non materiale
    /// crittografico: nessun rischio nel renderli leggibili pre-join.
    func createInvite(
        familyId: String,
        familyName: String,
        inviterDisplayName: String,
        ttlSeconds: TimeInterval = 24 * 3600
    ) async throws -> Result {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("Invite create failed: not authenticated")
            throw NSError(domain: "KidBox.Invite", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Not authenticated"
            ])
        }
        
        guard !familyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            KBLog.security.kbError("Invite create failed: empty familyId")
            throw NSError(domain: "KidBox.Invite", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "familyId vuoto"
            ])
        }
        
        let now = Date()
        
        // 1) Ensure family master key in Keychain (random 32 bytes)
        let familyKey: SymmetricKey
        do {
            if let existing = FamilyKeychainStore.loadFamilyKey(familyId: familyId, userId: uid) {
                familyKey = existing
            } else {
                // Try recovering from Firestore escrow before generating a new key
                if let recovered = await FamilyKeyEscrowService.recover(familyId: familyId, userId: uid) {
                    try FamilyKeychainStore.saveFamilyKey(recovered, familyId: familyId, userId: uid)
                    familyKey = recovered
                    KBLog.security.kbInfo("Family master key recovered from escrow for familyId=\(familyId)")
                } else {
                    let raw = InviteCrypto.randomBytes(32)
                    let created = SymmetricKey(data: raw)
                    try FamilyKeychainStore.saveFamilyKey(created, familyId: familyId, userId: uid)
                    familyKey = created
                    KBLog.security.kbInfo("Family master key created for familyId=\(familyId)")
                }
            }
            // Always ensure an up-to-date escrow backup exists for this user
            await FamilyKeyEscrowService.backup(key: familyKey, familyId: familyId, userId: uid)
        } catch {
            KBLog.security.kbError("Family master key ensure failed: \(error.localizedDescription)")
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
            KBLog.security.kbError("Invite wrap failed inviteId=\(inviteId): \(error.localizedDescription)")
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

                "familyName": familyName,
                "createdByDisplayName": inviterDisplayName,

                "secretHash": secretHash,
                "kdfSalt": salt.base64EncodedString(),
                
                "wrappedKeyCipher": wrapped.cipher.base64EncodedString(),
                "wrappedKeyNonce": wrapped.nonce.base64EncodedString(),
                "wrappedKeyTag": wrapped.tag.base64EncodedString(),
                
                "usedAt": NSNull(),
                "usedBy": NSNull()
            ], merge: false)
        } catch {
            KBLog.sync.kbError("Invite Firestore write failed inviteId=\(inviteId): \(error.localizedDescription)")
            throw error
        }
        
        // 5) QR payload contains inviteId + secret (url-safe)
        let secretB64url = secret.base64url()
        let qrPayload = "kidbox://join?familyId=\(familyId)&inviteId=\(inviteId)&secret=\(secretB64url)"
        
        KBLog.security.kbInfo("Invite created inviteId=\(inviteId) familyId=\(familyId)")
        
        return Result(
            inviteId: inviteId,
            secretBase64url: secretB64url,
            qrPayload: qrPayload,
            shareLink: Self.shareLink(
                familyId: familyId,
                inviteId: inviteId,
                secretBase64url: secretB64url
            ),
            expiresAt: expiresAt
        )
    }
}
