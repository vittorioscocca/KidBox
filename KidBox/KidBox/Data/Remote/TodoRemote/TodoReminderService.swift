//
//  TodoReminderService.swift
//  KidBox
//
//  Created by vscocca on 26/02/26.
//

import Foundation
import UserNotifications
import OSLog

enum TodoReminderService {
    
    static func ensurePermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                KBLog.app.kbError("[Reminder] requestAuthorization FAIL err=\(error.localizedDescription)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
    
    /// Pianifica il promemoria di un to-do.
    ///
    /// Due strade, scelte da `isUrgent`:
    /// - **urgente** → sveglia AlarmKit: suona anche in silenzioso e in full
    ///   immersion, come la sveglia dell'Orologio;
    /// - **normale** → notifica locale.
    ///
    /// Se la sveglia non si può armare (permesso negato, Mac Catalyst) si
    /// ripiega sulla notifica, marcata però `.timeSensitive`: non è una
    /// sveglia, ma è il massimo che passa attraverso una full immersion.
    static func schedule(
        todoId:   String,
        listId:   String,
        familyId: String,
        childId:  String,
        title:    String,
        dueAt:    Date,
        isUrgent: Bool = false
    ) async throws -> String {
        let id = "todo.reminder.\(todoId)"   // stabile: 1 notifica per todo

        if isUrgent {
            let armed = await KBUrgentAlarmService.schedule(
                entityId: todoId,
                kind: .todo,
                title: title,
                fireAt: dueAt,
                familyId: familyId,
                childId: childId,
                listId: listId
            )
            if armed {
                // Sveglia e notifica sullo stesso istante avviserebbero due
                // volte: chi vince è la sveglia, l'altra si toglie.
                UNUserNotificationCenter.current()
                    .removePendingNotificationRequests(withIdentifiers: [id])
                return id
            }
        } else {
            // Non più urgente: la sveglia di prima non deve sopravvivere.
            KBUrgentAlarmService.cancel(entityId: todoId, kind: .todo)
        }

        let allowed = await ensurePermission()
        guard allowed else {
            throw NSError(domain: "KidBox", code: 401, userInfo: [NSLocalizedDescriptionKey: "Notifiche non autorizzate"])
        }
        
        let content = UNMutableNotificationContent()
        content.body  = title
        content.sound = UNNotificationSound.default
        // Urgente senza sveglia: resta l'unica leva che attraversa una full
        // immersion, se l'utente consente le notifiche critiche per tempo.
        content.interruptionLevel = isUrgent ? .timeSensitive : .active
        // ── Payload completo per il deep link ──────────────────────────────
        // NotificationManager.handleNotificationUserInfo() usa questi campi
        // per costruire il DeepLink.todo e navigare direttamente al todo.
        content.userInfo = [
            "type":     "todo_reminder",
            "todoId":   todoId,
            "listId":   listId,
            "familyId": familyId,
            "childId":  childId
        ]
        KBNotificationLocalization.setText(on: content, titleKey: "⏰ Promemoria")
        // ──────────────────────────────────────────────────────────────────
        
        let comps   = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req     = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        await KBLocalNotificationBudget.shared.add(req, priority: .deadline)
        
        KBLog.todo.kbInfo("[Reminder] scheduled id=\(id) dueAt=\(dueAt) urgent=\(isUrgent)")
        return id
    }
    
    /// Toglie promemoria **e** sveglia: un to-do che perde la scadenza non
    /// deve continuare a suonare per la strada che non è stata cancellata.
    static func cancel(reminderId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderId])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [reminderId])
        if reminderId.hasPrefix("todo.reminder.") {
            let todoId = String(reminderId.dropFirst("todo.reminder.".count))
            KBUrgentAlarmService.cancel(entityId: todoId, kind: .todo)
        }
        KBLog.todo.kbInfo("[Reminder] cancelled id=\(reminderId)")
    }

    /// Variante quando si ha in mano il to-do e non il suo `reminderId`:
    /// i to-do più vecchi lo hanno `nil` anche con il promemoria acceso.
    static func cancel(todoId: String) {
        cancel(reminderId: "todo.reminder.\(todoId)")
    }
}
