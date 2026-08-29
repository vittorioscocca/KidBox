//
//  HousePaymentExpenseLink.swift
//  KidBox
//
//  Il ponte fra una scadenza di casa e la spesa di famiglia che ne deriva.
//
//  Stessa idea degli interventi sull'auto: la scadenza è il promemoria (cosa,
//  quando, da quale fornitore), la spesa è il denaro. L'importo si scrive una
//  volta sola, nella scheda della scadenza, e la voce in Spese si allinea da sé.
//

import Foundation
import SwiftData
import FirebaseAuth

enum HousePaymentExpenseLink {

    /// Allinea la spesa collegata alla scadenza appena salvata.
    ///
    /// - importo > 0 e nessuna spesa collegata → la crea;
    /// - importo > 0 e spesa già collegata → la aggiorna (titolo, importo, data, note);
    /// - importo tolto → la spesa collegata sparisce: la scadenza sta dicendo che
    ///   non ha un costo, e lasciarla in giro falserebbe i conti.
    @MainActor
    static func sync(
        payment: KBHousePayment,
        familyId: String,
        modelContext: ModelContext
    ) {
        payment.linkedExpenseId = KBLinkedExpense.sync(
            linkedExpenseId: payment.linkedExpenseId,
            amount: payment.importo,
            title: payment.name,
            fallbackTitle: String(localized: "Scadenza casa"),
            // La scadenza vera se c'è: una bolletta datata deve cadere nel mese
            // in cui si paga, non in quello in cui la si registra.
            date: payment.dataScadenza ?? Date(),
            notes: notesFor(payment: payment),
            categorySlug: "casa",
            familyId: familyId,
            modelContext: modelContext
        )
        payment.updatedAt = Date()
        payment.updatedBy = Auth.auth().currentUser?.uid ?? "local"
        payment.syncState = .pendingUpsert
        try? modelContext.save()
        SyncCenter.shared.enqueueHousePaymentUpsert(paymentId: payment.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }

    private static func notesFor(payment: KBHousePayment) -> String? {
        var parts: [String] = []
        if let fornitore = payment.fornitore?.trimmingCharacters(in: .whitespacesAndNewlines), !fornitore.isEmpty {
            parts.append(fornitore)
        }
        if let note = payment.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            parts.append(note)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
