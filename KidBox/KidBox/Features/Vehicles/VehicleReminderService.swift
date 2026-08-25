//
//  VehicleReminderService.swift
//  KidBox
//

import Foundation
import SwiftData
import UserNotifications

/// Notifiche locali per le scadenze veicolo in Garage.
///
/// Strategia:
/// - Identificativi deterministici `vehicle.<vehicleId>.<kind>.offset<giorni>` così
///   aggiornare/cancellare è idempotente.
/// - `UNCalendarNotificationTrigger` sulla data concreta della scadenza, **non
///   ricorrente**. Un trigger annuale non lascia mai la coda dei pendenti: con 64
///   slot totali due auto ne occupavano 16 in permanenza, e continuavano ad
///   avvisare per anni su una polizza mai rinnovata. Ora ogni avviso libera il
///   suo posto quando scatta, e la finestra si riapre da [rescheduleAllActive]
///   al rientro in app — stesso schema di `HousePaymentReminderService`.
/// - Fino a 3 avvisi per scadenza, scelti dall'utente tra: giorno stesso, 2 giorni prima,
///   1 settimana prima (`KBVehicle.reminderOffsetsJson`).
@MainActor
final class VehicleReminderService {

    static let shared = VehicleReminderService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    // MARK: - Public

    func cancelAll(vehicleId: String) async {
        KBDeviceReminderLedger.forget(KBDeviceReminderLedger.vehicle(vehicleId))
        let prefix = Self.idPrefix(vehicleId: vehicleId)
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        KBLog.sync.kbDebug("[VehicleReminder] cancelled count=\(ids.count) vehicleId=\(vehicleId)")
    }

    /// Riapre la finestra per tutti i veicoli con promemoria attivi. Va chiamata
    /// al rientro in app: senza trigger ricorrenti è l'unico momento in cui gli
    /// avvisi già scattati vengono rimpiazzati.
    func rescheduleAllActive(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<KBVehicle>(
            predicate: #Predicate { $0.isDeleted == false && $0.reminderEnabled == true }
        )
        guard let rows = try? modelContext.fetch(descriptor) else { return }
        // Solo ciò che è già armato su questo device: il refresh rinnova, non crea.
        let mine = rows.filter { KBDeviceReminderLedger.contains(KBDeviceReminderLedger.vehicle($0.id)) }
        for vehicle in mine {
            await scheduleReminders(for: vehicle)
        }
        KBLog.sync.kbDebug("[VehicleReminder] rescheduleAllActive count=\(mine.count)/\(rows.count)")
    }

    /// (Ri)schedula tutti i promemoria per un veicolo in base a `reminderEnabled` e alle date impostate.
    func scheduleReminders(for vehicle: KBVehicle) async {
        await cancelAll(vehicleId: vehicle.id)

        guard vehicle.reminderEnabled, !vehicle.isDeleted else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            KBLog.sync.kbDebug("[VehicleReminder] notifications not authorized — skip vehicleId=\(vehicle.id)")
            return
        }

        let calendar = Calendar.current
        let label = vehicle.name
        let offsets = VehicleReminderOffsets.decode(json: vehicle.reminderOffsetsJson)

        let specs: [(key: String, title: String, date: Date?)] = [
            ("insurance", String(localized: "Assicurazione"), vehicle.insuranceExpiryDate),
            ("revision", String(localized: "Revisione"), vehicle.revisionExpiryDate),
            ("tax", String(localized: "Bollo"), vehicle.taxExpiryDate),
            ("service", String(localized: "Prossimo tagliando"), vehicle.nextServiceDate),
        ]

        for spec in specs {
            guard let deadline = spec.date else { continue }
            let startOfDeadline = calendar.startOfDay(for: deadline)

            for days in offsets.offsets(forKind: spec.key) {
                guard let fireDay = calendar.date(byAdding: .day, value: -days, to: startOfDeadline) else { continue }
                var comps = calendar.dateComponents([.year, .month, .day], from: fireDay)
                comps.hour = 9
                comps.minute = 0
                // Scadenza già passata: niente avviso finché l'utente non aggiorna
                // la data. Stesso comportamento del client Android.
                guard let fireDate = calendar.date(from: comps), fireDate > Date() else { continue }

                await scheduleOne(
                    identifier: "vehicle.\(vehicle.id).\(spec.key).offset\(days)",
                    title: "\(String(localized: "Promemoria")): \(spec.title): \(label)",
                    body: Self.offsetBody(days: days),
                    familyId: vehicle.familyId,
                    vehicleId: vehicle.id,
                    kind: spec.key,
                    slot: "offset\(days)",
                    components: comps
                )
            }
        }
    }

    // MARK: - Private

    private static func offsetBody(days: Int) -> String {
        switch days {
        case 0: return String(localized: "Scade oggi — tocca in Garage.")
        case 2: return String(localized: "Scade tra 2 giorni — Garage.")
        case 7: return String(localized: "Scade tra una settimana — Garage.")
        default: return String(localized: "Scade tra una settimana — Garage.")
        }
    }

    private static func idPrefix(vehicleId: String) -> String { "vehicle.\(vehicleId)." }

    private func scheduleOne(
        identifier: String,
        title: String,
        body: String,
        familyId: String,
        vehicleId: String,
        kind: String,
        slot: String,
        components: DateComponents
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "kidbox.vehicles"
        content.userInfo = [
            "type": "vehicle_deadline_reminder",
            "familyId": familyId,
            "vehicleId": vehicleId,
            "kind": kind,
            "slot": slot,
        ]

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        if await KBLocalNotificationBudget.shared.add(request, priority: .deadline) {
            KBDeviceReminderLedger.record(KBDeviceReminderLedger.vehicle(vehicleId))
            KBLog.sync.kbDebug("[VehicleReminder] scheduled id=\(identifier)")
        }
    }
}
