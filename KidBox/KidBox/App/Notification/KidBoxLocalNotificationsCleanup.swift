//
//  KidBoxLocalNotificationsCleanup.swift
//  KidBox
//
//  Rimuove i promemoria locali (UNUserNotificationCenter) schedulati dall'app
//  al logout / wipe account, così non restano notifiche del profilo precedente.
//

import Foundation
import UserNotifications

enum KidBoxLocalNotificationsCleanup {

    private static let weeklySummaryNotifDefaultsKey = "kb_weeklySummary_notifId"

    /// Cancella tutte le richieste locali KidBox (pending + delivered) e il riferimento
    /// UserDefaults alla notifica sintesi settimanale.
    @MainActor
    static func cancelAllScheduledAccountReminders() async {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        let ids = requests.map(\.identifier).filter { isKidBoxScheduledReminderIdentifier($0) }

        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: ids)
            KBLog.auth.kbInfo("KidBoxLocalNotificationsCleanup: removed \(ids.count) notification id(s)")
        }

        UserDefaults.standard.removeObject(forKey: weeklySummaryNotifDefaultsKey)
    }

    nonisolated private static func isKidBoxScheduledReminderIdentifier(_ id: String) -> Bool {
        if id == "kb.subscription.expiring" { return true }
        if id == "kb-weekly-summary" { return true }
        if id.hasPrefix("todo.reminder.") { return true }
        if id.hasPrefix("kb.exam.reminder.") { return true }
        if id.hasPrefix("visit-reminder-") { return true }
        if id.hasPrefix("next-visit-") { return true }
        if id.hasPrefix("treatment-") { return true }
        if id.hasPrefix("wallet.") { return true }
        if id.hasPrefix("kb-weekly-summary-") { return true }
        if id.hasPrefix("kb.vaccine.reminder.") { return true }
        if id.hasPrefix("kb.password.expiry.") { return true }
        if id.hasPrefix("kb.password.security.summary.") { return true }
        return false
    }
}
