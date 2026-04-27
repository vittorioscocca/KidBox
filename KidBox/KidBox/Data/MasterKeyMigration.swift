//
//  MasterKeyMigration.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import Foundation
import SwiftData
import CryptoKit
import FirebaseAuth

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

        let uid = Auth.auth().currentUser?.uid ?? "local"

        // Carica tutte le famiglie
        let descriptor = FetchDescriptor<KBFamily>()
        let families = try modelContext.fetch(descriptor)

        KBLog.sync.kbInfo("MasterKeyMigration families count=\(families.count)")

        var migratedCount = 0

        for family in families {
            let familyId = family.id

            // Controlla se la key esiste già nel Keychain locale
            if let existingKey = FamilyKeychainStore.loadFamilyKey(familyId: familyId, userId: uid) {
                KBLog.sync.kbDebug("MasterKeyMigration skip (already exists) familyId=\(familyId)")
                // Assicura che esista anche il backup su Firestore (best effort)
                await FamilyKeyEscrowService.backup(key: existingKey, familyId: familyId, userId: uid)
                continue
            }

            KBLog.sync.kbInfo("MasterKeyMigration key missing in Keychain — attempting Firestore recovery familyId=\(familyId)")

            // 1️⃣ Tenta il recovery dall'escrow Firestore (account precedente o reinstall)
            if let recovered = await FamilyKeyEscrowService.recover(familyId: familyId, userId: uid) {
                do {
                    try FamilyKeychainStore.saveFamilyKey(recovered, familyId: familyId, userId: uid)
                    KBLog.sync.kbInfo("MasterKeyMigration key recovered from Firestore escrow familyId=\(familyId)")
                    migratedCount += 1
                    continue
                } catch {
                    KBLog.sync.kbError("MasterKeyMigration Keychain save after recovery failed familyId=\(familyId) error=\(error.localizedDescription)")
                    // continua a generare una nuova chiave
                }
            }

            // 2️⃣ Ultima risorsa: genera una nuova chiave random e salvala sia nel Keychain
            //    che sull'escrow Firestore (così i prossimi recovery funzioneranno)
            KBLog.sync.kbInfo("MasterKeyMigration generating new key (no escrow found) familyId=\(familyId)")
            do {
                let masterKeyBytes = InviteCrypto.randomBytes(32)
                let masterKey = CryptoKit.SymmetricKey(data: masterKeyBytes)
                try FamilyKeychainStore.saveFamilyKey(masterKey, familyId: familyId, userId: uid)
                // Salva subito il backup così i recovery futuri funzionano
                await FamilyKeyEscrowService.backup(key: masterKey, familyId: familyId, userId: uid)
                KBLog.sync.kbInfo("MasterKeyMigration new key created and backed up familyId=\(familyId)")
                migratedCount += 1
            } catch {
                KBLog.sync.kbError("MasterKeyMigration failed familyId=\(familyId) error=\(error.localizedDescription)")
                throw error
            }
        }

        KBLog.sync.kbInfo("MasterKeyMigration completed migrated=\(migratedCount)")
    }
}
