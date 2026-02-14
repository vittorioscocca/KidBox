//
//  FamilyKeychainStore.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import Foundation
import Security
import CryptoKit
import OSLog

/// Gestione della master key di famiglia nel Keychain.
///
/// - Security:
///   - Service: "KidBox"
///   - Access level: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
///   - Chiave 32 byte (AES-256)
///
/// - Logging:
///   - Nessun `print`
///   - Log solo in caso di errore o condizioni anomale
enum FamilyKeychainStore {
    
    private static let service = "KidBox"
    
    private static func keychainKey(for familyId: String) -> String {
        "kidbox.family.masterkey.\(familyId)"
    }
    
    /// Carica la master key per una famiglia.
    ///
    /// - Returns: `SymmetricKey` se presente e valida (32 byte), altrimenti `nil`.
    static func loadFamilyKey(familyId: String) -> SymmetricKey? {
        let account = keychainKey(for: familyId)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                KBLog.security.error(
                    "Keychain load failed for familyId=\(familyId, privacy: .public), status=\(status)"
                )
            }
            return nil
        }
        
        guard
            let data = item as? Data,
            data.count == 32
        else {
            KBLog.security.error(
                "Keychain load invalid data length for familyId=\(familyId, privacy: .public)"
            )
            return nil
        }
        
        return SymmetricKey(data: data)
    }
    
    /// Salva (o sovrascrive) la master key per una famiglia.
    ///
    /// - Throws: errore se `SecItemAdd` fallisce.
    static func saveFamilyKey(_ key: SymmetricKey, familyId: String) throws {
        let account = keychainKey(for: familyId)
        let data = key.withUnsafeBytes { Data($0) }
        
        // 1️⃣ Cancella eventuale chiave precedente (best effort)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // 2️⃣ Aggiungi nuova chiave
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            KBLog.security.error(
                "Keychain save failed for familyId=\(familyId, privacy: .public), status=\(status)"
            )
            throw NSError(
                domain: "KidBox.Keychain",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Keychain save failed (status: \(status))"]
            )
        }
        
        KBLog.security.info(
            "Master key saved for familyId=\(familyId, privacy: .public)"
        )
    }
}
