//
//  InviteCrypto.swift
//  KidBox
//
//  FIXED: Correct AES.GCM.Nonce initialization
//

import Foundation
import CryptoKit
import Security
internal import os

/// Primitive crittografiche per inviti e wrapping della master key di famiglia.
///
/// - Note:
///   - `secret` (input) è un blob casuale (tipicamente 32 bytes) condiviso via QR.
///   - `wrapKey` è derivata con HKDF-SHA256 usando `secret + salt + familyId`.
///   - La family master key viene “wrappata” con AES-GCM (confidenzialità + integrità).
///
/// - Security:
///   - AES.GCM usa nonce 12 bytes (standard) e tag 16 bytes.
///   - `sha256Base64` produce Base64 standard (non URL-safe) utile per confronti su Firestore.
///
/// - Logging:
///   - Nessun `print`.
///   - Log solo su condizioni anomale / errori.
enum InviteCrypto {
    
    // MARK: - Randomness
    
    /// Genera `count` bytes random usando `SecRandomCopyBytes`.
    ///
    /// - Important: se `SecRandomCopyBytes` fallisce, ritorna comunque un buffer della dimensione richiesta
    ///   (ma non random) e logga errore. In pratica: trattalo come failure e non usare quel valore.
    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status: Int32 = data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        
        if status != errSecSuccess {
            KBLog.security.error("SecRandomCopyBytes failed status=\(status)")
        }
        
        return data
    }
    
    // MARK: - Hash
    
    /// SHA256(data) in Base64 standard.
    static func sha256Base64(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }
    
    // MARK: - KDF
    
    /// Deriva una wrap key (32 bytes) con HKDF-SHA256.
    ///
    /// - Parameters:
    ///   - secret: segreto condiviso (es. 32 bytes) dall’invito
    ///   - salt: salt random per HKDF
    ///   - familyId: domain separation (entra nell’info)
    ///
    /// - Returns: `SymmetricKey` (32 bytes)
    static func deriveWrapKey(secret: Data, salt: Data, familyId: String) -> SymmetricKey {
        let ikm = SymmetricKey(data: secret)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: Data("kidbox-wrap:\(familyId)".utf8),
            outputByteCount: 32
        )
    }
    
    // MARK: - Wrap / Unwrap
    
    /// Cifra (wrap) la family master key con AES-GCM usando la wrap key.
    ///
    /// - Returns: tuple (ciphertext, nonce, tag) da salvare su storage/Firestore.
    static func wrapFamilyKey(
        familyKey: SymmetricKey,
        wrapKey: SymmetricKey
    ) throws -> (cipher: Data, nonce: Data, tag: Data) {
        let plaintext = familyKey.withUnsafeBytes { Data($0) }
        do {
            let sealed = try AES.GCM.seal(plaintext, using: wrapKey)
            return (
                cipher: sealed.ciphertext,
                nonce: Data(sealed.nonce),
                tag: sealed.tag
            )
        } catch {
            KBLog.security.error("wrapFamilyKey failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    /// Decifra (unwrap) la family master key con AES-GCM usando la wrap key.
    ///
    /// - Parameters:
    ///   - cipher: ciphertext
    ///   - nonce: nonce (12 bytes tipici)
    ///   - tag: authentication tag (16 bytes)
    ///   - wrapKey: wrap key (32 bytes)
    ///
    /// - Returns: `SymmetricKey` (family master key)
    static func unwrapFamilyKey(
        cipher: Data,
        nonce: Data,
        tag: Data,
        wrapKey: SymmetricKey
    ) throws -> SymmetricKey {
        do {
            let nonceObj = try AES.GCM.Nonce(data: nonce)
            let sealed = try AES.GCM.SealedBox(
                nonce: nonceObj,
                ciphertext: cipher,
                tag: tag
            )
            let plaintext = try AES.GCM.open(sealed, using: wrapKey)
            return SymmetricKey(data: plaintext)
        } catch {
            KBLog.security.error("unwrapFamilyKey failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}

// MARK: - URL-safe Base64 helpers (per QR code)

extension Data {
    
    /// Encode to URL-safe Base64 (RFC 4648):
    /// - usa `-` e `_` al posto di `+` e `/`
    /// - rimuove il padding `=`
    func base64url() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Decode da URL-safe Base64.
    ///
    /// - Note: aggiunge padding `=` se necessario.
    static func fromBase64url(_ s: String) -> Data? {
        var str = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let mod = str.count % 4
        if mod != 0 {
            str += String(repeating: "=", count: 4 - mod)
        }
        
        let data = Data(base64Encoded: str)
        if data == nil {
            KBLog.security.error("fromBase64url failed: invalid base64url input")
        }
        return data
    }
}
