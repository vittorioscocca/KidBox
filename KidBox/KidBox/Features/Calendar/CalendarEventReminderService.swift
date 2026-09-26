//
//  CalendarEventReminderService.swift
//  KidBox
//
//  Il promemoria di un evento del calendario.
//

import Foundation
import UserNotifications
import SwiftData

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
///
/// **Eventi ricorrenti.** Una notifica locale non sa ripetersi «ogni mese dal
/// 31» o «ogni settimana, un giorno prima»: i trigger ripetuti di sistema
/// seguono il calendario, non la serie, e resterebbero in coda per sempre.
/// Per questo una serie arma le **prossime `notificationHorizon` ripetizioni**
/// come notifiche singole (la sveglia urgente solo la prossima: AlarmKit ne
/// tiene una per elemento) e si iscrive a `KBDeviceReminderLedger`; al rientro
/// in app `rescheduleArmed` riempie di nuovo la finestra. Chi non apre
/// l'app per tre ripetizioni di fila smette di ricevere l'avviso: è il prezzo
/// di non usare trigger ripetuti, lo stesso di veicoli e pagamenti.
/// Il riarmo legge l'evento locale, quindi per una serie le modifiche fatte
/// da un altro telefono (orario, avviso tolto, evento cancellato) arrivano
/// anche qui al rientro successivo; per un evento singolo resta la regola
/// sopra.
enum CalendarEventReminderService {

    /// Quante ripetizioni future si armano in anticipo per una serie.
    static let notificationHorizon = 3

    private static func identifier(eventId: String, slot: Int = 0) -> String {
        slot == 0 ? "calendar.reminder.\(eventId)" : "calendar.reminder.\(eventId).\(slot)"
    }

    private static let identifierPrefix = "calendar.reminder."

    static func ledgerKey(_ eventId: String) -> String { "calendarEvent:\(eventId)" }

    /// Gli istanti a cui avvisare: la prossima ripetizione, o le prossime
    /// `notificationHorizon` per una serie, sempre `minutes` prima dell'inizio.
    static func fireDates(for event: KBCalendarEvent, now: Date = Date()) -> [Date] {
        guard let minutes = event.reminderMinutes else { return [] }
        let lead = Double(minutes) * 60
        let earliestStart = now.addingTimeInterval(lead)
        guard event.recurrence != .none else {
            return event.startDate > earliestStart ? [event.startDate.addingTimeInterval(-lead)] : []
        }
        let window = DateInterval(start: earliestStart, duration: 86_400 * 800)
        return event.occurrences(in: window)
            .filter { $0.startDate > earliestStart }
            .prefix(notificationHorizon)
            .map { $0.startDate.addingTimeInterval(-lead) }
    }

    /// Allinea il promemoria allo stato dell'evento: lo arma, lo sposta o lo
    /// toglie. Si chiama a ogni salvataggio, così non serve sapere cosa è
    /// cambiato.
    static func sync(event: KBCalendarEvent) async {
        await sync(
            eventId: event.id,
            familyId: event.familyId,
            title: event.title,
            fireDates: event.isDeleted ? [] : fireDates(for: event),
            isUrgent: event.isUrgent
        )
    }

    static func sync(
        eventId: String,
        familyId: String,
        title: String,
        fireDates: [Date],
        isUrgent: Bool
    ) async {
        cancel(eventId: eventId)

        // Niente promemoria, o solo avvisi già scaduti: non resta nulla da fare.
        let upcoming = fireDates.filter { $0 > Date() }.sorted()
        guard let first = upcoming.first else { return }
        KBDeviceReminderLedger.record(ledgerKey(eventId))

        var notificationDates = upcoming
        if isUrgent {
            let armed = await KBUrgentAlarmService.schedule(
                entityId: eventId,
                kind: .calendarEvent,
                title: title,
                fireAt: first,
                familyId: familyId
            )
            // La prossima suona come sveglia; le successive restano notifiche
            // finché il rientro in app non le promuove a loro volta.
            if armed { notificationDates.removeFirst() }
            // Sveglie negate o non disponibili: si ripiega sulla notifica.
        }
        guard !notificationDates.isEmpty else { return }

        guard await KBReminderPermission.requestIfNeeded() else {
            KBLog.app.kbInfo("[CalendarReminder] notifiche negate eventId=\(eventId)")
            return
        }

        let slotOffset = upcoming.count - notificationDates.count
        for (i, fireAt) in notificationDates.enumerated() {
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
                identifier: identifier(eventId: eventId, slot: slotOffset + i),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            )
            await KBLocalNotificationBudget.shared.add(request, priority: .deadline)
        }
        KBLog.app.kbInfo("[CalendarReminder] armato eventId=\(eventId) prossimi=\(upcoming.count) urgent=\(isUrgent)")
    }

    /// Toglie notifiche **e** sveglia: un evento cancellato non deve suonare
    /// per la strada che nessuno ha ripulito.
    static func cancel(eventId: String) {
        let ids = (0...notificationHorizon).map { identifier(eventId: eventId, slot: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        KBUrgentAlarmService.cancel(entityId: eventId, kind: .calendarEvent)
    }

    /// Da chiamare quando l'evento sparisce per davvero: oltre all'avviso
    /// toglie l'iscrizione al riarmo.
    static func forget(eventId: String) {
        cancel(eventId: eventId)
        KBDeviceReminderLedger.forget(ledgerKey(eventId))
    }

    /// Riempie di nuovo la finestra degli eventi armati **su questo
    /// dispositivo**: il rientro in app è l'unico momento in cui gli avvisi
    /// già scattati di una serie vengono rimpiazzati. Non crea mai un
    /// promemoria per un evento arrivato dal sync; spegne quelli di un evento
    /// cancellato altrove.
    @MainActor
    static func rescheduleArmed(modelContext: ModelContext) async {
        await adoptPendingIfNeeded()
        let descriptor = FetchDescriptor<KBCalendarEvent>()
        guard let rows = try? modelContext.fetch(descriptor) else { return }
        var byId: [String: KBCalendarEvent] = [:]
        for row in rows { byId[row.id] = row }

        var refreshed = 0
        for key in KBDeviceReminderLedger.keys(withPrefix: "calendarEvent:") {
            let eventId = String(key.dropFirst("calendarEvent:".count))
            guard let event = byId[eventId], !event.isDeleted, event.reminderMinutes != nil else {
                forget(eventId: eventId)
                continue
            }
            // Un evento singolo è già armato fino in fondo: si tocca solo per
            // toglierlo dal registro quando è passato.
            if event.recurrence == .none {
                if fireDates(for: event).isEmpty { KBDeviceReminderLedger.forget(key) }
                continue
            }
            await sync(event: event)
            refreshed += 1
        }
        KBLog.app.kbDebug("[CalendarReminder] rescheduleArmed serie=\(refreshed)")
    }

    /// Le notifiche armate prima che esistesse il registro sono comunque di
    /// questo dispositivo: si riconoscono dall'identificativo.
    @MainActor
    private static func adoptPendingIfNeeded() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        for request in pending where request.identifier.hasPrefix(identifierPrefix) {
            let rest = request.identifier.dropFirst(identifierPrefix.count)
            let eventId = rest.split(separator: ".").first.map(String.init) ?? String(rest)
            KBDeviceReminderLedger.record(ledgerKey(eventId))
        }
    }
}
