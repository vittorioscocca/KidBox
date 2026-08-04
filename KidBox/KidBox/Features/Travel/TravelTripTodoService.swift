//
//  TravelTripTodoService.swift
//  KidBox
//

import Foundation
import SwiftData

enum TravelTripTodoService {

    static func defaultListName(for trip: KBTrip) -> String {
        trip.name
    }

    /// Crea o recupera la lista Todo KidBox dedicata al viaggio e aggiorna `trip.todoListId`.
    ///
    /// - Parameter createIfMissing: `false` quando la chiamata non nasce da un
    ///   gesto dell'utente (per esempio l'apertura della scheda viaggio). Senza
    ///   questo freno, una lista cancellata dalla sezione Todo tornava da sola
    ///   al primo sguardo al viaggio — e ogni volta con un id nuovo, quindi
    ///   come copia: cancellarne una lasciava le gemelle e sembrava che il
    ///   tasto Elimina non facesse niente.
    @discardableResult
    static func ensureList(
        for trip: KBTrip,
        childId: String,
        modelContext: ModelContext,
        createIfMissing: Bool = true
    ) -> String? {
        guard !childId.isEmpty else { return nil }

        let listName = defaultListName(for: trip)

        // Il collegamento punta a una lista che l'utente ha cancellato: il
        // puntatore è morto e va staccato, altrimenti il conteggio dei todo
        // aperti continua a contare le voci di una lista che non c'è più.
        if let linked = trip.todoListId, !linked.isEmpty,
           let deleted = fetchList(id: linked, familyId: trip.familyId, in: modelContext, includeDeleted: true),
           deleted.isDeleted {
            trip.todoListId = nil
            trip.updatedAt = .now
            try? modelContext.save()
            guard createIfMissing else { return nil }
        }

        if let existing = trip.todoListId, !existing.isEmpty,
           let list = fetchList(id: existing, familyId: trip.familyId, in: modelContext) {
            if list.name != listName {
                list.name = listName
                list.updatedAt = .now
                try? modelContext.save()
                SyncCenter.shared.enqueueTodoListUpsert(
                    listId: list.id,
                    familyId: trip.familyId,
                    modelContext: modelContext
                )
            }
            return list.id
        }

        // Lista già esistente di questo viaggio, rimasta scollegata: si
        // riaggancia. Stessa fragilità di nota e album — l'unico legame è
        // `trip.todoListId`, e se si perde si accumulano duplicati.
        let fid = trip.familyId
        let existingDescriptor = FetchDescriptor<KBTodoList>(
            predicate: #Predicate<KBTodoList> { $0.familyId == fid && !$0.isDeleted }
        )
        if let orphan = (try? modelContext.fetch(existingDescriptor))?.first(where: {
            $0.name.trimmingCharacters(in: .whitespaces) == listName.trimmingCharacters(in: .whitespaces)
        }) {
            trip.todoListId = orphan.id
            trip.updatedAt = .now
            try? modelContext.save()
            return orphan.id
        }

        // Nessuna lista da riagganciare: crearne una si fa solo se l'utente
        // l'ha chiesto aprendo i todo del viaggio.
        guard createIfMissing else { return nil }

        let list = KBTodoList(
            familyId: trip.familyId,
            childId: childId,
            name: listName
        )
        modelContext.insert(list)
        trip.todoListId = list.id
        trip.updatedAt = .now
        try? modelContext.save()
        SyncCenter.shared.enqueueTodoListUpsert(
            listId: list.id,
            familyId: trip.familyId,
            modelContext: modelContext
        )
        return list.id
    }

    static func childId(forListId listId: String, familyId: String, in lists: [KBTodoList]) -> String? {
        lists.first(where: { $0.id == listId && $0.familyId == familyId && !$0.isDeleted })?.childId
    }

    static func openTodoCount(listId: String, in todos: [KBTodoItem]) -> Int {
        todos.filter { $0.listId == listId && !$0.isDeleted && !$0.isDone }.count
    }

    private static func fetchList(
        id: String,
        familyId: String,
        in context: ModelContext,
        includeDeleted: Bool = false
    ) -> KBTodoList? {
        let listId = id
        let fid = familyId
        let descriptor = FetchDescriptor<KBTodoList>(
            predicate: #Predicate<KBTodoList> {
                $0.id == listId && $0.familyId == fid && (includeDeleted || !$0.isDeleted)
            }
        )
        return try? context.fetch(descriptor).first
    }
}
