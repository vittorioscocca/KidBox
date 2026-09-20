//
//  KBReminderPermission.swift
//  KidBox
//
//  Cancello unico per accendere un promemoria locale (visite, esami, vaccini,
//  cure, biglietti e documenti del Wallet), speculare a `ReminderPermission`
//  su Android.
//
//  Senza il permesso notifiche i servizi di promemoria escono in silenzio
//  (`guard authorized else { return }`): l'interruttore diceva «attivo» e il
//  telefono restava muto. Qui l'accensione passa prima dal permesso —
//  [KBReminderPermissionGate] chiede se manca, riporta l'interruttore a spento
//  se negato e alza `denied`, così la vista mostra [KBNotificationsDisabledCard]
//  con il rimando alle Impostazioni. Al rientro in foreground si rilegge:
//  l'utente riattiva nelle Impostazioni, torna, e l'avviso sparisce.
//

import SwiftUI
import UserNotifications

enum KBReminderPermission {

    /// Le notifiche possono arrivare su questo device.
    static func isGranted() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    /// Chiede il permesso se non è ancora stato deciso. `true` se le notifiche
    /// possono arrivare; `false` se negato (adesso o in passato).
    static func requestIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let s = await center.notificationSettings()
        switch s.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .authorized, .provisional:
            return true
        default:
            return false
        }
    }
}

// MARK: - Card «Notifiche disabilitate»

/// Avviso con il rimando alle Impostazioni, estratto da `TreatmentDetailView`
/// e riusato sotto ogni interruttore di promemoria. Le stringhe sono le stesse
/// già tradotte nel catalogo.
struct KBNotificationsDisabledCard: View {
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifiche disabilitate").font(.caption.bold())
                    Text("Abilita le notifiche nelle Impostazioni per ricevere i promemoria.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))

            Button("Apri Impostazioni") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption).foregroundStyle(tint)
        }
    }
}

// MARK: - Gate per un interruttore

/// Da applicare al `Toggle` di un promemoria: all'accensione chiede il
/// permesso; se negato riporta `isOn` a `false` e mette `denied` a `true`.
/// Se l'interruttore è già acceso ma le notifiche sono bloccate (permesso
/// revocato dopo averlo armato), `denied` va a `true` alla comparsa.
struct KBReminderPermissionGate: ViewModifier {
    @Binding var isOn: Bool
    @Binding var denied: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isOn) { _, on in
                guard on else { return }
                Task { @MainActor in
                    let ok = await KBReminderPermission.requestIfNeeded()
                    denied = !ok
                    if !ok { isOn = false }
                }
            }
            .task {
                if isOn { denied = !(await KBReminderPermission.isGranted()) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { @MainActor in
                    let ok = await KBReminderPermission.isGranted()
                    if ok { denied = false } else if isOn { denied = true }
                }
            }
    }
}

extension View {
    /// Vedi [KBReminderPermissionGate].
    func reminderPermissionGate(isOn: Binding<Bool>, denied: Binding<Bool>) -> some View {
        modifier(KBReminderPermissionGate(isOn: isOn, denied: denied))
    }
}
