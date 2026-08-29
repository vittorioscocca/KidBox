//
//  VehicleEventExpenseLink.swift
//  KidBox
//
//  Il ponte fra un intervento sul veicolo e la spesa di famiglia che ne deriva.
//
//  Stessa idea della spesa fatta al supermercato: l'intervento è il dettaglio
//  (cosa, dove, a quanti km), la spesa è il denaro. Il costo si scrive una volta
//  sola, nella scheda dell'intervento, e la voce in Spese si allinea da sé.
//

import Foundation
import SwiftData
import FirebaseAuth

enum VehicleEventExpenseLink {

    /// Allinea la spesa collegata all'intervento appena salvato.
    ///
    /// - costo > 0 e nessuna spesa collegata → la crea;
    /// - costo > 0 e spesa già collegata → la aggiorna (titolo, importo, data, note);
    /// - costo tolto → la spesa collegata sparisce: l'intervento sta dicendo che
    ///   non è costato niente, e lasciarla in giro falserebbe i conti.
    @MainActor
    static func sync(
        event: KBVehicleEvent,
        vehicleName: String?,
        familyId: String,
        modelContext: ModelContext
    ) {
        event.linkedExpenseId = KBLinkedExpense.sync(
            linkedExpenseId: event.linkedExpenseId,
            amount: event.cost,
            title: titleFor(event: event, vehicleName: vehicleName),
            fallbackTitle: String(localized: "Intervento auto"),
            date: event.date,
            notes: notesFor(event: event),
            categorySlug: "automobile",
            familyId: familyId,
            modelContext: modelContext
        )
        event.updatedAt = Date()
        event.updatedBy = Auth.auth().currentUser?.uid ?? "local"
        event.syncState = .pendingUpsert
        try? modelContext.save()
        SyncCenter.shared.enqueueVehicleEventUpsert(eventId: event.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }

    /// "Tagliando — Panda": in Spese si legge cosa e su quale auto, senza aprire il Garage.
    private static func titleFor(event: KBVehicleEvent, vehicleName: String?) -> String {
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = title.isEmpty ? String(localized: "Intervento auto") : title
        guard let vehicleName = vehicleName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !vehicleName.isEmpty else { return base }
        return "\(base) — \(vehicleName)"
    }

    private static func notesFor(event: KBVehicleEvent) -> String? {
        var parts: [String] = []
        if let garage = event.garageName?.trimmingCharacters(in: .whitespacesAndNewlines), !garage.isEmpty {
            parts.append(garage)
        }
        if let km = event.km {
            parts.append(String(localized: "\(km) km"))
        }
        if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append(notes)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
