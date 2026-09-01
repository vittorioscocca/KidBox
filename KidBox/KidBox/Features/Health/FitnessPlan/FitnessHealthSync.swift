//
//  FitnessHealthSync.swift
//  KidBox
//
//  Riconciliazione tra il piano e gli allenamenti registrati da Apple Salute
//  (Apple Watch, Garmin e ogni altra sorgente che scrive su HealthKit).
//
//  Due inneschi, come da specifica:
//  - passivo, all'apertura dell'app (`FitnessPlanForegroundSync`);
//  - attivo, dal pulsante "Sincronizza ora" nella dashboard.
//

import Foundation

enum FitnessHealthSync {

    /// Quanto deve durare un allenamento, in proporzione alla seduta prevista,
    /// perché valga come completata. Sotto questa soglia resta "da fare": una
    /// camminata di 5 minuti non chiude una seduta di forza da 45.
    private static let minimumDurationRatio = 0.5

    /// Minuti minimi comunque richiesti, anche per sedute brevi.
    private static let minimumMinutes = 10

    struct Result {
        let plan: FitnessPlanDocument
        let matchedSessions: [FitnessSession]

        var didChange: Bool { !matchedSessions.isEmpty }
    }

    /// Confronta le attività lette da Apple Salute con le sedute pianificate e
    /// chiude quelle coperte da un allenamento reale.
    ///
    /// Si guardano solo le sedute **passate o di oggi** e ancora `planned`:
    /// una seduta già chiusa a mano non viene toccata, e una futura non può
    /// essere completata in anticipo.
    @MainActor
    static func reconcile(plan: FitnessPlanDocument) async -> Result {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let pending = plan.allSessions.filter {
            !$0.isRest && $0.status == .planned && $0.date <= today
        }
        guard !pending.isEmpty else {
            return Result(plan: plan, matchedSessions: [])
        }

        let windowStart = pending.map(\.date).min() ?? plan.startDate
        let workouts = await KBHealthKitService.shared.workouts(since: windowStart)
        guard !workouts.isEmpty else {
            return Result(plan: plan, matchedSessions: [])
        }

        // Un allenamento chiude al massimo una seduta: senza questo insieme una
        // corsa lunga chiuderebbe tutte le sedute arretrate dello stesso giorno.
        var usedWorkoutIds = Set(plan.allSessions.compactMap(\.matchedWorkoutId))
        var updated = plan
        var matched: [FitnessSession] = []

        for session in pending.sorted(by: { $0.date < $1.date }) {
            let sameDay = workouts.filter {
                !usedWorkoutIds.contains($0.id) && cal.isDate($0.startedAt, inSameDayAs: session.date)
            }
            guard let workout = bestMatch(for: session, among: sameDay) else { continue }

            usedWorkoutIds.insert(workout.id)
            updated.updateSession(id: session.id) { target in
                target.status = .done
                target.completedAt = workout.startedAt
                target.completionSource = .healthKit
                target.matchedWorkoutId = workout.id
                target.actualMinutes = workout.durationMinutes
                target.actualKcal = workout.activeEnergyKcal.map { Int($0.rounded()) }
            }
            if let closed = updated.session(id: session.id) {
                matched.append(closed)
            }
        }

        KBLog.sync.kbInfo(
            "FitnessHealthSync: pending=\(pending.count) workouts=\(workouts.count) matched=\(matched.count)"
        )
        return Result(plan: updated, matchedSessions: matched)
    }

    /// Tra gli allenamenti dello stesso giorno vince quello abbastanza lungo e,
    /// a parità, quello con la disciplina più vicina al tipo di seduta.
    private static func bestMatch(
        for session: FitnessSession,
        among workouts: [KBHealthWorkoutEntry]
    ) -> KBHealthWorkoutEntry? {
        let required = max(
            minimumMinutes,
            Int(Double(session.durationMinutes) * minimumDurationRatio)
        )
        let eligible = workouts.filter { ($0.durationMinutes ?? 0) >= required }
        guard !eligible.isEmpty else { return nil }

        if let sameDiscipline = eligible.first(where: { matchesDiscipline($0, session: session) }) {
            return sameDiscipline
        }
        return eligible.max { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }
    }

    /// Corrispondenza grossolana tra il titolo Apple Salute ("Corsa all'aperto")
    /// e il tipo di seduta prodotto dall'AI ("corsa", "forza", …).
    private static func matchesDiscipline(
        _ workout: KBHealthWorkoutEntry,
        session: FitnessSession
    ) -> Bool {
        let workoutTitle = workout.title.lowercased()
        let sessionText = (session.activityType + " " + session.title).lowercased()
        let families: [[String]] = [
            ["cors", "run", "jog"],
            ["camm", "walk"],
            ["forza", "pesi", "strength", "funzional", "tonific"],
            ["hiit", "intervall", "circuit"],
            ["bici", "cicl", "cycl", "spinning"],
            ["nuot", "swim"],
            ["yoga", "pilates", "stretch", "mobil", "flessib"],
        ]
        return families.contains { keys in
            keys.contains(where: { workoutTitle.contains($0) })
                && keys.contains(where: { sessionText.contains($0) })
        }
    }
}

// MARK: - Trigger passivo

/// Riconciliazione all'apertura dell'app, per i profili che hanno un piano.
///
/// È volutamente silenziosa: aggiorna il piano salvato e lo risincronizza, la
/// dashboard lo rilegge quando viene aperta.
enum FitnessPlanForegroundSync {

    /// Non ha senso rileggere HealthKit a ogni ritorno in foreground.
    private static let minimumInterval: TimeInterval = 30 * 60

    @MainActor
    static func runIfNeeded(childId: String, force: Bool = false) async {
        guard var plan = FitnessPlanStore.load(childId: childId) else { return }
        if !force, let last = FitnessPlanStore.lastHealthSync(childId: childId),
           Date().timeIntervalSince(last) < minimumInterval {
            return
        }

        let result = await FitnessHealthSync.reconcile(plan: plan)
        FitnessPlanStore.setLastHealthSync(Date(), childId: childId)
        guard result.didChange else { return }

        plan = result.plan
        FitnessPlanStore.save(plan, childId: childId)
        await FitnessPlanRemoteStore.upsert(plan, childId: childId)
        // Le sedute chiuse non devono più suonare.
        await FitnessPlanNotificationManager.reschedule(plan: plan, childId: childId)
        NotificationCenter.default.post(name: .fitnessPlanDidChange, object: nil)
    }
}
