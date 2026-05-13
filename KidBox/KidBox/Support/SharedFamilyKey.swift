//
//  SharedFamilyKey.swift
//  KidBox
//
//  Mirror della family key nel Keychain con access group condiviso con l’estensione AutoFill
//  (account fisso `family.key`). L’app principale sincronizza dopo `FamilyKeychainStore.save`;
//  l’estensione legge solo questo item (nessun Firebase / SwiftData).
//

import CryptoKit
import Foundation
import Security

enum SharedFamilyKey {

    private static let service = "KidBox"
    private static let mirrorAccount = "family.key"

    /// Access group letto da Info.plist (`KidBoxSharedKeychainAccessGroup` = `$(AppIdentifierPrefix)it.vittorioscocca.kidbox.shared`).
    static func sharedAccessGroup() -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "KidBoxSharedKeychainAccessGroup") as? String,
              !raw.isEmpty,
              !raw.contains("$(")
        else { return nil }
        return raw
    }

    /// Salva in Keychain condiviso una copia locale della stessa materiale AES-256 usata per le password (mirror).
    static func saveMirroredFamilyKey(_ key: SymmetricKey) throws {
        guard let accessGroup = sharedAccessGroup() else {
            throw SharedFamilyKeyError.missingAccessGroup
        }
        let data = key.withUnsafeBytes { Data($0) }
        guard data.count == 32 else { throw SharedFamilyKeyError.invalidKeyLength }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: mirrorAccount,
            kSecAttrAccessGroup as String: accessGroup
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: mirrorAccount,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SharedFamilyKeyError.keychainFailure(status)
        }
    }

    static func deleteMirroredFamilyKey() {
        guard let accessGroup = sharedAccessGroup() else { return }
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: mirrorAccount,
            kSecAttrAccessGroup as String: accessGroup
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }

    static func loadMirroredFamilyKey() -> SymmetricKey? {
        guard let accessGroup = sharedAccessGroup() else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: mirrorAccount,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    enum SharedFamilyKeyError: Error {
        case missingAccessGroup
        case invalidKeyLength
        case keychainFailure(OSStatus)
    }
}
