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
    @discardableResult
    static func ensureList(
        for trip: KBTrip,
        childId: String,
        modelContext: ModelContext
    ) -> String? {
        guard !childId.isEmpty else { return nil }

        let listName = defaultListName(for: trip)

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

    private static func fetchList(id: String, familyId: String, in context: ModelContext) -> KBTodoList? {
        let listId = id
        let fid = familyId
        let descriptor = FetchDescriptor<KBTodoList>(
            predicate: #Predicate<KBTodoList> {
                $0.id == listId && $0.familyId == fid && !$0.isDeleted
            }
        )
        return try? context.fetch(descriptor).first
    }
}
