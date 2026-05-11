//
//  DocumentCryptoService.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import Foundation
import CryptoKit
internal import os

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
    
    // MARK: - Chat-linked KBDocument payloads
    
    /// Firebase paths under `.../chat/...` store **plaintext** media, except legacy `*.kbenc`.
    static func isPlainChatStoragePath(_ storagePath: String) -> Bool {
        guard !storagePath.isEmpty,
              storagePath.range(of: "/chat/", options: .caseInsensitive) != nil else {
            return false
        }
        return !storagePath.lowercased().hasSuffix(".kbenc")
    }
    
    /// Indexed chat saves use `notes == "chat_plain"`; remote rows may omit it while still using a chat `storagePath`.
    static func storedKBDocumentPayloadIsPlaintext(notes: String?, storagePath: String) -> Bool {
        if notes == "chat_plain" { return true }
        return isPlainChatStoragePath(storagePath)
    }
    
    /// Bytes from Storage or local cache: decrypt KidBox document ciphertext, or return as-is for plain chat payloads.
    static func decryptStoredKBDocumentPayload(
        _ data: Data,
        storagePath: String,
        notes: String?,
        familyId: String,
        userId: String
    ) throws -> Data {
        let isPlain = storedKBDocumentPayloadIsPlaintext(notes: notes, storagePath: storagePath)
        KBLog.storage.kbInfo("CryptoService decryptPayload: bytes=\(data.count) isPlain=\(isPlain) notes=\(notes ?? "nil") storagePath=\(storagePath)")
        guard !isPlain else {
            KBLog.storage.kbDebug("CryptoService decryptPayload: returning as-is (plain)")
            return data
        }
        do {
            let result = try decrypt(data, familyId: familyId, userId: userId)
            KBLog.storage.kbInfo("CryptoService decryptPayload: success outBytes=\(result.count)")
            return result
        } catch {
            // Backward compatibility / bad cache: some rows or on-disk cache files hold
            // plaintext PDF/JPEG/etc. while `storagePath` still ends in `.kbenc`.
            // Decrypt then fails (e.g. CryptoKit authentication) — if magic matches a
            // known file type, return bytes as-is instead of blocking open.
            if looksLikePlainFilePayload(data) {
                KBLog.storage.kbInfo("CryptoService decryptPayload: plaintext blob fallback bytes=\(data.count) storagePath=\(storagePath) underlying=\(error.localizedDescription)")
                return data
            }
            KBLog.storage.kbError("CryptoService decryptPayload: FAILED bytes=\(data.count) storagePath=\(storagePath) error=\(error.localizedDescription)")
            throw error
        }
    }

    private static func looksLikePlainFilePayload(_ data: Data) -> Bool {
        if data.count >= 4 {
            let b4 = Array(data.prefix(4))
            // %PDF
            if b4 == [0x25, 0x50, 0x44, 0x46] { return true }
            // ZIP (docx/xlsx/pptx)
            if b4 == [0x50, 0x4B, 0x03, 0x04] { return true }
            // PNG
            if data.count >= 8 && Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] { return true }
            // JPEG
            if data.count >= 3 && Array(data.prefix(3)) == [0xFF, 0xD8, 0xFF] { return true }
            // OLE (legacy Office)
            if data.count >= 8 && Array(data.prefix(8)) == [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] { return true }
        }
        return false
    }

}
