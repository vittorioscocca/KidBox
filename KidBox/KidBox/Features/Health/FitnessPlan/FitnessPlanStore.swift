//
//  FitnessPlanStore.swift
//  KidBox
//
//  Persistenza locale del piano fitness per profilo (childId).
//  Stessa logica di `MealPlanStore`: generare il piano costa messaggi AI,
//  quindi non va rigenerato a ogni apertura della schermata. Qui però il
//  documento cambia spesso (stati delle sedute, spostamenti), quindi si
//  riscrive a ogni modifica.
//

import Foundation

enum FitnessPlanStore {

    private static let planPrefix = "kidbox.fitnessplan."
    private static let reviewedWeeksPrefix = "kidbox.fitnessplan.reviewedWeeks."
    private static let lastHealthSyncPrefix = "kidbox.fitnessplan.lastHealthSync."

    // MARK: - Piano

    static func load(childId: String) -> FitnessPlanDocument? {
        guard let data = UserDefaults.standard.data(forKey: planPrefix + childId) else { return nil }
        return try? JSONDecoder().decode(FitnessPlanDocument.self, from: data)
    }

    /// Gli id dei profili che hanno un piano salvato su questo dispositivo.
    /// Le chiavi degli altri dati (settimane riviste, ultima sincronizzazione,
    /// storico) hanno lo stesso prefisso e vanno scartate.
    static func storedChildIds() -> [String] {
        let skipped = ["reviewedWeeks.", "lastHealthSync.", "archive."]
        return UserDefaults.standard.dictionaryRepresentation().keys.compactMap { key -> String? in
            guard key.hasPrefix(planPrefix) else { return nil }
            let rest = String(key.dropFirst(planPrefix.count))
            guard !rest.isEmpty, !skipped.contains(where: { rest.hasPrefix($0) }) else { return nil }
            return rest
        }
    }

    static func save(_ document: FitnessPlanDocument, childId: String) {
        guard let data = try? JSONEncoder().encode(document) else { return }
        UserDefaults.standard.set(data, forKey: planPrefix + childId)
        KBLog.persistence.kbInfo(
            "FitnessPlan saved childId=\(childId) sessions=\(document.allSessions.count)"
        )
        // Le corse del piano finiscono nel registro delle scarpe adesso: alla
        // rigenerazione del piano sarebbe tardi.
        FitnessShoeStore.reconcile(plan: document, childId: childId)
        Task { @MainActor in KBWidgetSync.shared.requestRefresh() }
    }

    // MARK: - Storico delle sedute

    private static let archivePrefix = "kidbox.fitnessplan.archive."

    private struct Archive: Codable {
        var sessions: [FitnessSession]
        var workouts: [FitnessLoggedWorkout]
    }

    /// Mette da parte le sedute fatte del piano che sta per sparire (eliminato
    /// dall'utente): il prossimo piano le riprende e lo storico non si perde.
    static func archiveHistory(of plan: FitnessPlanDocument, childId: String) {
        let archive = Archive(sessions: plan.sessionsToArchive, workouts: plan.logged)
        guard !archive.sessions.isEmpty || !archive.workouts.isEmpty,
              let data = try? JSONEncoder().encode(archive) else { return }
        UserDefaults.standard.set(data, forKey: archivePrefix + childId)
    }

    /// Storico che un piano nuovo si porterà dietro, letto senza consumarlo:
    /// serve a raccontarlo all'AI prima della generazione (`carryHistory` lo
    /// consuma dopo). Stessa unione e stessa deduplica.
    static func pendingHistory(
        from old: FitnessPlanDocument?,
        childId: String
    ) -> (sessions: [FitnessSession], workouts: [FitnessLoggedWorkout], missed: [FitnessSession]) {
        var sessions = old?.sessionsToArchive ?? []
        var workouts = old?.logged ?? []
        if let data = UserDefaults.standard.data(forKey: archivePrefix + childId),
           let stored = try? JSONDecoder().decode(Archive.self, from: data) {
            sessions += stored.sessions
            workouts += stored.workouts
        }
        var seen = Set<String>()
        sessions = sessions.filter { seen.insert($0.id).inserted }
        var seenWorkouts = Set<String>()
        workouts = workouts.filter { seenWorkouts.insert($0.id).inserted }
        // Le sedute del piano che sta per sparire e non sono state fatte (saltate
        // o passate senza registrazione): senza queste l'AI non vedrebbe i regressi.
        let today = Calendar.current.startOfDay(for: Date())
        let missed = (old?.allSessions ?? []).filter { session in
            guard !session.isRest else { return false }
            switch session.status {
            case .skipped: return true
            case .planned, .moved: return session.date < today
            case .done: return false
            }
        }
        return (sessions, workouts, missed)
    }

    /// Porta lo storico (del piano corrente o messo da parte) dentro un piano nuovo.
    static func carryHistory(
        into document: FitnessPlanDocument,
        from old: FitnessPlanDocument?,
        childId: String
    ) -> FitnessPlanDocument {
        var sessions = old?.sessionsToArchive ?? []
        var workouts = old?.logged ?? []
        if let data = UserDefaults.standard.data(forKey: archivePrefix + childId),
           let stored = try? JSONDecoder().decode(Archive.self, from: data) {
            sessions += stored.sessions
            workouts += stored.workouts
        }
        UserDefaults.standard.removeObject(forKey: archivePrefix + childId)
        var seen = Set<String>()
        sessions = sessions.filter { seen.insert($0.id).inserted }
        var seenWorkouts = Set<String>()
        workouts = workouts.filter { seenWorkouts.insert($0.id).inserted }
        var result = document
        if !sessions.isEmpty { result.archivedSessions = sessions }
        if !workouts.isEmpty { result.loggedWorkouts = workouts + document.logged }
        return result
    }

    static func clear(childId: String) {
        UserDefaults.standard.removeObject(forKey: planPrefix + childId)
        UserDefaults.standard.removeObject(forKey: reviewedWeeksPrefix + childId)
        UserDefaults.standard.removeObject(forKey: lastHealthSyncPrefix + childId)
    }

    // MARK: - Report settimanali già visti

    /// Settimane per cui l'utente ha già chiuso il report: evita di riproporlo.
    static func reviewedWeeks(childId: String) -> Set<Int> {
        let raw = UserDefaults.standard.array(forKey: reviewedWeeksPrefix + childId) as? [Int] ?? []
        return Set(raw)
    }

    static func markWeekReviewed(_ weekIndex: Int, childId: String) {
        var weeks = reviewedWeeks(childId: childId)
        weeks.insert(weekIndex)
        UserDefaults.standard.set(Array(weeks), forKey: reviewedWeeksPrefix + childId)
    }

    /// Un piano nuovo riparte dalla settimana 1: senza azzerare, i report del
    /// mese successivo nascerebbero già «visti» e non comparirebbero mai.
    static func resetReviewedWeeks(childId: String) {
        UserDefaults.standard.removeObject(forKey: reviewedWeeksPrefix + childId)
    }

    // MARK: - Ultima riconciliazione con Apple Salute

    static func lastHealthSync(childId: String) -> Date? {
        UserDefaults.standard.object(forKey: lastHealthSyncPrefix + childId) as? Date
    }

    static func setLastHealthSync(_ date: Date, childId: String) {
        UserDefaults.standard.set(date, forKey: lastHealthSyncPrefix + childId)
    }
}
