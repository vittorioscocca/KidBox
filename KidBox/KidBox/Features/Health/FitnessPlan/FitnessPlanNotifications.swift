//
//  FitnessPlanNotifications.swift
//  KidBox
//
//  Promemoria locali delle sedute, con le due azioni rapide previste dalle
//  specifiche: [Fatto] e [Sposta].
//
//  Vincoli KidBox rispettati qui:
//  - ogni notifica passa da `KBLocalNotificationBudget` (tetto iOS di 64
//    pendenti per app), mai da `center.add` diretto;
//  - il promemoria è **del device** che ha creato il piano: la registrazione in
//    `KBDeviceReminderLedger` serve a non far riarmare nulla al sync;
//  - il testo si congela al momento della schedulazione (su iOS non esiste un
//    hook prima della consegna), quindi si usa `localizedUserNotificationString`.
//

import Foundation
import UserNotifications

// MARK: - Notification.Name

extension Notification.Name {
    /// Postata quando il piano cambia fuori dalla view (quick action, sync Salute).
    static let fitnessPlanDidChange = Notification.Name("kb.fitnessPlanDidChange")
}

// MARK: - Categoria e azioni

enum FitnessPlanNotificationCategory {
    static let identifier = "FITNESS_SESSION_REMINDER"
    static let actionDone = "FITNESS_SESSION_DONE"
    static let actionMove = "FITNESS_SESSION_MOVE"

    /// Payload della notifica: il tipo entra anche nella classificazione del budget.
    static let notificationType = "fitness_session_reminder"

    static var category: UNNotificationCategory {
        let done = UNNotificationAction(
            identifier: actionDone,
            title: NSLocalizedString("✅ Fatto", comment: "Fitness notification action done"),
            options: []
        )
        let move = UNNotificationAction(
            identifier: actionMove,
            title: NSLocalizedString("📅 Sposta", comment: "Fitness notification action move"),
            options: []
        )
        return UNNotificationCategory(
            identifier: identifier,
            actions: [done, move],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
    }
}

// MARK: - Schedulazione

enum FitnessPlanNotificationManager {

    /// Quanti promemoria futuri tenere in coda: il budget locale è stretto e le
    /// sedute oltre le due settimane cambiano quasi sempre prima di scattare.
    private static let maxScheduled = 10

    private static func identifier(childId: String, sessionId: String) -> String {
        "fitness-\(childId)-\(sessionId)"
    }

