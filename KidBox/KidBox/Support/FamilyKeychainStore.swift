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

/// Gestione della master key di famiglia nel Keychain con sincronizzazione iCloud.
///
/// ℹ️ IMPORTANT: Ogni utente ha la sua master key per ogni famiglia.
/// La chiave è identificata da: {userId}.{familyId}
/// Così se uno stesso dispositivo ha 2 account Apple ID, ogni account ha la sua chiave.
///
/// - Security:
///   - Service: "KidBox"
///   - Account: "kidbox.family.masterkey.{userId}.{familyId}"
///   - Access level: `kSecAttrAccessibleAfterFirstUnlock` (sincronizzato con iCloud Keychain)
///   - Chiave 32 byte (AES-256)
///   - Sincronizzazione: abilitata (`kSecAttrSynchronizable`)
///
/// - Logging:
///   - Nessun `print`
///   - Log solo in caso di errore o condizioni anomale
enum FamilyKeychainStore {
    
    private static let service = "KidBox"
    
    /// Costruisce la chiave Keychain univoca per un utente + famiglia
    ///
    /// - Parameters:
    ///   - familyId: Family identifier
    ///   - userId: Current user ID (from Firebase Auth)
    ///
    /// - Returns: Keychain account key (es: "kidbox.family.masterkey.{userId}.{familyId}")
    private static func keychainKey(for familyId: String, userId: String) -> String {
        "kidbox.family.masterkey.\(userId).\(familyId)"
    }
    
    /// Carica la master key per una famiglia + utente corrente.
    ///
    /// - Parameters:
    ///   - familyId: Family identifier
    ///   - userId: Current user ID (from Firebase Auth)
    ///
    /// - Returns: `SymmetricKey` se presente e valida (32 byte), altrimenti `nil`.
    /// - Note: Ricerca automaticamente tra i dispositivi sincronizzati via iCloud Keychain.
    static func loadFamilyKey(familyId: String, userId: String) -> SymmetricKey? {
        let account = keychainKey(for: familyId, userId: userId)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny // trova item sync e non-sync
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                KBLog.security.error(
                    "Keychain load failed for familyId=\(familyId, privacy: .public) userId=\(userId, privacy: .public), status=\(status)"
                )
            }
            return nil
        }
        
        guard
            let data = item as? Data,
            data.count == 32
        else {
            KBLog.security.error(
                "Keychain load invalid data length for familyId=\(familyId, privacy: .public) userId=\(userId, privacy: .public)"
            )
            return nil
        }
        
        return SymmetricKey(data: data)
    }
    
    /// Salva (o sovrascrive) la master key per una famiglia + utente corrente con sincronizzazione iCloud.
    ///
    /// - Parameters:
    ///   - key: La master key da salvare (32 byte AES-GCM)
    ///   - familyId: L'ID della famiglia
    ///   - userId: Current user ID (from Firebase Auth)
    ///
    /// - Throws: errore se `SecItemAdd` fallisce.
    ///
    /// - Important:
    ///   - La chiave viene automaticamente sincronizzata via iCloud Keychain
    ///   - Richiede iCloud Keychain abilitato nelle impostazioni iOS
    ///   - Disponibile su tutti i dispositivi con lo stesso Apple ID
    ///   - Ogni utente ha la sua chiave per ogni famiglia (no conflicts)
    static func saveFamilyKey(_ key: SymmetricKey, familyId: String, userId: String) throws {
        let account = keychainKey(for: familyId, userId: userId)
        let data = key.withUnsafeBytes { Data($0) }
        
        // 1️⃣ Cancella eventuale chiave precedente (best effort)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true  // ✅ Cerca nei dispositivi sincronizzati
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // 2️⃣ Aggiungi nuova chiave con sincronizzazione iCloud
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // ✅ iCloud Keychain: sincronizzazione multi-device
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: true
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            KBLog.security.error(
                "Keychain save failed for familyId=\(familyId, privacy: .public) userId=\(userId, privacy: .public), status=\(status)"
            )
            throw NSError(
                domain: "KidBox.Keychain",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Keychain save failed (status: \(status))"]
            )
        }
        
        KBLog.security.info(
            "Master key saved and synced to iCloud Keychain for familyId=\(familyId, privacy: .public) userId=\(userId, privacy: .public)"
        )
    }
}
