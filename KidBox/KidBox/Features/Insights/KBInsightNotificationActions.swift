//
//  KBInsightNotificationActions.swift
//  KidBox
//
//  Azioni rapide sulle notifiche degli insight, senza aprire l'app:
//  - to-do senza nessuno: «Ci penso io» lo assegna a chi tocca;
//  - dose mancante: «Presa» registra la prima dose di oggi ancora scoperta;
//  - «Rimanda di un'ora» e «Non mi interessa» su entrambi.
//
//  «Non mi interessa» chiude quell'insight e basta: spegnere un tipo intero
//  sta nelle preferenze, dove si può anche riaccendere.
//
//  Dopo ogni azione il motore rifà il giro subito: l'insight risolto sparisce
//  anche dal Centro notifiche.
//

import FirebaseAuth
import Foundation
import SwiftData
import UserNotifications

enum KBInsightNotificationCategory {
    static let todo = "KB_INSIGHT_TODO"
    static let dose = "KB_INSIGHT_DOSE"

    static let actionTake    = "KB_INSIGHT_TAKE"
    static let actionDoseOk  = "KB_INSIGHT_DOSE_TAKEN"
    static let actionSnooze  = "KB_INSIGHT_SNOOZE"
    static let actionDismiss = "KB_INSIGHT_DISMISS"

    static let snoozeInterval: TimeInterval = 3600

    static func identifier(for type: KBInsightType) -> String? {
        switch type {
        case .todoUnassignedDueSoon: return todo
        case .treatmentDoseMissing:  return dose
        case .eventTomorrowNoReminder, .vaccineDue, .groceryStale: return nil
        }
    }

    /// Registrate da `KBNotificationCategoryRegistry`, di nuovo a ogni cambio
    /// di lingua: il sistema mostra i pulsanti con il testo della registrazione.
    static var categories: [UNNotificationCategory] {
        let snooze = UNNotificationAction(
            identifier: actionSnooze,
            title: KBNotificationLocalization.text("Rimanda di un'ora"),
            options: []
        )
        let dismiss = UNNotificationAction(
            identifier: actionDismiss,
            title: KBNotificationLocalization.text("Non mi interessa"),
            options: []
        )
        let take = UNNotificationAction(
            identifier: actionTake,
            title: KBNotificationLocalization.text("Ci penso io"),
            options: []
        )
        let doseOk = UNNotificationAction(
            identifier: actionDoseOk,
            title: KBNotificationLocalization.text("Presa"),
            options: []
        )
        return [
            UNNotificationCategory(identifier: todo, actions: [take, snooze, dismiss], intentIdentifiers: []),
            UNNotificationCategory(identifier: dose, actions: [doseOk, snooze, dismiss], intentIdentifiers: []),
        ]
    }
}

@MainActor
enum KBInsightActionHandler {

