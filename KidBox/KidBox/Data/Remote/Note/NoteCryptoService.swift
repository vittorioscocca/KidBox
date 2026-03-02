//
//  NoteCryptoService.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import Foundation

enum NoteCryptoService {
    
    enum CryptoError: Error {
        case invalidBase64
        case invalidUTF8
    }
    
    /// Encrypts a UTF-8 string into base64(AES.GCM.SealedBox.combined)
    static func encryptString(_ plaintext: String, familyId: String, userId: String) throws -> String {
        let data = Data(plaintext.utf8)
        let combined = try DocumentCryptoService.encrypt(data, familyId: familyId, userId: userId)
        return combined.base64EncodedString()
    }
    
    /// Decrypts base64(AES.GCM.SealedBox.combined) into a UTF-8 string
    static func decryptString(_ combinedB64: String, familyId: String, userId: String) throws -> String {
        guard let combined = Data(base64Encoded: combinedB64) else {
            throw CryptoError.invalidBase64
        }
        let plaintext = try DocumentCryptoService.decrypt(combined, familyId: familyId, userId: userId)
        guard let s = String(data: plaintext, encoding: .utf8) else {
            throw CryptoError.invalidUTF8
        }
        return s
    }
}
