//
//  DocumentCryptoService.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import Foundation
import CryptoKit

enum DocumentCryptoService {
    
    enum CryptoError: Error {
        case missingFamilyKey
        case invalidCipher
    }
    
    // Encrypt -> returns combined (nonce+cipher+tag)
    static func encrypt(_ plaintext: Data, familyId: String) throws -> Data {
        guard let key = FamilyKeychainStore.loadFamilyKey(familyId: familyId) else {
            throw CryptoError.missingFamilyKey
        }
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CryptoError.invalidCipher }
        return combined
    }
    
    static func decrypt(_ combined: Data, familyId: String) throws -> Data {
        guard let key = FamilyKeychainStore.loadFamilyKey(familyId: familyId) else {
            throw CryptoError.missingFamilyKey
        }
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }
}
