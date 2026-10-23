//
//  KBInsightEngine.swift
//  KidBox
//
//  Motore proattivo: dalle voci di famiglia già in locale ricava le cose
//  rimaste scoperte, senza AI e senza rete. È una funzione pura su una
//  fotografia dei dati (`KBInsightSnapshot`), così le regole si provano con
//  dati finti; la fotografia la scatta `KBInsightSnapshot.load`.
//
//  Ogni candidato ha il suo orario ideale di consegna, anche futuro (la
//  valutazione gira quando cambiano i dati, non a orario, e la notifica deve
//  partire anche se l'app non si riapre) o già passato. Non dipende da «adesso»:
//  due valutazioni sugli stessi dati danno lo stesso risultato, così la
//  riconciliazione non riscrive niente. Quando consegnare davvero lo decide
//  `KBInsightNotificationScheduler`.
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

    struct HousePayment {
        let id: String
        let isDeleted: Bool
        /// Scadenza unica (contratto, rata): ha la precedenza sul giorno del mese.
        let dueDate: Date?
        /// Scadenza ricorrente: giorno del mese (1-31).
        let monthlyDay: Int?
    }

    var housePayments: [HousePayment] = []
    /// Id dei to-do della famiglia, anche fatti: il to-do «Pagare: …» di una
    /// scadenza dice che qualcuno se n'è già occupato.
    var todoIds: Set<String> = []
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
            + unclaimedHousePayments(snapshot, now: now, calendar: calendar)
    }

    // MARK: - To-do senza nessuno

    /// To-do da fare, visibile a questo utente, che nessuno ha preso e scade
    /// nella prossima settimana: avviso il giorno prima alla stessa ora (se è già
    /// passato, appena possibile), urgente sotto le 6 ore.
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
                fireAt: calendar.date(byAdding: .day, value: -1, to: deadline) ?? deadline
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
                fireAt: firstMissing.addingTimeInterval(doseGrace)
            )
        }
    }

    // MARK: - Pagamento di casa senza nessuno

    /// Giorni prima della scadenza in cui si chiede chi paga.
    static let paymentLeadDays = 3
    static let paymentHorizonDays = 7

    /// Id del to-do «Pagare: …» per una scadenza: lo stesso su ogni telefono,
    /// così due genitori che toccano insieme scrivono lo stesso to-do.
    static func paymentTodoId(paymentId: String, due: Date, calendar: Calendar = .current) -> String {
        "hp-\(paymentId)-\(due.kbDayKey(calendar: calendar))"
    }

    /// Prossima scadenza dal giorno `today` compreso: la data unica se c'è e non
    /// è passata, altrimenti il giorno del mese (il 31 diventa l'ultimo del mese).
    static func nextDue(of p: KBInsightSnapshot.HousePayment, today: Date, calendar: Calendar) -> Date? {
        if let date = p.dueDate {
            let day = calendar.startOfDay(for: date)
            return day >= today ? day : nil
        }
        guard let d = p.monthlyDay, (1...31).contains(d) else { return nil }
        for monthOffset in 0...1 {
            guard let month = calendar.date(byAdding: .month, value: monthOffset, to: today),
                  let range = calendar.range(of: .day, in: .month, for: month) else { continue }
            var c = calendar.dateComponents([.year, .month], from: month)
            c.day = min(d, range.count)
            if let due = calendar.date(from: c), due >= today { return due }
        }
        return nil
    }

    /// Pagamento che scade entro una settimana senza il to-do «Pagare: …» di
    /// quella scadenza: avviso 3 giorni prima alle 9, urgente dal giorno prima.
    static func unclaimedHousePayments(
        _ snapshot: KBInsightSnapshot,
        now: Date,
        calendar: Calendar
    ) -> [KBInsightCandidate] {
        let today = calendar.startOfDay(for: now)
        return snapshot.housePayments.compactMap { p in
            guard !p.isDeleted, let due = nextDue(of: p, today: today, calendar: calendar) else { return nil }
            guard let days = calendar.dateComponents([.day], from: today, to: due).day,
                  days <= paymentHorizonDays else { return nil }
            guard !snapshot.todoIds.contains(paymentTodoId(paymentId: p.id, due: due, calendar: calendar)) else { return nil }
            let leadDay = calendar.date(byAdding: .day, value: -paymentLeadDays, to: due) ?? due
            let fireAt = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: leadDay) ?? leadDay
            return KBInsightCandidate(
                type: .housePaymentDue,
                entityId: "\(p.id)@\(due.kbDayKey(calendar: calendar))",
                priority: days <= 1 ? .high : .normal,
                fireAt: fireAt
            )
        }
    }

    private static func time(_ hhmm: String, on day: Date, calendar: Calendar) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }
}
