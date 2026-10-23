//
//  KBInsightStore.swift
//  KidBox
//
//  Ponte fra il motore e SwiftData: scatta la fotografia delle voci di una
//  famiglia e riconcilia i candidati con le righe `KBInsight` già salvate.
//
//  Riconciliare vuol dire:
//  - candidato nuovo → riga nuova (stato `new`);
//  - candidato già noto → stesso stato, orario e priorità aggiornati; una riga
//    chiusa dal motore (`done`) torna `new` se la regola scatta di nuovo, una
//    scartata dall'utente (`dismissed`) resta scartata;
//  - riga aperta che nessuna regola propone più → `done`: il problema si è
//    risolto (to-do preso, dose registrata).
//

import Foundation
import SwiftData

extension KBInsightSnapshot {

    @MainActor
    static func load(familyId: String, uid: String, context: ModelContext) throws -> KBInsightSnapshot {
        let fid = familyId
        let todos = try context.fetch(FetchDescriptor<KBTodoItem>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false && $0.isDone == false }
        ))
        let treatments = try context.fetch(FetchDescriptor<KBTreatment>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false && $0.isActive == true }
        ))
        let treatmentIds = Set(treatments.map(\.id))
        let logs = try context.fetch(FetchDescriptor<KBDoseLog>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false && $0.taken == true }
        )).filter { treatmentIds.contains($0.treatmentId) }

        let payments = try context.fetch(FetchDescriptor<KBHousePayment>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        ))
        let allTodoIds = try context.fetch(FetchDescriptor<KBTodoItem>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        )).map(\.id)

        return KBInsightSnapshot(
            todos: todos.map {
                Todo(
                    id: $0.id,
                    dueAt: $0.dueAt,
                    hasDueTime: $0.hasDueTime,
                    isDone: $0.isDone,
                    isDeleted: $0.isDeleted,
                    isTaken: !($0.assignedTo ?? "").isEmpty || !($0.assignedExternalName ?? "").isEmpty,
                    isVisibleToUser: $0.isVisible(to: uid)
                )
            },
            treatments: treatments.map {
                Treatment(
                    id: $0.id,
                    isActive: $0.isActive,
                    isDeleted: $0.isDeleted,
                    isLongTerm: $0.isLongTerm,
                    durationDays: $0.durationDays,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    intervalBetweenDosesDays: $0.intervalBetweenDosesDays,
                    scheduleTimes: $0.scheduleTimes
                )
            },
            doseLogs: logs.map {
                DoseLog(
                    treatmentId: $0.treatmentId,
                    dayNumber: $0.dayNumber,
                    slotIndex: $0.slotIndex,
                    taken: $0.taken,
                    isDeleted: $0.isDeleted
                )
            },
            housePayments: payments.map {
                HousePayment(
                    id: $0.id,
                    isDeleted: $0.isDeleted,
                    dueDate: $0.dataScadenza,
                    monthlyDay: $0.giornoDiScadenzaMensile
                )
            },
            todoIds: Set(allTodoIds)
        )
    }
}

enum KBInsightStore {

    /// Cosa è cambiato: la consegna (notifiche, feed) riparte da qui.
    struct Changes: Equatable {
        var opened: [String] = []
        var rescheduled: [String] = []
        var resolved: [String] = []

        var isEmpty: Bool { opened.isEmpty && rescheduled.isEmpty && resolved.isEmpty }
    }

    @MainActor
    @discardableResult
    static func reconcile(
        _ candidates: [KBInsightCandidate],
        familyId: String,
        uid: String,
        now: Date = Date(),
        context: ModelContext
    ) throws -> Changes {
        let fid = familyId
        let existing = try context.fetch(FetchDescriptor<KBInsight>(
            predicate: #Predicate { $0.familyId == fid }
        ))
        var byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changes = Changes()
        var proposed = Set<String>()

        for c in candidates {
            let key = KBInsight.key(familyId: familyId, type: c.type, entityId: c.entityId)
            proposed.insert(key)
            if let row = byId[key] {
                let before = (row.state, row.priority, row.fireAt)
                if row.state == .done {
                    row.mark(.new, now: now)
                }
                row.refresh(priority: c.priority, fireAt: c.fireAt, now: now)
                if before.0 != row.state {
                    changes.opened.append(key)
                } else if row.state.isOpen, before.1 != row.priority || before.2 != row.fireAt {
                    changes.rescheduled.append(key)
                }
            } else {
                let row = KBInsight(
                    familyId: familyId,
                    recipientUid: uid,
                    type: c.type,
                    entityId: c.entityId,
                    priority: c.priority,
                    fireAt: c.fireAt,
                    now: now
                )
                context.insert(row)
                byId[key] = row
                changes.opened.append(key)
            }
        }

        // Solo i tipi che questa build sa valutare: una riga di un tipo che non
        // conosce non è «risolta», è solo fuori dalla sua portata.
        for row in existing where row.state.isOpen && row.type != nil && !proposed.contains(row.id) {
            row.mark(.done, now: now)
            changes.resolved.append(row.id)
        }

        if context.hasChanges { try context.save() }
        return changes
    }
}
