//
//  MasterKeyMigration.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import Foundation
import SwiftData
import CryptoKit

/// Performs a local migration to ensure each `KBFamily` has a stored master key.
///
/// This migration is **local-only**:
/// - It inspects all local families in SwiftData.
/// - For any family missing a key in `FamilyKeychainStore`, it generates a new random 32-byte key
///   and saves it to the Keychain.
///
/// Typical usage (boot time, best effort):
/// ```swift
/// Task {
///   try? await MasterKeyMigration.migrateAllFamilies(modelContext: modelContext)
/// }
/// ```
enum MasterKeyMigration {
    
    /// Generates and stores a master key for every local family that doesn't have one yet.
    ///
    /// Behavior (logic unchanged):
    /// - Fetches all families from SwiftData.
    /// - Skips families that already have a key in `FamilyKeychainStore`.
    /// - Generates a 32-byte random key and stores it in Keychain for missing ones.
    /// - Throws if saving fails for any family.
    static func migrateAllFamilies(modelContext: ModelContext) async throws {
        KBLog.sync.kbInfo("MasterKeyMigration started (checking families)")
        
        // Carica tutte le famiglie
        let descriptor = FetchDescriptor<KBFamily>()
        let families = try modelContext.fetch(descriptor)
        
        KBLog.sync.kbInfo("MasterKeyMigration families count=\(families.count)")
        
        var migratedCount = 0
        
        for family in families {
            let familyId = family.id
            
            // Controlla se la key esiste già
            if FamilyKeychainStore.loadFamilyKey(familyId: familyId) != nil {
                KBLog.sync.kbDebug("MasterKeyMigration skip (already exists) familyId=\(familyId)")
                continue
            }
            
            // Crea la key
            KBLog.sync.kbInfo("MasterKeyMigration generating key familyId=\(familyId)")
            do {
                let masterKeyBytes = InviteCrypto.randomBytes(32)
                let masterKey = CryptoKit.SymmetricKey(data: masterKeyBytes)
                try FamilyKeychainStore.saveFamilyKey(masterKey, familyId: familyId)
                KBLog.sync.kbInfo("MasterKeyMigration key created familyId=\(familyId)")
                migratedCount += 1
            } catch {
                KBLog.sync.kbError("MasterKeyMigration failed familyId=\(familyId) error=\(error.localizedDescription)")
                throw error
            }
        }
        
        KBLog.sync.kbInfo("MasterKeyMigration completed migrated=\(migratedCount)")
    }
}
