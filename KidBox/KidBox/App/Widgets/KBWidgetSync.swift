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
        // Un solo aggancio per tutti i pulsanti dei widget (dosi e to-do).
        KBWidgetDoseQueue.drainInApp = {
            await MainActor.run { KBWidgetSync.shared.drainPendingDoses() }
            await KBWidgetSync.shared.drainPendingTodos()
            await MainActor.run { KBWidgetSync.shared.drainPendingGrocery() }
        }
        KBWidgetDoseQueue.refreshInApp = {
            await MainActor.run {
                KBWidgetSync.shared.drainPendingDoses()
                KBWidgetSync.shared.drainPendingGrocery()
            }
            await KBWidgetSync.shared.drainPendingTodos()
            await MainActor.run { KBWidgetSync.shared.refresh(force: true) }
        }

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

    // MARK: - Listener per i widget

    private static let listenerConsumer = "homeWidget"
    private var retainedFamilyId: String?

    /// Spesa e to-do si aggiornano dal server solo mentre la loro schermata è
    /// aperta: per il widget restavano vecchi, o vuoti dopo una reinstallazione.
    /// Con almeno un widget KidBox sulla Home, mentre l'app è in primo piano li
    /// teniamo accesi anche noi (letture: solo con widget e solo in primo piano).
    func retainListenersIfNeeded() {
        guard let container else { return }
        let familyId = UserDefaults(suiteName: KBWidgetStore.appGroupId)?
            .string(forKey: "activeFamilyId") ?? ""
        guard !familyId.isEmpty, Auth.auth().currentUser != nil else { return }
        WidgetCenter.shared.getCurrentConfigurations { result in
            let hasWidgets = (try? result.get())?.contains { $0.kind.hasPrefix("KidBoxHomeWidget") } ?? false
            Task { @MainActor in
                guard hasWidgets else { self.releaseListeners(); return }
                if let old = self.retainedFamilyId, old != familyId { self.releaseListeners() }
                self.retainedFamilyId = familyId
                let context = container.mainContext
                SyncCenter.shared.startGroceryRealtime(
                    familyId: familyId, modelContext: context, consumer: Self.listenerConsumer
                )
                // Stesso childId della schermata To-do (primo figlio), così il
                // listener già agganciato non si ricrea a ogni apertura.
                let childId = ((try? context.fetch(FetchDescriptor<KBFamily>(
                    predicate: #Predicate { $0.id == familyId }
                )))?.first?.children.first?.id) ?? ""
                SyncCenter.shared.startTodoRealtime(
                    familyId: familyId, childId: childId, modelContext: context,
                    remote: TodoRemoteStore(), consumer: Self.listenerConsumer
                )
            }
        }
    }

    /// Andando in background: le schermate aperte restano consumatori e
    /// decidono loro; qui si toglie solo la nostra parte.
    func releaseListeners() {
        guard retainedFamilyId != nil else { return }
        retainedFamilyId = nil
        SyncCenter.shared.stopGroceryRealtime(consumer: Self.listenerConsumer)
        SyncCenter.shared.stopTodoRealtime(consumer: Self.listenerConsumer)
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

    /// Scrive come «prese» le dosi segnate dal widget e le manda in sincronizzazione.
    func drainPendingDoses() {
        guard let container else { return }
        let ids = KBWidgetDoseQueue.pending()
        guard !ids.isEmpty else { return }
        let familyId = UserDefaults(suiteName: KBWidgetStore.appGroupId)?
            .string(forKey: "activeFamilyId") ?? ""
        guard !familyId.isEmpty else { return }
        for (id, taken) in ids {
            // «treatmentId|giorno|slot», vedi `doses(...)`.
            let parts = id.split(separator: "|").map(String.init)
            if parts.count == 3, let day = Int(parts[1]), let slot = Int(parts[2]) {
                TreatmentDoseActionHandler.recordDose(
                    treatmentId: parts[0], familyId: familyId,
                    dayOffset: day - 1, slotIndex: slot, taken: taken,
                    modelContext: container.mainContext
                )
            }
            KBWidgetDoseQueue.remove(id)
        }
    }

    /// Chiude i to-do segnati come fatti dal widget.
    func drainPendingTodos() async {
        let ids = KBWidgetTodoQueue.queue.pending()
        guard !ids.isEmpty else { return }
        let familyId = UserDefaults(suiteName: KBWidgetStore.appGroupId)?
            .string(forKey: "activeFamilyId") ?? ""
        for id in ids {
            // Rimosso prima: `run` in caso di errore avvisa da sé con una notifica.
            KBWidgetTodoQueue.queue.remove(id)
            await TodoReminderDoneAction.run(todoId: id, familyId: familyId, childId: "", listId: "", title: "")
        }
    }

    /// Segna come comprate le voci toccate nel widget. Non è un interruttore
    /// come nella lista: se un altro l'ha già comprata, resta comprata.
    func drainPendingGrocery() {
        guard let container else { return }
        let ids = KBWidgetGroceryQueue.queue.pending()
        guard !ids.isEmpty else { return }
        let context = container.mainContext
        let uid = KBUid.current ?? "local"
        let now = Date()
        var touched: [(id: String, familyId: String)] = []
        for id in ids {
            KBWidgetGroceryQueue.queue.remove(id)
            let pid = id
            guard let item = try? context.fetch(FetchDescriptor<KBGroceryItem>(
                predicate: #Predicate { $0.id == pid }
            )).first, !item.isPurchased, !item.isDeleted else { continue }
            item.isPurchased = true
            item.purchasedAt = now
            item.purchasedBy = uid
            item.updatedAt = now
            item.updatedBy = uid
            item.syncState = .pendingUpsert
            item.lastSyncError = nil
            touched.append((item.id, item.familyId))
        }
        guard !touched.isEmpty else { return }
        try? context.save()
        for t in touched {
            SyncCenter.shared.enqueueGroceryUpsert(itemId: t.id, familyId: t.familyId, modelContext: context)
        }
        Task { await SyncCenter.shared.flushGrocery(modelContext: context) }
    }

    func refresh(force: Bool = false) {
        guard let container else { return }
        observePlanIfNeeded()
        drainPendingDoses()
        drainPendingGrocery()
        if !force, !KBWidgetTodoQueue.queue.pending().isEmpty {
            // Il giro dopo (salvataggio → didSave) ricostruisce l'istantanea.
            Task { await drainPendingTodos() }
            return
        }

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
        if KBWidgetStore.write(snapshot, force: force) || force {
            WidgetCenter.shared.reloadAllTimelines()
        }
        KBWidgetPhotos.prepareIfNeeded(familyId: familyId, uid: uid, context: container.mainContext)
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

        // Stessi soggetti del selettore della Salute: figli e membri adulti
        // (per questi l'id è lo uid, come `childId` di cure e piano fitness).
        let children = (try? context.fetch(FetchDescriptor<KBChild>(
            predicate: #Predicate { $0.familyId == familyId },
            sortBy: [SortDescriptor(\.name)]
        ))) ?? []
        let members = (try? context.fetch(FetchDescriptor<KBFamilyMember>(
            predicate: #Predicate { $0.familyId == familyId && $0.isDeleted == false },
            sortBy: [SortDescriptor(\.displayName)]
        ))) ?? []
        snap.profiles = children.map { .init(id: $0.id, name: $0.name) }
            + members.map { m in
                let name = m.displayName?.trimmingCharacters(in: .whitespaces) ?? ""
                let fallback = m.email?.split(separator: "@").first.map(String.init) ?? ""
                return .init(id: m.userId, name: name.isEmpty ? fallback : name)
            }

        snap.doses = doses(familyId: familyId, context: context, today: today, cal: cal)

        if fitnessUnlocked {
            snap.fitness = snap.profiles.compactMap { fitnessProfile(for: $0.id, today: today, cal: cal) }
        }

        let photos = KBWidgetPhotos.snapshotPart(familyId: familyId, context: context)
        snap.photos = photos.photos
        snap.albums = photos.albums
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
        // Nel widget i to-do assegnati a me e quelli di nessuno (ancora da
        // prendere); fuori quelli di un altro membro o presi da fuori dall'app
        // con «Ci penso io». Le liste restano tutte sceglibili anche se vuote,
        // così il widget configurato non perde la lista.
        let visible = items.filter { item in
            guard item.isVisible(to: uid) else { return false }
            let assignee = item.assignedTo ?? ""
            if !assignee.isEmpty { return assignee == uid }
            return (item.assignedExternalName ?? "").isEmpty
        }

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
            predicate: #Predicate { $0.familyId == familyId && $0.isDeleted == false }
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
                    // Riga presente con taken == false = saltata (come nel dettaglio cura).
                    let log = logs.first {
                        $0.treatmentId == t.id && $0.dayNumber == dayNumber && $0.slotIndex == slot
                    }
                    let taken = log?.taken == true
                    out.append(.init(
                        id: "\(t.id)|\(dayNumber)|\(slot)",
                        childId: t.childId,
                        drugName: t.drugName,
                        dosage: dosageLabel(t.dosageValue, t.dosageUnit),
                        time: time,
                        taken: taken,
                        skipped: log != nil && !taken
                    ))
                }
            }
        }
        out.sort { $0.time < $1.time }
        return out
    }

    private static func dosageLabel(_ value: Double, _ unit: String) -> String {
        guard value > 0 else { return "" }   // «0 ml» non dice niente
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
