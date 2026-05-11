//
//  FamilyKeyEscrowService.swift
//  KidBox
//
//  Encrypted backup of the family master key on Firestore, so any authenticated
//  family member can recover their Keychain entry after an account switch,
//  app reinstall, or iCloud Keychain loss.
//
//  Security model
//  ─────────────
//  The family key is wrapped with AES-GCM using an escrow key derived
//  deterministically from (userId + familyId + a compile-time constant) via
//  HKDF-SHA256. Recovery only requires knowing the Firebase UID (available after
//  normal Firebase Auth) and having access to the Firestore document — which must
//  be restricted by security rules to `request.auth.uid == userId`.
//
//  Firestore path:  families/{familyId}/memberKeyBackups/{userId}
//  Fields:          cipher, nonce, tag (all base64), updatedAt, version
//

import Foundation
import CryptoKit
import FirebaseFirestore
import OSLog

enum FamilyKeyEscrowService {

    // MARK: - Constants

    private static let db = Firestore.firestore()

    // Version tag — bump if the wrap scheme changes so we can migrate.
    private static let currentVersion = 1

    // App-level constants used in key derivation. Never log these.
    private static let escrowSalt    = "kidbox-escrow-salt-2026"
    private static let escrowContext = "kidbox-key-escrow-v1"

    // MARK: - Public API

    /// Encrypts `key` with a deterministic escrow key and stores it on Firestore.
    ///
    /// Best-effort: errors are logged but not rethrown so callers can fire-and-forget.
    ///
    /// - Parameters:
    ///   - key:      Family master key to back up.
    ///   - familyId: Identifies which Firestore sub-collection to write to.
    ///   - userId:   Firebase UID of the current user (used for key derivation and doc ID).
    static func backup(key: SymmetricKey, familyId: String, userId: String) async {
        guard !familyId.isEmpty, !userId.isEmpty else {
            KBLog.security.error("KeyEscrow backup skipped: empty familyId or userId")
            return
        }
        do {
            let escrowKey = deriveEscrowKey(userId: userId, familyId: familyId)
            let wrapped   = try InviteCrypto.wrapFamilyKey(familyKey: key, wrapKey: escrowKey)

            let data: [String: Any] = [
                "cipher":    wrapped.cipher.base64EncodedString(),
                "nonce":     wrapped.nonce.base64EncodedString(),
                "tag":       wrapped.tag.base64EncodedString(),
                "updatedAt": FieldValue.serverTimestamp(),
                "version":   currentVersion
            ]

            try await db
                .collection("families").document(familyId)
                .collection("memberKeyBackups").document(userId)
                .setData(data)

            KBLog.security.info(
                "KeyEscrow backup OK familyId=\(familyId, privacy: .public) userId=\(userId, privacy: .public)"
            )
        } catch {
            KBLog.security.error(
                "KeyEscrow backup failed familyId=\(familyId, privacy: .public) err=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Tries to recover the family master key from Firestore escrow.
    ///
    /// Returns `nil` if no backup document exists, the document is malformed,
    /// or unwrapping fails (e.g. wrong userId or corrupted data).
    ///
    /// - Parameters:
    ///   - familyId: Family whose key to recover.
    ///   - userId:   Firebase UID of the current user.
    static func recover(familyId: String, userId: String) async -> SymmetricKey? {
        guard !familyId.isEmpty, !userId.isEmpty else {
            KBLog.security.error("KeyEscrow recover skipped: empty familyId or userId")
            return nil
        }
        do {
            let snap = try await db
                .collection("families").document(familyId)
                .collection("memberKeyBackups").document(userId)
                .getDocument()

            guard
                let d        = snap.data(),
                let cipherB64 = d["cipher"] as? String,
                let nonceB64  = d["nonce"]  as? String,
                let tagB64    = d["tag"]    as? String,
                let cipher    = Data(base64Encoded: cipherB64),
                let nonce     = Data(base64Encoded: nonceB64),
                let tag       = Data(base64Encoded: tagB64)
            else {
                KBLog.security.info(
                    "KeyEscrow recover: no backup found familyId=\(familyId, privacy: .public) userId=\(userId, privacy: .public)"
                )
                return nil
            }

            let escrowKey = deriveEscrowKey(userId: userId, familyId: familyId)
            let familyKey = try InviteCrypto.unwrapFamilyKey(
                cipher: cipher, nonce: nonce, tag: tag, wrapKey: escrowKey
            )

            KBLog.security.info(
                "KeyEscrow recover OK familyId=\(familyId, privacy: .public) userId=\(userId, privacy: .public)"
            )
            return familyKey

        } catch {
            KBLog.security.error(
                "KeyEscrow recover failed familyId=\(familyId, privacy: .public) err=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    // MARK: - Convenience key-ensure

    /// Ensures the family master key is available in the local Keychain.
    ///
    /// - Checks Keychain first (fast path).
    /// - On miss, attempts Firestore escrow recovery and saves to Keychain.
    /// - Returns `true` if the key is available after the call, `false` otherwise.
    static func ensureFamilyKeyAvailable(familyId: String, userId: String) async -> Bool {
        guard !familyId.isEmpty, !userId.isEmpty else { return false }
        if FamilyKeychainStore.loadFamilyKey(familyId: familyId, userId: userId) != nil {
            return true
        }
        KBLog.security.info(
            "KeyEscrow key missing locally, trying escrow recovery familyId=\(familyId, privacy: .public)"
        )
        guard let recovered = await recover(familyId: familyId, userId: userId) else {
            KBLog.security.error(
                "KeyEscrow escrow recovery failed (no backup) familyId=\(familyId, privacy: .public)"
            )
            return false
        }
        do {
            try FamilyKeychainStore.saveFamilyKey(recovered, familyId: familyId, userId: userId)
            KBLog.security.info(
                "KeyEscrow escrow recovery OK familyId=\(familyId, privacy: .public)"
            )
            return true
        } catch {
            KBLog.security.error(
                "KeyEscrow save failed familyId=\(familyId, privacy: .public) err=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    // MARK: - Private helpers

    /// Derives a deterministic 32-byte AES-GCM key for wrapping the escrow payload.
    ///
    /// Input key material = SHA-256(userId + ":" + familyId + ":" + escrowContext)
    /// Salt               = UTF-8 bytes of the compile-time `escrowSalt` constant
    /// Info               = UTF-8 bytes of "escrowContext:userId:familyId" (domain separation)
    ///
    /// The derivation is fully deterministic: given the same (userId, familyId) pair
    /// it always produces the same wrap key, enabling key recovery after login.
    private static func deriveEscrowKey(userId: String, familyId: String) -> SymmetricKey {
        let ikmData = Data("\(userId):\(familyId):\(escrowContext)".utf8)
        let ikm     = SymmetricKey(data: SHA256.hash(data: ikmData))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: Data(escrowSalt.utf8),
            info: Data("\(escrowContext):\(userId):\(familyId)".utf8),
            outputByteCount: 32
        )
    }
}
