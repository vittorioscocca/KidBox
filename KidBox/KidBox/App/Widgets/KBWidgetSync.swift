//
//  KBWidgetSync.swift
//  KidBox
//
//  Costruisce `KBWidgetSnapshot` dai dati locali e avvisa WidgetKit.
//  Si riscrive dopo ogni salvataggio (con un attimo di pausa per raggruppare),
//  al ritorno in primo piano, al cambio piano e quando cambia il piano Fitness.
//

import Foundation
import SwiftData
import Combine
import WidgetKit
import FirebaseAuth

@MainActor
final class KBWidgetSync {

    static let shared = KBWidgetSync()

    private var container: ModelContainer?
    private var saveObserver: NSObjectProtocol?
    private var planObserver: AnyCancellable?
    private var scheduled: Task<Void, Never>?

    private init() {}

    // MARK: - Avvio

    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container

        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestRefresh() }
        }
    }

    /// Non in `start`: gira in `App.init`, prima che Firebase sia configurato.
    private func observePlanIfNeeded() {
        guard planObserver == nil else { return }
        planObserver = KBSubscriptionManager.shared.$currentPlan
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.requestRefresh() }
            }
    }

    /// Le richieste ravvicinate si fondono in una sola.
    func requestRefresh(delay: Duration = .seconds(2)) {
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: - Un giro

    func refresh() {
        guard let container else { return }
        observePlanIfNeeded()

        let familyId = UserDefaults(suiteName: KBWidgetStore.appGroupId)?
            .string(forKey: "activeFamilyId") ?? ""
        guard !familyId.isEmpty, let uid = Auth.auth().currentUser?.uid else {
            // Uscito o senza famiglia: il widget non deve restare con dati altrui.
            KBWidgetStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        let snapshot = Self.build(
            familyId: familyId,
            uid: uid,
            context: container.mainContext,
            fitnessUnlocked: KBSubscriptionManager.shared.currentPlan != .free
        )
        if KBWidgetStore.write(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Costruzione

    static func build(
        familyId: String,
        uid: String,
        context: ModelContext,
        fitnessUnlocked: Bool,
        now: Date = Date()
    ) -> KBWidgetSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        let familyName = (try? context.fetch(
            FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == familyId })
        ))?.first?.name ?? ""

        var snap = KBWidgetSnapshot(
            familyId: familyId,
            familyName: familyName,
            updatedAt: now,
            fitnessUnlocked: fitnessUnlocked
        )

        snap.events = events(familyId: familyId, uid: uid, context: context, today: today, cal: cal)
        snap.todoLists = todoLists(familyId: familyId, uid: uid, context: context)
        snap.grocery = grocery(familyId: familyId, context: context)

        let children = (try? context.fetch(FetchDescriptor<KBChild>(
            predicate: #Predicate { $0.familyId == familyId },
            sortBy: [SortDescriptor(\.name)]
        ))) ?? []
        snap.profiles = children.map { .init(id: $0.id, name: $0.name) }

        snap.doses = doses(familyId: familyId, context: context, today: today, cal: cal)

        if fitnessUnlocked {
            snap.fitness = children.compactMap { fitnessProfile(for: $0.id, today: today, cal: cal) }
        }
        return snap
    }

    // MARK: Calendario

    private static func events(
        familyId: String, uid: String, context: ModelContext, today: Date, cal: Calendar
    ) -> [KBWidgetSnapshot.Event] {
        let rows = (try? context.fetch(FetchDescriptor<KBCalendarEvent>(
            predicate: #Predicate { $0.familyId == familyId && $0.isDeleted == false }
        ))) ?? []

        let end = cal.date(byAdding: .day, value: 15, to: today) ?? today
        let window = DateInterval(start: today, end: end)

        var out: [KBWidgetSnapshot.Event] = []
        for event in rows where event.isVisible(to: uid) {
            for occ in event.occurrences(in: window, calendar: cal) {
                out.append(.init(
                    id: occ.id,
                    title: event.title,
                    start: occ.startDate,
                    end: occ.endDate,
                    isAllDay: event.isAllDay,
                    colorHex: event.category.color
                ))
            }
        }
        out.sort { $0.start < $1.start }
        return Array(out.prefix(40))
    }

    // MARK: To-do

    private static func todoLists(
        familyId: String, uid: String, context: ModelContext
    ) -> [KBWidgetSnapshot.TodoList] {
        let lists = (try? context.fetch(FetchDescriptor<KBTodoList>(
            predicate: #Predicate { $0.familyId == familyId && $0.isDeleted == false },
            sortBy: [SortDescriptor(\.name)]
        ))) ?? []
        let items = (try? context.fetch(FetchDescriptor<KBTodoItem>(
            predicate: #Predicate {
                $0.familyId == familyId && $0.isDeleted == false && $0.isDone == false
            }
        ))) ?? []
        let visible = items.filter { $0.isVisible(to: uid) }

        func rows(_ list: [KBTodoItem]) -> (Int, [KBWidgetSnapshot.TodoItem]) {
            let sorted = list.sorted {
                switch ($0.dueAt, $1.dueAt) {
                case let (a?, b?): return a < b
                case (_?, nil):    return true
                case (nil, _?):    return false
                default:           return $0.createdAt < $1.createdAt
                }
            }
            return (sorted.count, sorted.prefix(12).map {
                .init(id: $0.id, title: $0.title, due: $0.dueAt,
                      hasTime: $0.dueAt != nil && $0.hasDueTime, isUrgent: $0.isUrgent)
            })
        }

        var out: [KBWidgetSnapshot.TodoList] = lists.map { list in
            let (count, top) = rows(visible.filter { $0.listId == list.id })
            return .init(id: list.id, name: list.name, openCount: count, items: top)
        }
        // «Senza lista»: nome vuoto, lo traduce il widget.
        let orphans = visible.filter { item in
            guard let id = item.listId, !id.isEmpty else { return true }
            return !lists.contains { $0.id == id }
        }
        if !orphans.isEmpty {
            let (count, top) = rows(orphans)
            out.append(.init(id: "", name: "", openCount: count, items: top))
        }
        return out
    }

    // MARK: Spesa

    private static func grocery(familyId: String, context: ModelContext) -> [KBWidgetSnapshot.GroceryItem] {
        let rows = (try? context.fetch(FetchDescriptor<KBGroceryItem>(
            predicate: #Predicate {
                $0.familyId == familyId && $0.isDeleted == false && $0.isPurchased == false
            },
            sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []
        return rows.prefix(60).map {
            .init(id: $0.id, name: $0.name, category: $0.category, quantity: $0.quantity)
        }
    }

    // MARK: Cure

    /// Dosi di oggi e di domani delle cure attive, con lo stato «presa».
    private static func doses(
        familyId: String, context: ModelContext, today: Date, cal: Calendar
    ) -> [KBWidgetSnapshot.Dose] {
        let treatments = (try? context.fetch(FetchDescriptor<KBTreatment>(
            predicate: #Predicate {
                $0.familyId == familyId && $0.isDeleted == false && $0.isActive == true
            }
        ))) ?? []
        guard !treatments.isEmpty else { return [] }
        let logs = (try? context.fetch(FetchDescriptor<KBDoseLog>(
            predicate: #Predicate { $0.familyId == familyId && $0.isDeleted == false && $0.taken == true }
        ))) ?? []

        var out: [KBWidgetSnapshot.Dose] = []
        for t in treatments where t.petId.isEmpty {
            let startDay = cal.startOfDay(for: t.startDate)
            for dayDelta in 0...1 {
                guard let day = cal.date(byAdding: .day, value: dayDelta, to: today) else { continue }
                let offset = cal.dateComponents([.day], from: startDay, to: day).day ?? -1
                guard offset >= 0,
                      t.isLongTerm || offset < t.durationDays,
                      t.isScheduledDoseDay(calendarDayOffsetFromStart: offset) else { continue }

                let dayNumber = offset + 1
                for (slot, hhmm) in t.scheduleTimes.enumerated() {
                    let parts = hhmm.split(separator: ":").compactMap { Int($0) }
                    guard parts.count == 2,
                          let time = cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
                    else { continue }
                    let taken = logs.contains {
                        $0.treatmentId == t.id && $0.dayNumber == dayNumber && $0.slotIndex == slot
                    }
                    out.append(.init(
                        id: "\(t.id)|\(dayNumber)|\(slot)",
                        childId: t.childId,
                        drugName: t.drugName,
                        dosage: dosageLabel(t.dosageValue, t.dosageUnit),
                        time: time,
                        taken: taken
                    ))
                }
            }
        }
        out.sort { $0.time < $1.time }
        return out
    }

    private static func dosageLabel(_ value: Double, _ unit: String) -> String {
        let number = value == value.rounded() ? String(Int(value)) : String(value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    // MARK: Fitness

    private static func fitnessProfile(
        for childId: String, today: Date, cal: Calendar
    ) -> KBWidgetSnapshot.FitnessProfile? {
        guard let plan = FitnessPlanStore.load(childId: childId) else { return nil }
        let end = cal.date(byAdding: .day, value: 15, to: today) ?? today
        let sessions = plan.allSessions
            .filter { $0.date >= today && $0.date < end }
            .sorted { $0.date < $1.date }
            .map {
                KBWidgetSnapshot.FitnessSession(
                    id: $0.id,
                    date: $0.date,
                    title: $0.title,
                    activityType: $0.activityType,
                    minutes: $0.durationMinutes,
                    isDone: $0.status == .done,
                    isSkipped: $0.status == .skipped
                )
            }
        return .init(id: childId, sessions: Array(sessions.prefix(14)))
    }
}
