//
//  DocumentCryptoService.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import Foundation
import CryptoKit

/// Cryptographic utilities for encrypting/decrypting KidBox documents.
///
/// Security model (unchanged):
/// - Uses a per-family symmetric key loaded from `FamilyKeychainStore`.
/// - Encrypts with AES-GCM.
/// - The encrypted payload is returned/accepted as `combined`:
///   `nonce + ciphertext + tag` (Apple CryptoKit format).
///
/// Logging:
/// - Never log plaintext, ciphertext, keys, nonces, or tags.
/// - Only log high-level events and sizes for debugging.
enum DocumentCryptoService {
    
    /// Errors thrown by document crypto operations.
    enum CryptoError: Error {
        /// The per-family key is missing in Keychain.
        case missingFamilyKey
        /// CryptoKit did not produce/accept a combined representation.
        case invalidCipher
    }
    
    /// Encrypts plaintext bytes for a given family.
    ///
    /// - Parameters:
    ///   - plaintext: Data to encrypt.
    ///   - familyId: Family identifier used to load the correct key.
    ///
    /// - Returns: AES-GCM combined representation (nonce + ciphertext + tag).
    ///
    /// - Throws:
    ///   - `CryptoError.missingFamilyKey` if the family key is not available.
    ///   - `CryptoError.invalidCipher` if `sealed.combined` is nil.
    ///   - Any CryptoKit errors thrown by `AES.GCM.seal`.
    static func encrypt(_ plaintext: Data, familyId: String, userId: String) throws -> Data {
        KBLog.sync.kbDebug("Encrypt start familyId=\(familyId) bytes=\(plaintext.count)")
        
        guard let key = FamilyKeychainStore.loadFamilyKey(familyId: familyId, userId: userId) else {
            KBLog.sync.kbError("Encrypt failed: missing family key familyId=\(familyId)")
            throw CryptoError.missingFamilyKey
        }
        
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            KBLog.sync.kbError("Encrypt failed: invalid cipher (combined nil) familyId=\(familyId)")
            throw CryptoError.invalidCipher
        }
        
        KBLog.sync.kbDebug("Encrypt OK familyId=\(familyId) outBytes=\(combined.count)")
        return combined
    }
    
    /// Decrypts AES-GCM combined bytes for a given family.
    ///
    /// - Parameters:
    ///   - combined: AES-GCM combined representation (nonce + ciphertext + tag).
    ///   - familyId: Family identifier used to load the correct key.
    ///
    /// - Returns: Decrypted plaintext bytes.
    ///
    /// - Throws:
    ///   - `CryptoError.missingFamilyKey` if the family key is not available.
    ///   - Any CryptoKit errors thrown by `SealedBox(combined:)` or `AES.GCM.open`.
    static func decrypt(_ combined: Data, familyId: String, userId: String) throws -> Data {
        KBLog.sync.kbDebug("Decrypt start familyId=\(familyId) bytes=\(combined.count)")
        
        guard let key = FamilyKeychainStore.loadFamilyKey(familyId: familyId, userId: userId) else {
            KBLog.sync.kbError("Decrypt failed: missing family key familyId=\(familyId)")
            throw CryptoError.missingFamilyKey
        }
        
        let box = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(box, using: key)
        
        KBLog.sync.kbDebug("Decrypt OK familyId=\(familyId) outBytes=\(plaintext.count)")
        return plaintext
    }
}
