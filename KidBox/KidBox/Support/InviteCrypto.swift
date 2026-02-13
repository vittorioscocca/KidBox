//
//  InviteCrypto.swift
//  KidBox
//
//  FIXED: Correct AES.GCM.Nonce initialization
//

import Foundation
import CryptoKit
import Security

enum InviteCrypto {
    
    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return data
    }
    
    static func sha256Base64(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }
    
    static func deriveWrapKey(secret: Data, salt: Data, familyId: String) -> SymmetricKey {
        let ikm = SymmetricKey(data: secret)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: Data("kidbox-wrap:\(familyId)".utf8),
            outputByteCount: 32
        )
    }
    
    /// Cifra family key con wrap key
    ///
    /// - Returns: (ciphertext, nonce, tag) per storage
    ///
    static func wrapFamilyKey(familyKey: SymmetricKey, wrapKey: SymmetricKey) throws -> (cipher: Data, nonce: Data, tag: Data) {
        let plaintext = familyKey.withUnsafeBytes { Data($0) }
        let sealed = try AES.GCM.seal(plaintext, using: wrapKey)
        
        // ✅ sealed.nonce è già Data
        return (
            cipher: sealed.ciphertext,
            nonce: Data(sealed.nonce),
            tag: sealed.tag
        )
    }
    
    /// Decifra family key con wrap key
    ///
    /// - Parameters:
    ///   - cipher: Ciphertext
    ///   - nonce: Nonce (12 bytes)
    ///   - tag: Authentication tag (16 bytes)
    ///   - wrapKey: Wrap key (32 bytes)
    ///
    static func unwrapFamilyKey(cipher: Data, nonce: Data, tag: Data, wrapKey: SymmetricKey) throws -> SymmetricKey {
        // ✅ FIXED: Usa il costruttore corretto di AES.GCM.Nonce
        let nonceObj = try AES.GCM.Nonce(data: nonce)
        
        let sealed = try AES.GCM.SealedBox(
            nonce: nonceObj,
            ciphertext: cipher,
            tag: tag
        )
        let plaintext = try AES.GCM.open(sealed, using: wrapKey)
        return SymmetricKey(data: plaintext)
    }
}

// MARK: - URL-safe Base64 helpers (per QR code)

extension Data {
    /// Encode to URL-safe Base64 (RFC 4648)
    /// Usa - e _ invece di + e /, rimuove padding =
    func base64url() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Decode da URL-safe Base64
    static func fromBase64url(_ s: String) -> Data? {
        var str = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Aggiungi padding se necessario
        let pad = 4 - (str.count % 4)
        if pad < 4 {
            str += String(repeating: "=", count: pad)
        }
        
        return Data(base64Encoded: str)
    }
}
