//
//  KBChatAvailability.swift
//  KidBox
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Interruttore della chat di famiglia.
///
/// È una preferenza **dell'account**, non del telefono: vive su
/// `users/{uid}.appPrefs.chatEnabled` e segue l'utente su tutti i suoi
/// dispositivi, iOS e Android insieme — stesso trattamento delle preferenze di
/// notifica in `users/{uid}.notificationPrefs`.
///
/// `UserDefaults` resta solo come **cache locale**: serve a disegnare la Home
/// subito e a funzionare offline, ed è la chiave che le view leggono con
/// `@AppStorage` per aggiornarsi da sole.
///
/// Spegnendola questo account non vede più la chat, ma gli altri membri
/// continuano a scriversi e i messaggi restano sul server: riaccendendola si
/// ritrova tutto.
///
/// Gemello di `ChatAvailability` su Android, stesso campo Firestore.
enum KBChatAvailability {

    static let defaultsKey = "kb_chatEnabled"

    private static let prefsField = "appPrefs"
    private static let chatField = "chatEnabled"

    /// Ricorda che le notifiche dei messaggi le abbiamo spente **noi** insieme
    /// alla chat: serve a non riaccenderle a chi le aveva già disattivate.
    private static let pausedNotificationsKey = "kb_chatNotificationsPausedByChatOff"

    /// Cache locale di `SettingsViewModel.LocalKeys.notifyOnNewMessages`: va
    /// tenuta allineata o Impostazioni mostrerebbe il vecchio valore.
    private static let notifyMessagesCacheKey = "kb_notifyOnNewMessages"

    /// `object(forKey:)` e non `bool(forKey:)`: quest'ultimo non distingue
    /// "mai scritta" da `false` e al primo avvio spegnerebbe la chat.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// Aggiorna cache e account. La cache si scrive per prima così l'interfaccia
    /// reagisce subito, anche senza rete.
    static func set(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
        Task {
            await pushToRemote(enabled)
            await syncMessageNotifications(chatEnabled: enabled)
        }
    }

    /// Con la chat spenta una notifica di messaggio porterebbe a una schermata
    /// che si rifiuta di aprirsi: si spengono insieme.
    ///
    /// Riaccendendo la chat le notifiche tornano **solo se le avevamo spente noi**.
    /// Chi le aveva già disattivate per conto suo se le ritrova disattivate.
    private static func syncMessageNotifications(chatEnabled: Bool) async {
        let defaults = UserDefaults.standard
        let notifications = NotificationManager.shared

        if !chatEnabled {
            let wasOn = await notifications.fetchNotifyOnNewMessagesPreference()
            guard wasOn else { return }
            defaults.set(true, forKey: pausedNotificationsKey)
            try? await notifications.setNotifyOnNewMessages(false)
            defaults.set(false, forKey: notifyMessagesCacheKey)
            KBLog.settings.kbInfo("Chat disattivata: spente anche le notifiche dei messaggi")
        } else if defaults.bool(forKey: pausedNotificationsKey) {
            defaults.set(false, forKey: pausedNotificationsKey)
            try? await notifications.setNotifyOnNewMessages(true)
            defaults.set(true, forKey: notifyMessagesCacheKey)
            KBLog.settings.kbInfo("Chat riattivata: riaccese le notifiche dei messaggi")
        }
    }

    /// Allinea la cache al valore sull'account. Va chiamata al login e a ogni
    /// ingresso in Impostazioni → Messaggi.
    static func refreshFromRemote() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let prefs = snap.get(prefsField) as? [String: Any],
                  let remote = prefs[chatField] as? Bool
            else {
                // Campo assente = mai toccato: la chat resta attiva.
                await MainActor.run { UserDefaults.standard.set(true, forKey: defaultsKey) }
                return
            }
            await MainActor.run { UserDefaults.standard.set(remote, forKey: defaultsKey) }
        } catch {
            // Offline: si tiene la cache, che è già il valore giusto dell'ultima volta.
            KBLog.settings.kbDebug("KBChatAvailability refresh fallito: \(error.localizedDescription)")
        }
    }

    private static func pushToRemote(_ enabled: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await Firestore.firestore().collection("users").document(uid)
                .setData([prefsField: [chatField: enabled]], merge: true)
            KBLog.settings.kbInfo("KBChatAvailability chatEnabled=\(enabled) salvato sull'account")
        } catch {
            KBLog.settings.kbError("KBChatAvailability salvataggio fallito: \(error.localizedDescription)")
        }
    }
}