    static func ledgerKey(childId: String) -> String { "fitnessPlan:\(childId)" }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return settings.authorizationStatus == .authorized
        }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Ripianifica da zero i promemoria del piano: è l'unico punto di ingresso,
    /// chiamato dopo generazione, spostamento, completamento e ricalcolo.
    static func reschedule(plan: FitnessPlanDocument, childId: String, familyId: String? = nil) async {
        await cancelAll(childId: childId)

        guard plan.input.reminderEnabled else {
            KBLog.auth.kbInfo("FitnessPlanNotifications: promemoria disattivati childId=\(childId)")
            return
        }
        guard await requestAuthorization() else {
            KBLog.auth.kbInfo("FitnessPlanNotifications: autorizzazione negata")
            return
        }

        let now = Date()
        let cal = Calendar.current
        let upcoming = plan.allSessions
            .filter { $0.status == .planned && !$0.isRest }
            .compactMap { session -> (FitnessSession, Date)? in
                guard let fireDate = cal.date(
                    bySettingHour: plan.input.reminderHour,
                    minute: plan.input.reminderMinute,
                    second: 0,
                    of: session.date
                ), fireDate > now else { return nil }
                return (session, fireDate)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(maxScheduled)

        guard !upcoming.isEmpty else { return }

        let requests = upcoming.map { session, fireDate in
            request(
                session: session,
                fireDate: fireDate,
                childId: childId,
                familyId: familyId,
                subjectName: plan.subjectName
            )
        }
        let accepted = await KBLocalNotificationBudget.shared.add(requests, priority: .deadline)
        if accepted > 0 {
            KBDeviceReminderLedger.record(ledgerKey(childId: childId))
        }
        KBLog.auth.kbInfo(
            "FitnessPlanNotifications: schedulate \(accepted)/\(requests.count) childId=\(childId)"
        )
    }

    static func cancelAll(childId: String) async {
        let center = UNUserNotificationCenter.current()
        let prefix = "fitness-\(childId)-"
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Rimuove i promemoria e la traccia nel registro: usato all'eliminazione del piano.
    static func removePlan(childId: String) async {
        await cancelAll(childId: childId)
        KBDeviceReminderLedger.forget(ledgerKey(childId: childId))
    }

    private static func request(
        session: FitnessSession,
        fireDate: Date,
        childId: String,
        familyId: String?,
        subjectName: String
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = NSString.localizedUserNotificationString(
            forKey: "Allenamento di oggi",
            arguments: nil
        )
        var body = session.title
        if session.durationMinutes > 0 {
            body += " · \(session.durationMinutes) min"
        }
        if let first = session.targets.first {
            body += "\n\(first)"
        }
        content.body = body
        content.sound = .default
        content.categoryIdentifier = FitnessPlanNotificationCategory.identifier
        var userInfo: [String: Any] = [
            "type": FitnessPlanNotificationCategory.notificationType,
            "childId": childId,
            "sessionId": session.id,
        ]
        if let familyId { userInfo["familyId"] = familyId }
        content.userInfo = userInfo

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        return UNNotificationRequest(
            identifier: identifier(childId: childId, sessionId: session.id),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }
}

// MARK: - Quick action

@MainActor
enum FitnessSessionActionHandler {

    /// Gestisce [Fatto] e [Sposta] dalla notifica.
    /// - Returns: `true` se era una quick action (non un tap normale).
    @discardableResult
    static func handle(response: UNNotificationResponse) async -> Bool {
        let actionId = response.actionIdentifier
        guard
            actionId == FitnessPlanNotificationCategory.actionDone
                || actionId == FitnessPlanNotificationCategory.actionMove
        else { return false }

        let userInfo = response.notification.request.content.userInfo
        guard
            let childId = userInfo["childId"] as? String,
            let sessionId = userInfo["sessionId"] as? String,
            var plan = FitnessPlanStore.load(childId: childId),
            plan.session(id: sessionId) != nil
        else {
            KBLog.auth.kbError("FitnessSessionActionHandler: piano o seduta non trovati")
            return true
        }

        let familyId = userInfo["familyId"] as? String

        if actionId == FitnessPlanNotificationCategory.actionDone {
            plan.updateSession(id: sessionId) { session in
                session.status = .done
                session.completedAt = Date()
                session.completionSource = .notification
            }
        } else {
            // Lo spostamento vero e proprio è deterministico e avviene subito,
            // così il calendario resta coerente anche con l'app chiusa. La
            // riorganizzazione AI del resto della settimana costa un messaggio
            // e va chiesta con la rete disponibile: la esegue la dashboard alla
            // prima apertura, leggendo questo flag.
            guard let newDate = nextAvailableDate(for: sessionId, in: plan) else {
                KBLog.auth.kbInfo("FitnessSessionActionHandler: nessuna data libera per lo spostamento")
                return true
            }
            plan.updateSession(id: sessionId) { session in
                session.originalDate = session.originalDate ?? session.date
                session.date = newDate
                session.status = .planned
            }
            FitnessPlanPendingReschedule.set(sessionId: sessionId, childId: childId)
        }

        FitnessPlanStore.save(plan, childId: childId)
        let saved = plan
        Task {
            await FitnessPlanRemoteStore.upsert(saved, childId: childId)
            await FitnessPlanNotificationManager.reschedule(
                plan: saved,
                childId: childId,
                familyId: familyId
            )
        }
        NotificationCenter.default.post(name: .fitnessPlanDidChange, object: nil)
        return true
    }

    /// Prima giornata utile fra i giorni di allenamento scelti, saltando quelle
    /// che hanno già una seduta.
    private static func nextAvailableDate(for sessionId: String, in plan: FitnessPlanDocument) -> Date? {
        guard let session = plan.session(id: sessionId) else { return nil }
        let cal = Calendar.current
        let occupied = Set(
            plan.allSessions
                .filter { $0.id != sessionId }
                .map { cal.startOfDay(for: $0.date) }
        )
        for offset in 1...14 {
            guard let candidate = cal.date(byAdding: .day, value: offset, to: session.date) else { continue }
            let day = cal.startOfDay(for: candidate)
            guard plan.input.trainingWeekdays.contains(cal.component(.weekday, from: day)) else { continue }
            guard !occupied.contains(day) else { continue }
            return day
        }
        // Nessun giorno libero fra quelli scelti: il giorno dopo va comunque bene.
        return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: session.date))
    }
}

// MARK: - Riorganizzazione AI in sospeso

/// Traccia la seduta spostata da una notifica, per la quale la dashboard deve
/// ancora chiedere all'AI di riorganizzare il resto della settimana.
enum FitnessPlanPendingReschedule {

    private static let prefix = "kidbox.fitnessplan.pendingReschedule."

    static func set(sessionId: String, childId: String) {
        UserDefaults.standard.set(sessionId, forKey: prefix + childId)
    }

    static func pending(childId: String) -> String? {
        UserDefaults.standard.string(forKey: prefix + childId)
    }

    static func clear(childId: String) {
        UserDefaults.standard.removeObject(forKey: prefix + childId)
    }
}
