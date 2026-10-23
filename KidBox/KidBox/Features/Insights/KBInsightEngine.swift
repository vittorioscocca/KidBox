//
//  KBInsightEngine.swift
//  KidBox
//
//  Motore proattivo: dalle voci di famiglia già in locale ricava le cose
//  rimaste scoperte, senza AI e senza rete. È una funzione pura su una
//  fotografia dei dati (`KBInsightSnapshot`), così le regole si provano con
//  dati finti; la fotografia la scatta `KBInsightSnapshot.load`.
//
//  Ogni candidato ha già il suo orario di consegna, anche futuro: la
//  valutazione gira quando cambiano i dati, non a orario, e la notifica deve
//  partire anche se l'app nel frattempo non si riapre.
//

import Foundation

/// Le voci che le regole leggono, staccate da SwiftData.
struct KBInsightSnapshot {

    struct Todo {
        let id: String
        let dueAt: Date?
        let hasDueTime: Bool
        let isDone: Bool
        let isDeleted: Bool
        /// Uid di un membro oppure nome di chi l'ha presa da fuori dall'app.
        let isTaken: Bool
        let isVisibleToUser: Bool
    }

    struct Treatment {
        let id: String
        let isActive: Bool
        let isDeleted: Bool
        let isLongTerm: Bool
        let durationDays: Int
        let startDate: Date
        let endDate: Date?
        let intervalBetweenDosesDays: Int
        /// «08:00», «20:00»…
        let scheduleTimes: [String]
    }

    struct DoseLog {
        let treatmentId: String
        let dayNumber: Int
        let slotIndex: Int
        let taken: Bool
        let isDeleted: Bool
    }

    var todos: [Todo] = []
    var treatments: [Treatment] = []
    var doseLogs: [DoseLog] = []
}

/// Un insight come lo propone una regola: diventa una riga `KBInsight` nel
/// `KBInsightStore`, che ne conserva lo stato fra una valutazione e l'altra.
struct KBInsightCandidate: Equatable {
    let type: KBInsightType
    let entityId: String
    let priority: KBInsightPriority
    let fireAt: Date
}

enum KBInsightEngine {

    /// Quanto avanti si guarda per i to-do: oltre, la prossima valutazione arriva prima.
    static let todoHorizon: TimeInterval = 7 * 24 * 3600
    /// Margine dopo l'orario della dose prima di dire che manca.
    static let doseGrace: TimeInterval = 3600

    static func evaluate(
        _ snapshot: KBInsightSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> [KBInsightCandidate] {
        unassignedTodos(snapshot.todos, now: now, calendar: calendar)
            + missingDoses(snapshot, now: now, calendar: calendar)
    }

    // MARK: - To-do senza nessuno

    /// To-do da fare, visibile a questo utente, che nessuno ha preso e scade
    /// nella prossima settimana: avviso il giorno prima alla stessa ora (subito
    /// se la scadenza è più vicina), urgente sotto le 6 ore.
    static func unassignedTodos(
        _ todos: [KBInsightSnapshot.Todo],
        now: Date,
        calendar: Calendar
    ) -> [KBInsightCandidate] {
        todos.compactMap { todo in
            guard !todo.isDone, !todo.isDeleted, !todo.isTaken, todo.isVisibleToUser,
                  let dueAt = todo.dueAt else { return nil }
            // Senza orario la scadenza è la fine di quel giorno.
            let deadline = todo.hasDueTime
                ? dueAt
                : calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dueAt)) ?? dueAt
            let left = deadline.timeIntervalSince(now)
            guard left > 0, left <= todoHorizon else { return nil }
            return KBInsightCandidate(
                type: .todoUnassignedDueSoon,
                entityId: todo.id,
                priority: left <= 6 * 3600 ? .high : .normal,
                // Il giorno prima alla stessa ora, anche a cavallo del cambio d'ora.
                fireAt: max(now, calendar.date(byAdding: .day, value: -1, to: deadline) ?? deadline)
            )
        }
    }

    // MARK: - Dose non registrata

    /// Cura attiva con una dose di oggi non segnata come presa un'ora dopo
    /// l'orario previsto. Un insight per cura e per giorno, all'orario della
    /// prima dose scoperta: il giorno dopo è un insight nuovo, non lo stesso
    /// già chiuso o scartato.
    static func missingDoses(
        _ snapshot: KBInsightSnapshot,
        now: Date,
        calendar: Calendar
    ) -> [KBInsightCandidate] {
        let today = calendar.startOfDay(for: now)
        let taken = Set(
            snapshot.doseLogs
                .filter { $0.taken && !$0.isDeleted }
                .map { "\($0.treatmentId)|\($0.dayNumber)|\($0.slotIndex)" }
        )

        return snapshot.treatments.compactMap { t in
            guard t.isActive, !t.isDeleted else { return nil }
            let start = calendar.startOfDay(for: t.startDate)
            guard let offset = calendar.dateComponents([.day], from: start, to: today).day,
                  offset >= 0 else { return nil }
            if !t.isLongTerm, offset >= t.durationDays { return nil }
            if let end = t.endDate, calendar.startOfDay(for: end) < today { return nil }
            if t.intervalBetweenDosesDays > 0, offset % t.intervalBetweenDosesDays != 0 { return nil }

            let dayNumber = offset + 1
            let firstMissing = t.scheduleTimes.enumerated().compactMap { slot, time -> Date? in
                guard !taken.contains("\(t.id)|\(dayNumber)|\(slot)"),
                      let at = Self.time(time, on: today, calendar: calendar) else { return nil }
                return at
            }.min()
            guard let firstMissing else { return nil }

            return KBInsightCandidate(
                type: .treatmentDoseMissing,
                entityId: "\(t.id)@\(today.kbDayKey(calendar: calendar))",
                priority: .high,
                fireAt: max(now, firstMissing.addingTimeInterval(doseGrace))
            )
        }
    }

    private static func time(_ hhmm: String, on day: Date, calendar: Calendar) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }
}
