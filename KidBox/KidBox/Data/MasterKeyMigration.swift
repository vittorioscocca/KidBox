//
//  MasterKeyMigration.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import Foundation
import SwiftData
import FirebaseAuth

/// Allinea il Keychain locale alle chiavi di famiglia già esistenti.
///
/// **Solo recupero: non genera mai chiavi.** Il nome è storico — in origine
/// questa routine, se non trovava la chiave da nessuna parte, ne fabbricava una
/// nuova a caso. Girando a ogni avvio da `RootHostView`, il risultato era che
/// un utente entrato in famiglia col solo codice testuale (senza il QR che
/// trasporta il materiale crittografico) al primo riavvio si ritrovava una
/// chiave **divergente** da quella vera della famiglia: da lì in poi tutto ciò
/// che cifrava era illeggibile per gli altri e viceversa, in silenzio. Peggio,
/// la chiave fasulla veniva anche caricata sull'escrow, rendendo l'errore
/// permanente e apparentemente legittimo.
///
/// La regola ora è: **una chiave di famiglia nasce una volta sola, quando la
/// famiglia viene creata.** Ovunque altro il codice può solo recuperarla. Se
/// non è recuperabile è uno stato da mostrare all'utente — ci pensa
/// `FamilyKeyMissingGate`, che spiega come farsi reinvitare col QR — non da
/// tappare fabbricando dati.
///
/// Uso tipico (all'avvio, best effort):
/// ```swift
/// Task {
///   try? await MasterKeyMigration.migrateAllFamilies(modelContext: modelContext)
/// }
/// ```
enum MasterKeyMigration {

    /// Per ogni famiglia locale: assicura il backup su escrow se la chiave c'è,
    /// e tenta il recupero dall'escrow se manca.
    ///
    /// Comportamento:
    /// - Chiave presente in Keychain → aggiorna il backup su Firestore.
    /// - Chiave assente → tenta il recupero dall'escrow e la salva se riesce.
    /// - Recupero fallito → **non genera nulla**, logga e passa alla famiglia
    ///   successiva. Una famiglia irrecuperabile non deve fermare le altre.
    static func migrateAllFamilies(modelContext: ModelContext) async throws {
        KBLog.sync.kbInfo("MasterKeyMigration started (checking families)")

        let uid = Auth.auth().currentUser?.uid ?? "local"

        // Carica tutte le famiglie
        let descriptor = FetchDescriptor<KBFamily>()
        let families = try modelContext.fetch(descriptor)

        KBLog.sync.kbInfo("MasterKeyMigration families count=\(families.count)")

        var recoveredCount = 0
        var unrecoverableCount = 0

        for family in families {
            let familyId = family.id

            // Chiave già in Keychain: si assicura solo che esista il backup.
            //
            // Questo ramo non è cosmetico — è l'unico punto in cui la chiave di
            // chi CREA la famiglia arriva sull'escrow: né `SetupFamilyView` né
            // la creazione da onboarding fanno il backup, si limitano a salvare
            // in Keychain. Senza questo, il creatore non potrebbe recuperare la
            // propria chiave dopo una reinstallazione, finché non genera un invito.
            if let existingKey = FamilyKeychainStore.loadFamilyKey(familyId: familyId, userId: uid) {
                KBLog.sync.kbDebug("MasterKeyMigration key present, refreshing escrow backup familyId=\(familyId)")
                await FamilyKeyEscrowService.backup(key: existingKey, familyId: familyId, userId: uid)
                continue
            }

            KBLog.sync.kbInfo("MasterKeyMigration key missing in Keychain — attempting Firestore recovery familyId=\(familyId)")

            // Unica via: recupero dall'escrow (reinstallazione, nuovo dispositivo,
            // stesso account). Se non c'è backup, la chiave non è ricostruibile
            // da qui: solo chi ce l'ha può ritrasmetterla con un invito QR.
            guard let recovered = await FamilyKeyEscrowService.recover(familyId: familyId, userId: uid) else {
                unrecoverableCount += 1
                KBLog.security.kbError(
                    "MasterKeyMigration: no key and no escrow backup familyId=\(familyId) — contenuti cifrati illeggibili finché non arriva un nuovo invito QR"
                )
                continue
            }

            do {
                try FamilyKeychainStore.saveFamilyKey(recovered, familyId: familyId, userId: uid)
                recoveredCount += 1
                KBLog.sync.kbInfo("MasterKeyMigration key recovered from Firestore escrow familyId=\(familyId)")
            } catch {
                // Non si propaga: le altre famiglie devono comunque essere processate.
                unrecoverableCount += 1
                KBLog.sync.kbError("MasterKeyMigration Keychain save after recovery failed familyId=\(familyId) error=\(error.localizedDescription)")
            }
        }

        KBLog.sync.kbInfo("MasterKeyMigration completed recovered=\(recoveredCount) unrecoverable=\(unrecoverableCount)")
    }
}
