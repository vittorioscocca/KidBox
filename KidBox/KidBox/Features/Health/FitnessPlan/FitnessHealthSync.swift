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
        /// Allenamenti svolti che non corrispondono a nessuna seduta prevista.
        let loggedWorkouts: [FitnessLoggedWorkout]
        /// Sedute riaperte perché chiuse da un'attività di un'altra disciplina.
        let repairedSessions: Int

        var didChange: Bool {
            !matchedSessions.isEmpty || !loggedWorkouts.isEmpty || repairedSessions > 0
        }
    }

    /// Confronta le attività lette da Apple Salute con le sedute pianificate e
    /// chiude quelle coperte da un allenamento reale.
    ///
    /// Si guardano solo le sedute **passate o di oggi** e ancora `planned`:
    /// una seduta già chiusa a mano non viene toccata, e una futura non può
    /// essere completata in anticipo.
    @MainActor
    static func reconcile(plan: FitnessPlanDocument) async -> Result {
        // Si rilegge dall'inizio del piano, non dalla prima seduta aperta: serve
        // anche a ricontrollare le sedute già chiuse (vedi la riparazione) e a
        // registrare le attività dei giorni senza nulla in programma.
        let workouts = await KBHealthKitService.shared.workouts(
            since: Calendar.current.startOfDay(for: plan.startDate)
        )
        return reconcile(plan: plan, workouts: workouts)
    }

    /// La logica, separata dalla lettura di HealthKit perché sia verificabile
    /// senza un device e senza dati sanitari veri.
    static func reconcile(
        plan: FitnessPlanDocument,
        workouts: [KBHealthWorkoutEntry],
        now: Date = Date()
    ) -> Result {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        guard !workouts.isEmpty else {
            return Result(plan: plan, matchedSessions: [], loggedWorkouts: [], repairedSessions: 0)
        }

        var updated = plan
        var matched: [FitnessSession] = []

        // Riparazione dei dati lasciati dalla vecchia euristica, che in mancanza
        // di corrispondenza chiudeva una seduta con l'allenamento più lungo del
        // giorno: una corsa poteva risultare "bici svolta". Quelle sedute vanno
        // riaperte, altrimenti il calendario continua a dichiarare un
        // allenamento mai fatto e l'attività vera resta invisibile.
        var repaired = 0
        for session in plan.allSessions
        where session.status == .done && session.completionSource == .healthKit {
            guard
                let workoutId = session.matchedWorkoutId,
                let workout = workouts.first(where: { $0.id == workoutId })
            else { continue }

            let sameDiscipline = FitnessDisciplineMatcher.matches(
                activityTitle: workout.title,
                sessionText: "\(session.activityType) \(session.title)"
            )
            if sameDiscipline {
                // Chiusura corretta: le manca solo il nome dell'attività, che
                // la vecchia versione non salvava.
                if session.actualActivityTitle == nil {
                    updated.updateSession(id: session.id) { $0.actualActivityTitle = workout.title }
                }
            } else {
                updated.updateSession(id: session.id) { target in
                    target.status = .planned
                    target.completedAt = nil
                    target.completionSource = nil
                    target.matchedWorkoutId = nil
                    target.actualActivityTitle = nil
                    target.actualMinutes = nil
                    target.actualKcal = nil
                }
                repaired += 1
            }
        }

        // Residui di abbinamenti su sedute non chiuse: campi rimasti da versioni
        // che riaprivano la seduta senza azzerarli. Non fanno danni visibili, ma
        // falsano i minuti del consuntivo e impediscono di riusare quell'attività.
        for session in updated.allSessions where session.status != .done {
            guard session.matchedWorkoutId != nil || session.actualMinutes != nil
                || session.actualKcal != nil || session.actualActivityTitle != nil
            else { continue }
            updated.updateSession(id: session.id) { target in
                target.matchedWorkoutId = nil
                target.actualMinutes = nil
                target.actualKcal = nil
                target.actualHeartRateBpm = nil
                target.actualActivityTitle = nil
                target.completedAt = nil
                target.completionSource = nil
            }
        }

        // Le sedute da valutare si leggono dal piano già riparato: una riaperta
        // qui sopra può essere richiusa subito dall'allenamento giusto.
        let pending = updated.allSessions.filter {
            !$0.isRest && $0.status == .planned && $0.date <= today
        }

        // Un allenamento chiude al massimo una seduta: senza questo insieme una
        // corsa lunga chiuderebbe tutte le sedute arretrate dello stesso giorno.
        var usedWorkoutIds = Set(updated.allSessions.compactMap(\.matchedWorkoutId))

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
                target.actualActivityTitle = workout.title
                target.actualMinutes = workout.durationMinutes
                target.actualKcal = workout.activeEnergyKcal.map { Int($0.rounded()) }
                target.actualHeartRateBpm = workout.averageHeartRateBpm.map { Int($0.rounded()) }
            }
            if let closed = updated.session(id: session.id) {
                matched.append(closed)
            }
        }

        // Quello che resta è attività svolta che il programma non prevedeva:
        // va mostrata per quella che è, non spacciata per una seduta pianificata.
        let alreadyLogged = Set(updated.logged.map(\.id))
        let newlyLogged = workouts
            .filter { !usedWorkoutIds.contains($0.id) && !alreadyLogged.contains($0.id) }
            .map { workout in
                FitnessLoggedWorkout(
                    id: workout.id,
                    date: workout.startedAt,
                    title: workout.title,
                    durationMinutes: workout.durationMinutes,
                    kcal: workout.activeEnergyKcal.map { Int($0.rounded()) },
                    heartRateBpm: workout.averageHeartRateBpm.map { Int($0.rounded()) }
                )
            }
        if !newlyLogged.isEmpty {
            updated.loggedWorkouts = updated.logged + newlyLogged
        }

        KBLog.sync.kbInfo(
            "FitnessHealthSync: pending=\(pending.count) workouts=\(workouts.count) matched=\(matched.count) logged=\(newlyLogged.count) repaired=\(repaired)"
        )
        return Result(
            plan: updated,
            matchedSessions: matched,
            loggedWorkouts: newlyLogged,
            repairedSessions: repaired
        )
    }

    /// Chiude la seduta solo un allenamento abbastanza lungo **e della stessa
    /// disciplina**.
    ///
    /// Prima, senza corrispondenza, si ripiegava sull'allenamento più lungo
    /// della giornata: una corsa chiudeva così sia la seduta di bici sia quella
    /// di corpo libero previste quel giorno, dichiarando svolto un allenamento
    /// mai fatto. Meglio lasciare la seduta aperta e mostrare a parte ciò che è
    /// stato fatto: a decidere se una cosa sostituisce l'altra è la persona,
    /// non un'euristica sulla durata.
    private static func bestMatch(
        for session: FitnessSession,
        among workouts: [KBHealthWorkoutEntry]
    ) -> KBHealthWorkoutEntry? {
        let required = max(
            minimumMinutes,
            Int(Double(session.durationMinutes) * minimumDurationRatio)
        )
        return workouts
            .filter { ($0.durationMinutes ?? 0) >= required }
            .first { workout in
                FitnessDisciplineMatcher.matches(
                    activityTitle: workout.title,
                    sessionText: "\(session.activityType) \(session.title)"
                )
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
