//
//  KBShoppingTrip.swift
//  KidBox
//
//  Una spesa fatta: cosa è finito nel carrello, dove, quanto è costata.
//
//  Nasce dal filtro "Presi" della lista: quello che si spunta al supermercato è
//  già l'elenco dello scontrino, e archiviarlo costa un tocco. Il record resta
//  qui come storico; i soldi vivono nella spesa collegata (`linkedExpenseId`),
//  che è l'unica voce contata nella sezione Spese.
//

import Foundation
import SwiftData

/// Una riga dello scontrino, congelata al momento del salvataggio: se il
/// prodotto viene poi rinominato o cancellato dalla lista, lo storico non cambia.
struct KBShoppingTripLine: Codable, Hashable, Identifiable {
    var name: String
    var quantity: Int?

    var id: String { "\(name)-\(quantity ?? 1)" }
}

@Model
final class KBShoppingTrip {

    // MARK: - Identity
    @Attribute(.unique) var id: String = UUID().uuidString
    var familyId: String = ""

    // MARK: - Content
    var storeName: String?
    var total: Double = 0
    var date: Date = Date()
    /// Le righe dello scontrino serializzate in JSON: un solo campo da
    /// sincronizzare, e nessuna relazione da tenere allineata quando i prodotti
    /// spariscono dalla lista.
    var linesJson: String?
    var notes: String?
    /// La spesa creata nella sezione Spese, se c'è.
    var linkedExpenseId: String?

    // MARK: - Soft delete
    var isDeleted: Bool = false

    // MARK: - Sync metadata
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var updatedBy: String?
    var createdBy: String?
    var syncStateRaw: Int = KBSyncState.synced.rawValue
    var lastSyncError: String?

    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    /// Le righe decodificate. Un JSON illeggibile non fa sparire lo scontrino:
    /// restano negozio, totale e data, che sono il motivo per cui lo si salva.
    var lines: [KBShoppingTripLine] {
        get {
            guard let linesJson, let data = linesJson.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([KBShoppingTripLine].self, from: data)) ?? []
        }
        set {
            linesJson = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        storeName: String? = nil,
        total: Double = 0,
        date: Date = Date(),
        lines: [KBShoppingTripLine] = [],
        notes: String? = nil,
        linkedExpenseId: String? = nil,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        updatedBy: String? = nil,
        createdBy: String? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.storeName = storeName
        self.total = total
        self.date = date
        self.notes = notes
        self.linkedExpenseId = linkedExpenseId
        self.isDeleted = isDeleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.createdBy = createdBy
        self.syncStateRaw = KBSyncState.synced.rawValue
        self.linesJson = (try? JSONEncoder().encode(lines)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
