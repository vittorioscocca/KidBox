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
    private static let dailyBriefingNotifDefaultsKey = "kb_dailyBriefing_notifId"
    private static let healthPatternNotifDefaultsKey = "kb_healthPattern_notifId"

    /// Cancella **tutte** le notifiche locali dell'app (pendenti e già consegnate)
    /// e i riferimenti in `UserDefaults` che le accompagnano.
    ///
    /// Non c'è una lista di prefissi da tenere aggiornata: ogni notifica locale in
    /// coda è stata schedulata da KidBox per l'utente che sta uscendo, quindi si
    /// azzera tutto. La versione precedente filtrava per prefisso e ne dimenticava
    /// sei famiglie — documenti Wallet, veicoli, pagamenti casa, nudge, briefing e
    /// insight continuavano ad arrivare dopo il logout.
    @MainActor
    static func cancelAllScheduledAccountReminders() async {
        let center = UNUserNotificationCenter.current()
        let pendingCount = await center.pendingNotificationRequests().count

        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        // Il registro di cosa è armato su questo device e i puntatori alle
        // notifiche AI: senza questi, al login successivo l'app crederebbe di
        // avere ancora in coda notifiche che non esistono più.
        KBDeviceReminderLedger.clear()
        NudgeState.clearFireHistory()
        for key in [
            weeklySummaryNotifDefaultsKey,
            dailyBriefingNotifDefaultsKey,
            healthPatternNotifDefaultsKey,
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        KBLog.auth.kbInfo("KidBoxLocalNotificationsCleanup: rimosse tutte le notifiche locali (\(pendingCount) pendenti)")
    }
}
