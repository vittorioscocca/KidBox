//
//  KBInsightRunner.swift
//  KidBox
//
//  Quando gira il motore proattivo: a ogni salvataggio dei dati locali (sync
//  in arrivo, modifiche dell'utente, dose registrata), al ritorno in primo
//  piano, al cambio di piano e in background con `BGAppRefreshTask`. Le
//  richieste ravvicinate si raccolgono in un solo giro.
//
//  Un giro: fotografia → regole → riconciliazione → notifiche. Tutto locale:
//  nessuna lettura Firestore, nessuna chiamata AI.
//
//  È una funzione Pro/Max come il resto della Mente proattiva. Il piano qui si
//  legge dalla copia già in memoria, senza rileggerlo: non c'è un costo da
//  proteggere, e quando il piano arriva il giro riparte da solo.
//

import BackgroundTasks
import Combine
import FirebaseAuth
import Foundation
import SwiftData

@MainActor
final class KBInsightRunner {

    static let shared = KBInsightRunner()
    static let backgroundTaskId = "it.vittorioscocca.kidbox.insights-refresh"

    private var container: ModelContainer?
    private var saveObserver: NSObjectProtocol?
    private var planObserver: AnyCancellable?
    private var scheduled: Task<Void, Never>?
    /// Le preferenze sono cambiate: al prossimo giro le consegne future si
    /// ricalcolano. Resta acceso anche se quel giro viene sostituito da un altro.
    private var needsDeliveryReset = false

    private init() {}

    func preferencesDidChange() {
        needsDeliveryReset = true
        requestRun(reason: "prefs", delay: .zero)
    }

    /// Le notifiche in coda si riscrivono da capo: la data del to-do («domani,
    /// 09:00») è testo formattato e la ritraduzione delle chiavi non la tocca.
    func languageDidChange() {
        needsDeliveryReset = true
        requestRun(reason: "language", delay: .zero)
    }

    // MARK: - Avvio

    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container

        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] note in
            let onlyInsights = Self.touchesOnlyInsights(note)
            MainActor.assumeIsolated {
                guard !onlyInsights else { return }
                self?.requestRun(reason: "save")
            }
        }
    }

    /// Non in `start`: quello gira in `App.init`, prima che Firebase sia
    /// configurato, e `KBSubscriptionManager` tocca Firestore appena nasce.
    private func observePlanIfNeeded() {
        guard planObserver == nil else { return }
        planObserver = KBSubscriptionManager.shared.$currentPlan
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.requestRun(reason: "plan") }
            }
    }

    /// Le richieste che arrivano entro `delay` dalla precedente la sostituiscono.
    func requestRun(reason: String, delay: Duration = .seconds(2)) {
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.run(reason: reason)
        }
    }

    // MARK: - Un giro

    func run(reason: String) async {
        guard let container else { return }
        let familyId = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
            .string(forKey: "activeFamilyId") ?? ""
        guard !familyId.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        observePlanIfNeeded()
        // Un altro dispositivo può aver cambiato le preferenze: se sì, il giro
        // riparte da solo con quelle nuove.
        Task { await KBInsightPreferencesStore.shared.refreshFromRemoteIfNeeded() }

        let prefs = KBInsightPreferencesStore.shared.prefs
        guard prefs.delivery != .off, KBSubscriptionManager.shared.currentPlan != .free else {
            await KBInsightNotificationScheduler.removeAll()
            return
        }

        let context = container.mainContext
        let resetFuture = needsDeliveryReset
        needsDeliveryReset = false
        do {
            let snapshot = try KBInsightSnapshot.load(familyId: familyId, uid: uid, context: context)
            // Un tipo spento non propone niente: le sue righe aperte si chiudono,
            // e si riaprono da sole se l'utente lo riaccende.
            let candidates = KBInsightEngine.evaluate(snapshot, now: Date())
                .filter { !prefs.isMuted($0.type) }
            let changes = try KBInsightStore.reconcile(candidates, familyId: familyId, uid: uid, context: context)
            reportActed(resolved: changes.resolved, prefs: prefs, context: context)
            try await KBInsightNotificationScheduler.sync(
                familyId: familyId, prefs: prefs, resetFuture: resetFuture, context: context
            )
            if !changes.isEmpty {
                KBLog.ai.kbInfo(
                    "InsightRunner[\(reason)]: opened=\(changes.opened.count) rescheduled=\(changes.rescheduled.count) resolved=\(changes.resolved.count)"
                )
            }
        } catch {
            KBLog.ai.kbError("InsightRunner[\(reason)]: \(error.localizedDescription)")
        }
    }

    /// Avvisi già arrivati che si sono chiusi perché il problema non c'è più:
    /// qualcuno ha agito dall'app (to-do preso, dose registrata).
    private func reportActed(resolved: [String], prefs: KBInsightPreferences, context: ModelContext) {
        guard !resolved.isEmpty else { return }
        let ids = Set(resolved)
        let rows = (try? context.fetch(FetchDescriptor<KBInsight>()))?.filter { ids.contains($0.id) } ?? []
        let now = Date()
        for row in rows {
            guard row.shownReportedAt != nil, let type = row.type, !prefs.isMuted(type) else { continue }
            AppAnalytics.insightActed(
                type: type.rawValue,
                via: "app",
                minutes: KBInsightActionHandler.minutesSinceShown(row, now: now)
            )
        }
    }

    // MARK: - Background

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskId, using: .main) { task in
            MainActor.assumeIsolated {
                KBInsightRunner.shared.handleBackground(task: task)
            }
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            KBLog.ai.kbDebug("InsightRunner: background refresh not scheduled \(error.localizedDescription)")
        }
    }

    private func handleBackground(task: BGTask) {
        scheduleBackgroundRefresh()
        let work = Task { @MainActor in
            await run(reason: "background")
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    // MARK: - Helpers

    /// Un salvataggio che tocca solo le righe degli insight è il motore stesso:
    /// rilanciarlo non cambierebbe niente.
    private nonisolated static func touchesOnlyInsights(_ note: Notification) -> Bool {
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        let ids = keys.flatMap { note.userInfo?[$0.rawValue] as? [PersistentIdentifier] ?? [] }
        return !ids.isEmpty && ids.allSatisfy { $0.entityName == String(describing: KBInsight.self) }
    }
}
