//
//  FamilyKeychainStore.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import Foundation
import Security
import CryptoKit

enum FamilyKeychainStore {
    
    private static func keychainKey(for familyId: String) -> String {
        "kidbox.family.masterkey.\(familyId)"
    }
    
    static func loadFamilyKey(familyId: String) -> SymmetricKey? {
        let account = keychainKey(for: familyId)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "KidBox",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let data = item as? Data,
              data.count == 32 else {
            return nil
        }
        
        return SymmetricKey(data: data)
    }
    
    static func saveFamilyKey(_ key: SymmetricKey, familyId: String) throws {
        let account = keychainKey(for: familyId)
        let data = key.withUnsafeBytes { Data($0) }
        
        // delete old if exists
        let del: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "KidBox",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(del as CFDictionary)
        
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "KidBox",
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "KidBox.Keychain", code: Int(status))
        }
    }
}
