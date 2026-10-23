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
    static let enabledKey = "kb_insightsEnabled"
    static let backgroundTaskId = "it.vittorioscocca.kidbox.insights-refresh"

    private var container: ModelContainer?
    private var saveObserver: NSObjectProtocol?
    private var planObserver: AnyCancellable?
    private var scheduled: Task<Void, Never>?

    private init() {}

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            requestRun(reason: "toggle", delay: .zero)
        }
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

        guard isEnabled, KBSubscriptionManager.shared.currentPlan != .free else {
            await KBInsightNotificationScheduler.removeAll()
            return
        }

        let context = container.mainContext
        do {
            let snapshot = try KBInsightSnapshot.load(familyId: familyId, uid: uid, context: context)
            let candidates = KBInsightEngine.evaluate(snapshot, now: Date())
            let changes = try KBInsightStore.reconcile(candidates, familyId: familyId, uid: uid, context: context)
            try await KBInsightNotificationScheduler.sync(familyId: familyId, context: context)
            if !changes.isEmpty {
                KBLog.ai.kbInfo(
                    "InsightRunner[\(reason)]: opened=\(changes.opened.count) rescheduled=\(changes.rescheduled.count) resolved=\(changes.resolved.count)"
                )
            }
        } catch {
            KBLog.ai.kbError("InsightRunner[\(reason)]: \(error.localizedDescription)")
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
