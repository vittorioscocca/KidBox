//
//  KBInsightNotificationActions.swift
//  KidBox
//
//  Azioni rapide sulle notifiche degli insight, senza aprire l'app:
//  - to-do senza nessuno: «Ci penso io» lo assegna a chi tocca; «Chiedi agli
//    altri» manda una richiesta di famiglia per quel to-do a chi lo vede, e il
//    primo che risponde sì se lo prende (solo se in famiglia c'è qualcun altro);
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
    /// Come `todo`, con «Chiedi agli altri»: c'è qualcun altro a cui chiedere.
    static let todoAsk = "KB_INSIGHT_TODO_ASK"
    static let dose = "KB_INSIGHT_DOSE"

    static let actionTake    = "KB_INSIGHT_TAKE"
    static let actionAsk     = "KB_INSIGHT_ASK"
    static let actionDoseOk  = "KB_INSIGHT_DOSE_TAKEN"
    static let actionSnooze  = "KB_INSIGHT_SNOOZE"
    static let actionDismiss = "KB_INSIGHT_DISMISS"

    static let snoozeInterval: TimeInterval = 3600

    static func identifier(for type: KBInsightType) -> String? {
        switch type {
        case .todoUnassignedDueSoon: return todo
        case .treatmentDoseMissing:  return dose
        // Stesse azioni del to-do: «chi paga» è il to-do «Pagare: …».
        case .housePaymentDue:       return todo
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
        let ask = UNNotificationAction(
            identifier: actionAsk,
            title: KBNotificationLocalization.text("Chiedi agli altri"),
            options: []
        )
        let doseOk = UNNotificationAction(
            identifier: actionDoseOk,
            title: KBNotificationLocalization.text("Presa"),
            options: []
        )
        return [
            UNNotificationCategory(identifier: todo, actions: [take, snooze, dismiss], intentIdentifiers: []),
            UNNotificationCategory(identifier: todoAsk, actions: [take, ask, snooze, dismiss], intentIdentifiers: []),
            UNNotificationCategory(identifier: dose, actions: [doseOk, snooze, dismiss], intentIdentifiers: []),
        ]
    }
}

@MainActor
enum KBInsightActionHandler {

