//
//  WalletReminderService.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import Foundation
import UserNotifications
import OSLog

/// Scheduling delle notifiche locali (`UNUserNotificationCenter`) per i biglietti Wallet.
///
/// Strategia:
/// - I default per-`KBWalletTicketKind` sono in `KBWalletTicketKind.defaultReminderOffsets`
///   (es. volo: T-24h + T-3h, treno: T-12h + T-1h).
/// - Per ogni biglietto schedula N richieste con identifier deterministici
///   `wallet.<ticketId>.<offsetSec>`, così cancellare/aggiornare = idempotente.
/// - Usa `UNCalendarNotificationTrigger` (più accurato di `UNTimeIntervalNotificationTrigger`
///   per offset di ore/giorni e robusto a sleep/awake del device).
/// - Salta gli offset che cadrebbero nel passato.
/// - Pulisce sempre le richieste vecchie del ticket prima di rischedulare,
///   così cambi di `eventDate` non lasciano notifiche stale.
///
/// Funziona offline: nessuna dipendenza da push/CF. Le push (CF schedulata)
/// sono ridondanti e gestiscono il caso "app non installata sul device che
/// ha creato il ticket" (es. l'utente l'ha aggiunto da un altro device).
@MainActor
final class WalletReminderService {

    static let shared = WalletReminderService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    // MARK: - Schedule

    /// (Ri)schedula tutti i promemoria per un biglietto.
    /// Idempotente: rimuove sempre prima le notifiche esistenti del ticket.
    ///
    /// Rispetta la preferenza utente `kb_notifyOnWalletReminder` (default ON).
    /// Se l'utente ha disattivato i promemoria Wallet in Settings, nessuna
    /// richiesta viene aggiunta — ma la cancellazione preventiva resta, così
    /// togliamo eventuali richieste pendenti rimaste prima del toggle off.
    func scheduleReminders(for ticket: KBWalletTicket) async {
        let ticketId = ticket.id
        await cancelReminders(ticketId: ticketId)

        let prefEnabled = (UserDefaults.standard.object(forKey: "kb_notifyOnWalletReminder") as? Bool) ?? true
        guard prefEnabled else {
            KBLog.sync.kbDebug("[WalletReminder] skip: user disabled wallet reminders ticketId=\(ticketId)")
            return
        }

        guard !ticket.isDeleted, let eventDate = ticket.eventDate else {
            KBLog.sync.kbDebug("[WalletReminder] skip: no eventDate or deleted ticketId=\(ticketId)")
            return
        }

        let now = Date()
        let kind = ticket.kind
        let offsets = kind.defaultReminderOffsets

        // Verifica permessi locali
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            KBLog.sync.kbDebug("[WalletReminder] notifications not authorized — skip")
            return
        }

        for offset in offsets {
            let fireDate = eventDate.addingTimeInterval(offset)
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = reminderTitle(for: kind, offset: offset)
            content.body = ticket.title.isEmpty ? kind.displayName : ticket.title
            content.sound = .default
            content.threadIdentifier = "kidbox.wallet"
            content.userInfo = [
                "type": "wallet_reminder",
                "familyId": ticket.familyId,
                "ticketId": ticketId
            ]

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let identifier = Self.identifier(ticketId: ticketId, offset: offset)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            do {
                try await center.add(request)
                KBLog.sync.kbDebug("[WalletReminder] scheduled \(identifier) fireDate=\(fireDate)")
            } catch {
                KBLog.sync.kbError("[WalletReminder] schedule FAIL \(identifier) err=\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Cancel

    /// Cancella tutte le notifiche pending per un ticket (tutti gli offset).
    func cancelReminders(ticketId: String) async {
        let pending = await center.pendingNotificationRequests()
        let prefix = "wallet.\(ticketId)."
        let toRemove = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }

        guard !toRemove.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
        KBLog.sync.kbDebug("[WalletReminder] cancelled \(toRemove.count) reqs ticketId=\(ticketId)")
    }

    /// Cancella TUTTE le notifiche locali Wallet pending (qualsiasi ticket).
    /// Usata quando l'utente disabilita "Promemoria Wallet" in Settings.
    func cancelAllReminders() async {
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("wallet.") }

        guard !toRemove.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
        KBLog.sync.kbInfo("[WalletReminder] cancelAllReminders cleared count=\(toRemove.count)")
    }

    // MARK: - Helpers

    private static func identifier(ticketId: String, offset: TimeInterval) -> String {
        "wallet.\(ticketId).\(Int(offset))"
    }

    private func reminderTitle(for kind: KBWalletTicketKind, offset: TimeInterval) -> String {
        let absHours = abs(Int(offset / 3600))
        let absMin = abs(Int(offset / 60))

        let when: String
        if absHours >= 24 {
            let days = absHours / 24
            when = days == 1 ? "domani" : "tra \(days) giorni"
        } else if absHours >= 1 {
            when = absHours == 1 ? "tra 1 ora" : "tra \(absHours) ore"
        } else {
            when = "tra \(absMin) min"
        }

        switch kind {
        case .flight:   return "Volo \(when)"
        case .train:    return "Treno \(when)"
        case .ferry:    return "Traghetto \(when)"
        case .bus:      return "Autobus \(when)"
        case .concert:  return "Concerto \(when)"
        case .cinema:   return "Cinema \(when)"
        case .museum:   return "Visita \(when)"
        case .parking:  return "Parcheggio \(when)"
        case .other:    return "Promemoria biglietto"
        }
    }
}
