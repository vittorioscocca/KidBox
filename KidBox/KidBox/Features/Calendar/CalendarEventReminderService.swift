//
//  CalendarEventReminderService.swift
//  KidBox
//
//  Il promemoria di un evento del calendario.
//

import Foundation
import UserNotifications

/// Fino al 22/09/2026 l'interruttore «Promemoria» nella scheda evento
/// **scriveva `reminderMinutes` e non armava niente**: né su iOS né su
/// Android esisteva un servizio che lo leggesse, e nessuna Cloud Function lo
/// guarda. L'utente accendeva l'avviso e non arrivava mai. Questo servizio
/// chiude quel buco.
///
/// Come tutti i promemoria KidBox è **del dispositivo che salva l'evento**:
/// un evento che arriva dalla sincronizzazione non arma nulla qui. Vale la
/// nota "Promemoria locali = del device" — e la conseguenza voluta è che
/// spostare un evento da un altro telefono non sposta l'avviso su questo.
enum CalendarEventReminderService {

    private static func identifier(eventId: String) -> String {
        "calendar.reminder.\(eventId)"
    }

    /// Allinea il promemoria allo stato dell'evento: lo arma, lo sposta o lo
    /// toglie. Si chiama a ogni salvataggio, così non serve sapere cosa è
    /// cambiato.
    static func sync(
        eventId: String,
        familyId: String,
        title: String,
        fireAt: Date?,
        isUrgent: Bool
    ) async {
        cancel(eventId: eventId)

        // Niente promemoria, o un avviso già scaduto: non resta nulla da fare.
        guard let fireAt, fireAt > Date() else { return }

        if isUrgent {
            let armed = await KBUrgentAlarmService.schedule(
                entityId: eventId,
                kind: .calendarEvent,
                title: title,
                fireAt: fireAt,
                familyId: familyId
            )
            if armed { return }
            // Sveglie negate o non disponibili: sotto si ripiega sulla notifica.
        }

        guard await KBReminderPermission.requestIfNeeded() else {
            KBLog.app.kbInfo("[CalendarReminder] notifiche negate eventId=\(eventId)")
            return
        }

        let content = UNMutableNotificationContent()
        content.body = title
        content.sound = .default
        content.interruptionLevel = isUrgent ? .timeSensitive : .active
        content.userInfo = [
            "type":     "calendar_event_reminder",
            "eventId":  eventId,
            "familyId": familyId
        ]
        KBNotificationLocalization.setText(on: content, titleKey: "📅 Promemoria evento")

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireAt)
        let request = UNNotificationRequest(
            identifier: identifier(eventId: eventId),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
        await KBLocalNotificationBudget.shared.add(request, priority: .deadline)
        KBLog.app.kbInfo("[CalendarReminder] armato eventId=\(eventId) fireAt=\(fireAt) urgent=\(isUrgent)")
    }

    /// Toglie notifica **e** sveglia: un evento cancellato non deve suonare
    /// per la strada che nessuno ha ripulito.
    static func cancel(eventId: String) {
        let id = identifier(eventId: eventId)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        KBUrgentAlarmService.cancel(entityId: eventId, kind: .calendarEvent)
    }
}