    /// - Returns: `true` se era un'azione rapida di un insight (niente deep link).
    @discardableResult
    static func handle(response: UNNotificationResponse, modelContext: ModelContext) -> Bool {
        let action = response.actionIdentifier
        guard [KBInsightNotificationCategory.actionTake,
               KBInsightNotificationCategory.actionDoseOk,
               KBInsightNotificationCategory.actionSnooze,
               KBInsightNotificationCategory.actionDismiss].contains(action) else { return false }

        let info = response.notification.request.content.userInfo
        guard let insightId = info["insightId"] as? String,
              let row = try? modelContext.fetch(FetchDescriptor<KBInsight>(
                  predicate: #Predicate { $0.id == insightId }
              )).first
        else {
            KBLog.ai.kbError("InsightAction: insight not found action=\(action)")
            return true
        }

        let now = Date()
        let typeRaw = row.type?.rawValue ?? row.typeRaw
        // Toccare il pulsante vuol dire che la notifica è arrivata, anche se il
        // motore non ha ancora fatto il giro che la conta.
        if row.shownReportedAt == nil {
            AppAnalytics.insightShown(type: typeRaw, channel: "notification")
            row.shownReportedAt = row.notifiedAt ?? now
        }
        switch action {
        case KBInsightNotificationCategory.actionTake:
            if let todoId = info["todoId"] as? String {
                takeTodo(todoId: todoId, familyId: row.familyId, now: now, modelContext: modelContext)
            }
            row.mark(.done, now: now)
            AppAnalytics.insightActed(type: typeRaw, via: "action", minutes: minutesSinceShown(row, now: now))

        case KBInsightNotificationCategory.actionDoseOk:
            if let treatmentId = info["treatmentId"] as? String {
                recordFirstMissingDose(treatmentId: treatmentId, familyId: row.familyId, now: now, modelContext: modelContext)
            }
            row.mark(.done, now: now)
            AppAnalytics.insightActed(type: typeRaw, via: "action", minutes: minutesSinceShown(row, now: now))

        case KBInsightNotificationCategory.actionSnooze:
            // Lo scheduler vede una consegna futura non in coda e la riprogramma.
            row.notifiedAt = now.addingTimeInterval(KBInsightNotificationCategory.snoozeInterval)
            AppAnalytics.insightSnoozed(type: typeRaw)

        default:
            row.mark(.dismissed, now: now)
            AppAnalytics.insightDismissed(type: typeRaw)
        }

        try? modelContext.save()
        KBLog.ai.kbInfo("InsightAction: \(action) insight=\(insightId)")
        // Un salvataggio dei soli insight non fa ripartire il motore da sé.
        KBInsightRunner.shared.requestRun(reason: "action", delay: .zero)
        return true
    }

    static func minutesSinceShown(_ row: KBInsight, now: Date) -> Int {
        guard let shown = row.shownReportedAt else { return 0 }
        return max(0, Int(now.timeIntervalSince(shown) / 60))
    }

    // MARK: - Ci penso io

    private static func takeTodo(todoId: String, familyId: String, now: Date, modelContext: ModelContext) {
        guard let uid = Auth.auth().currentUser?.uid,
              let todo = try? modelContext.fetch(FetchDescriptor<KBTodoItem>(
                  predicate: #Predicate { $0.id == todoId }
              )).first
        else { return }
        // Qualcuno l'ha preso nel frattempo: non si toglie a lui.
        guard (todo.assignedTo ?? "").isEmpty, (todo.assignedExternalName ?? "").isEmpty else { return }

        todo.assignedTo = uid
        todo.updatedBy = uid
        todo.updatedAt = now
        todo.syncState = .pendingUpsert
        do {
            try modelContext.save()
            SyncCenter.shared.enqueueTodoUpsert(todoId: todo.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
        } catch {
            KBLog.ai.kbError("InsightAction: take todo failed \(error.localizedDescription)")
        }
    }

    // MARK: - Presa

    /// La prima dose di oggi non segnata come presa, fra quelle già passate
    /// (altrimenti la prima in assoluto): è quella che ha fatto scattare l'avviso.
    private static func recordFirstMissingDose(
        treatmentId: String,
        familyId: String,
        now: Date,
        modelContext: ModelContext
    ) {
        guard let treatment = try? modelContext.fetch(FetchDescriptor<KBTreatment>(
            predicate: #Predicate { $0.id == treatmentId }
        )).first else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let offset = cal.dateComponents([.day], from: cal.startOfDay(for: treatment.startDate), to: today).day,
              offset >= 0 else { return }
        let dayNumber = offset + 1
        let taken = Set(
            ((try? modelContext.fetch(FetchDescriptor<KBDoseLog>(
                predicate: #Predicate { $0.treatmentId == treatmentId && $0.dayNumber == dayNumber }
            ))) ?? [])
            .filter { $0.taken && !$0.isDeleted }
            .map(\.slotIndex)
        )
        let missing = treatment.scheduleTimes.indices.filter { !taken.contains($0) }
        let due = missing.filter { slot in
            let parts = treatment.scheduleTimes[slot].split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2,
                  let at = cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: today)
            else { return false }
            return at <= now
        }
        guard let slot = due.first ?? missing.first else { return }

        TreatmentDoseActionHandler.recordDose(
            treatmentId: treatmentId,
            familyId: familyId,
            dayOffset: offset,
            slotIndex: slot,
            taken: true,
            modelContext: modelContext
        )
    }
}
