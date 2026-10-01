//
//  FamilyRequestAvailability.swift
//  KidBox
//
//  «Chi è libero a quell'ora» nel foglio «Chiedi a…».
//
//  Gli eventi del calendario non dicono chi partecipa (solo il figlio e chi li
//  ha creati), quindi non si attribuiscono a nessuno: si mostrano come contesto,
//  «in calendario intorno alle 16:30», e chi chiede giudica da sé. Gli unici
//  impegni davvero di una persona sono i to-do assegnati a lei: quelli sì,
//  accanto al suo nome. Scelta dell'utente del 01/10/2026; stessa regola su
//  Android (`FamilyRequestAvailability.kt`) e web (`requestAvailability`).
//

import Foundation

struct FamilyRequestAvailability {

    struct Item: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
    }

    /// Un'ora prima e un'ora dopo la scadenza.
    static let margin: TimeInterval = 3600

    let around: Date
    /// Eventi di famiglia nella finestra, non attribuiti a nessuno.
    let events: [Item]
    /// uid → to-do assegnati a quel membro nella finestra.
    let busy: [String: [Item]]

    /// `nil` se il to-do non ha una scadenza con orario: senza un'ora non c'è
    /// niente da confrontare.
    static func compute(
        around: Date?,
        todos: [KBTodoItem],
        events: [KBCalendarEvent],
        currentUid: String?
    ) -> FamilyRequestAvailability? {
        guard let around else { return nil }
        let window = DateInterval(start: around.addingTimeInterval(-margin), end: around.addingTimeInterval(margin))

        let eventItems = events
            .filter { !$0.isDeleted }
            .filter {
                KBVisibilityScope.isVisible(
                    scope: $0.visibilityScope,
                    memberIds: $0.visibilityMemberIds,
                    createdBy: $0.createdBy,
                    currentUid: currentUid
                )
            }
            .flatMap { $0.occurrences(in: window) }
            .map { Item(id: $0.id, title: $0.event.title, start: $0.startDate, end: $0.endDate, isAllDay: $0.event.isAllDay) }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.start < rhs.start
            }

        var busy: [String: [Item]] = [:]
        for todo in todos where !todo.isDone && !todo.isDeleted && todo.hasDueTime {
            guard let uid = todo.assignedTo, !uid.isEmpty,
                  let due = todo.dueAt, window.contains(due),
                  KBVisibilityScope.isVisible(
                      scope: todo.visibilityScope,
                      memberIds: todo.visibilityMemberIds ?? [],
                      createdBy: todo.createdBy,
                      currentUid: currentUid
                  )
            else { continue }
            busy[uid, default: []].append(Item(id: todo.id, title: todo.title, start: due, end: due, isAllDay: false))
        }
        for uid in busy.keys { busy[uid]?.sort { $0.start < $1.start } }

        return FamilyRequestAvailability(around: around, events: Array(eventItems.prefix(4)), busy: busy)
    }
}