    /// - Returns: `true` se era un'azione rapida di un insight (niente deep link).
    @discardableResult
    static func handle(response: UNNotificationResponse, modelContext: ModelContext) async -> Bool {
        let action = response.actionIdentifier
        guard [KBInsightNotificationCategory.actionTake,
               KBInsightNotificationCategory.actionAsk,
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
        // Pagamento di casa: «Ci penso io» e «Chiedi agli altri» lavorano sul
        // to-do «Pagare: …» di quella scadenza, che nasce qui se non c'è ancora.
        var targetTodoId = info["todoId"] as? String
        if row.type == .housePaymentDue,
           action == KBInsightNotificationCategory.actionTake || action == KBInsightNotificationCategory.actionAsk {
            targetTodoId = ensurePaymentTodo(for: row, now: now, modelContext: modelContext)
        }

        switch action {
        case KBInsightNotificationCategory.actionTake:
            if let todoId = targetTodoId {
                takeTodo(todoId: todoId, familyId: row.familyId, now: now, modelContext: modelContext)
            }
            row.mark(.done, now: now)
            reportActed(row, typeRaw: typeRaw, via: "action", now: now)

        case KBInsightNotificationCategory.actionAsk:
            // L'avviso resta aperto: si chiude da solo quando qualcuno prende
            // il to-do (dalla richiesta o dall'app).
            if let todoId = targetTodoId,
               await askOthers(todoId: todoId, familyId: row.familyId, modelContext: modelContext) {
                reportActed(row, typeRaw: typeRaw, via: "ask", now: now)
            }

        case KBInsightNotificationCategory.actionDoseOk:
            if let treatmentId = info["treatmentId"] as? String {
                recordFirstMissingDose(treatmentId: treatmentId, familyId: row.familyId, now: now, modelContext: modelContext)
            }
            row.mark(.done, now: now)
            reportActed(row, typeRaw: typeRaw, via: "action", now: now)

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

    private static func reportActed(_ row: KBInsight, typeRaw: String, via: String, now: Date) {
        guard row.actedReportedAt == nil else { return }
        AppAnalytics.insightActed(type: typeRaw, via: via, minutes: minutesSinceShown(row, now: now))
        row.actedReportedAt = now
    }

    static func minutesSinceShown(_ row: KBInsight, now: Date) -> Int {
        guard let shown = row.shownReportedAt else { return 0 }
        return max(0, Int(now.timeIntervalSince(shown) / 60))
    }

    // MARK: - Pagamento di casa → to-do «Pagare: …»

    /// Il to-do della scadenza indicata dall'insight (`<pagamento>@<giorno>`),
    /// creato senza nessuno se non esiste. L'id è prevedibile
    /// (`KBInsightEngine.paymentTodoId`): due genitori che toccano insieme
    /// scrivono lo stesso to-do, e il motore smette di chiedere chi paga.
    /// Va nella lista modificata più di recente; senza liste non si crea niente.
    static func ensurePaymentTodo(for row: KBInsight, now: Date, modelContext: ModelContext) -> String? {
        let parts = row.entityId.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let uid = Auth.auth().currentUser?.uid else { return nil }
        let paymentId = parts[0]
        let fmt = DateFormatter()
        fmt.calendar = Calendar.current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        guard let day = fmt.date(from: parts[1]),
              let payment = try? modelContext.fetch(FetchDescriptor<KBHousePayment>(
                  predicate: #Predicate { $0.id == paymentId }
              )).first
        else { return nil }

        let todoId = KBInsightEngine.paymentTodoId(paymentId: paymentId, due: day)
        if (try? modelContext.fetch(FetchDescriptor<KBTodoItem>(predicate: #Predicate { $0.id == todoId })).first) != nil {
            return todoId
        }
        let fid = row.familyId
        var listDescriptor = FetchDescriptor<KBTodoList>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        listDescriptor.fetchLimit = 1
        guard let list = try? modelContext.fetch(listDescriptor).first else {
            KBLog.ai.kbInfo("InsightAction: nessuna lista per il to-do del pagamento")
            return nil
        }

        // Senza orario: come i to-do «tutto il giorno», `dueAt` alle 9.
        let dueAt = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let todo = KBTodoItem(
            id: todoId,
            familyId: fid,
            childId: list.childId,
            title: String(format: NSLocalizedString("Pagare: %@", comment: "To-do nato da un pagamento di casa"), payment.name),
            listId: list.id,
            dueAt: dueAt,
            dueHasTime: false,
            updatedBy: uid,
            createdAt: now,
            updatedAt: now
        )
        todo.createdBy = uid
        todo.priorityRaw = 0
        todo.syncState = .pendingUpsert
        modelContext.insert(todo)
        do {
            try modelContext.save()
            SyncCenter.shared.enqueueTodoUpsert(todoId: todoId, familyId: fid, modelContext: modelContext)
            return todoId
        } catch {
            KBLog.ai.kbError("InsightAction: to-do del pagamento non salvato \(error.localizedDescription)")
            return nil
        }
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

    // MARK: - Chiedi agli altri

    /// Chi riceve la richiesta: i membri che vedono il to-do, tranne chi chiede.
    static func askRecipients(for todo: KBTodoItem, uid: String, modelContext: ModelContext) -> [String] {
        let fid = todo.familyId
        let members = ((try? modelContext.fetch(FetchDescriptor<KBFamilyMember>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        ))) ?? []).map(\.userId)
        let visible: [String]
        switch KBVisibilityScope.normalized(todo.visibilityScope) {
        case KBVisibilityScope.members:
            let allowed = Set(todo.visibilityMemberIds ?? [])
            visible = members.filter { allowed.contains($0) }
        case KBVisibilityScope.onlyCreator:
            visible = []
        default:
            visible = members
        }
        return Array(Set(visible.filter { !$0.isEmpty && $0 != uid })).sorted()
    }

    /// - Returns: `true` se la richiesta è partita.
    private static func askOthers(todoId: String, familyId: String, modelContext: ModelContext) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid,
              let todo = try? modelContext.fetch(FetchDescriptor<KBTodoItem>(
                  predicate: #Predicate { $0.id == todoId }
              )).first,
              (todo.assignedTo ?? "").isEmpty, (todo.assignedExternalName ?? "").isEmpty,
              let listId = todo.listId, !listId.isEmpty
        else { return false }
        let recipients = askRecipients(for: todo, uid: uid, modelContext: modelContext)
        guard !recipients.isEmpty else { return false }
        do {
            _ = try await FamilyRequestService.create(
                familyId: familyId,
                childId: todo.childId,
                listId: listId,
                title: todo.title,
                notes: todo.notes,
                isUrgent: todo.isUrgent,
                dueAt: todo.dueAt,
                dueHasTime: todo.hasDueTime,
                draft: FamilyRequestService.Draft(recipients: recipients),
                familyName: "",
                inviterName: "",
                sourceTodoId: todo.id
            )
            return true
        } catch {
            KBLog.ai.kbError("InsightAction: ask others failed \(error.localizedDescription)")
            return false
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
