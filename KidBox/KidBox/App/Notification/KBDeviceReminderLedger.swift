//
//  KBDeviceReminderLedger.swift
//  KidBox
//

import Foundation
import UserNotifications

/// Registro locale di quali entità hanno un promemoria armato **su questo device**.
///
/// I promemoria KidBox appartengono al dispositivo che li ha creati: un veicolo o
/// una cura arrivati dal sync non devono avvisare qui. Il path di sync infatti non
/// pianifica più nulla — ma alcuni promemoria vanno rinfrescati periodicamente
/// (la finestra scorrevole delle terapie, e le scadenze veicolo/pagamenti da
/// quando i loro trigger non sono più ricorrenti) e quel refresh legge lo store
/// locale, che contiene anche le righe sincronizzate.
///
/// Questo registro è il filtro che tiene le due cose separate: il refresh rinnova
/// solo ciò che è già stato armato qui, e non crea mai un promemoria nuovo.
/// È l'equivalente iOS di `ReminderAlarmRegistry` su Android.
enum KBDeviceReminderLedger {

    private static let defaultsKey = "kb.device.reminder.ledger"
    private static let adoptionDoneKey = "kb.device.reminder.ledger.adopted"

    // MARK: - Chiavi

    static func treatment(_ id: String) -> String { "treatment:\(id)" }
    static func vehicle(_ id: String) -> String { "vehicle:\(id)" }
    static func housePayment(_ id: String) -> String { "housePayment:\(id)" }

    // MARK: - API

    static func record(_ key: String) {
        var keys = stored()
        guard keys.insert(key).inserted else { return }
        persist(keys)
    }

    static func forget(_ key: String) {
        var keys = stored()
        guard keys.remove(key) != nil else { return }
        persist(keys)
    }

    static func contains(_ key: String) -> Bool {
        stored().contains(key)
    }

    /// Svuota il registro. Al logout non resta traccia del profilo precedente.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: adoptionDoneKey)
    }

    /// Adozione una tantum delle notifiche già in coda al momento dell'aggiornamento.
    ///
    /// Il registro nasce vuoto, ma le notifiche pendenti *sono* già state armate su
    /// questo device — è l'unica cosa che le ha messe in coda. Senza questo passaggio
    /// il refresh non le riconoscerebbe come proprie e non le rinnoverebbe più: le
    /// cure si fermerebbero a fine finestra, e soprattutto i vecchi avvisi veicolo
    /// con trigger annuale (`repeats: true`, ora abbandonato) resterebbero in coda
    /// per sempre senza che nulla li sostituisca.
    @MainActor
    static func adoptExistingPendingIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: adoptionDoneKey) else { return }

        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        var adopted = Set<String>()
        for request in pending {
            let id = request.identifier
            if id.hasPrefix("treatment-") {
                // "treatment-<uuid>-d3-s1" / "treatment-<uuid>-sentinel"
                let rest = id.dropFirst("treatment-".count)
                if let dash = rest.range(of: "-", options: .backwards) {
                    adopted.insert(treatment(String(rest[rest.startIndex..<dash.lowerBound])))
                }
            } else if id.hasPrefix("vehicle.") {
                // "vehicle.<uuid>.<kind>.offset<n>"
                let parts = id.split(separator: ".")
                if parts.count >= 2 { adopted.insert(vehicle(String(parts[1]))) }
            } else if id.hasPrefix("housePayment.") {
                let parts = id.split(separator: ".")
                if parts.count >= 2 { adopted.insert(housePayment(String(parts[1]))) }
            }
        }

        if !adopted.isEmpty {
            persist(stored().union(adopted))
        }
        UserDefaults.standard.set(true, forKey: adoptionDoneKey)
        KBLog.sync.kbInfo("[ReminderLedger] adozione una tantum: \(adopted.count) entità riconosciute su \(pending.count) notifiche pendenti")
    }

    // MARK: - Privato

    private static func stored() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    private static func persist(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys), forKey: defaultsKey)
    }
}
