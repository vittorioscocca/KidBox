//
//  MasterKeyMigration.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//


import Foundation
import SwiftData
import CryptoKit

enum MasterKeyMigration {
    
    /// Genera master key per tutte le famiglie che non ce l'hanno
    ///
    /// Uso:
    /// ```
    /// // Nel boot (AppDelegate o RootView onAppear)
    /// try? await MasterKeyMigration.migrateAllFamilies(modelContext: modelContext)
    /// ```
    ///
    static func migrateAllFamilies(modelContext: ModelContext) async throws {
        print("🔄 Checking families for master key migration...")
        
        // Carica tutte le famiglie
        let descriptor = FetchDescriptor<KBFamily>()
        let families = try modelContext.fetch(descriptor)
        
        print("📊 Found \(families.count) families")
        
        var migratedCount = 0
        
        for family in families {
            let familyId = family.id
            
            // Controlla se la key esiste già
            if FamilyKeychainStore.loadFamilyKey(familyId: familyId) != nil {
                print("✅ Family \(familyId) already has master key")
                continue
            }
            
            // Crea la key
            print("🔑 Generating master key for family: \(familyId)")
            do {
                let masterKeyBytes = InviteCrypto.randomBytes(32)
                let masterKey = CryptoKit.SymmetricKey(data: masterKeyBytes)
                try FamilyKeychainStore.saveFamilyKey(masterKey, familyId: familyId)
                print("✅ Master key created for family: \(familyId)")
                migratedCount += 1
            } catch {
                print("❌ Failed to create master key for family \(familyId): \(error.localizedDescription)")
                throw error
            }
        }
        
        print("✅ Migration complete! Migrated \(migratedCount) families")
    }
}

/*
 INTEGRAZIONE:
 
 1. Aggiungi questo call nel tuo AppDelegate.application(_:didFinishLaunchingWithOptions:)
 oppure nel RootView.onAppear():
 
 ```swift
 @Environment(\.modelContext) private var modelContext
 
 .onAppear {
 Task {
 try? await MasterKeyMigration.migrateAllFamilies(modelContext: modelContext)
 }
 }
 ```
 
 2. Questo script:
 - Carica tutte le famiglie dal database
 - Per ogni famiglia, controlla se ha una master key nel Keychain
 - Se NO, ne genera una nuova (32 bytes random)
 - Se SÌ, la salta (idempotent)
 
 3. È sicuro lanciarlo multiple volte (ogni volta skippa le famiglie che già hanno la key)
 
 4. Log output sarà:
 ```
 🔄 Checking families for master key migration...
 📊 Found 2 families
 ✅ Family 684E0CAE-... already has master key
 🔑 Generating master key for family: ABC123...
 ✅ Master key created for family: ABC123...
 ✅ Migration complete! Migrated 1 families
 ```
 */
