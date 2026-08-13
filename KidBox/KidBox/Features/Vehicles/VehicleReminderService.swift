//
//  VehicleReminderService.swift
//  KidBox
//

import Foundation
import UserNotifications

/// Notifiche locali ricorrenti (stesso giorno ogni anno) per le scadenze veicolo in Garage.
///
/// Strategia:
/// - Identificativi deterministici `vehicle.<vehicleId>.<kind>.offset<giorni>` così
///   aggiornare/cancellare è idempotente.
/// - `UNCalendarNotificationTrigger` con `repeats: true` su mese/giorno/ora (09:00) per
///   ricorrenza annuale (allineata al calendario utente).
/// - Fino a 3 avvisi per scadenza, scelti dall'utente tra: giorno stesso, 2 giorni prima,
///   1 settimana prima (`KBVehicle.reminderOffsetsJson`).
@MainActor
final class VehicleReminderService {

    static let shared = VehicleReminderService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    // MARK: - Public

    func cancelAll(vehicleId: String) async {
        let prefix = Self.idPrefix(vehicleId: vehicleId)
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        KBLog.sync.kbDebug("[VehicleReminder] cancelled count=\(ids.count) vehicleId=\(vehicleId)")
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
                let dayComps = calendar.dateComponents([.month, .day], from: fireDay)
                var comps = DateComponents()
                comps.month = dayComps.month
                comps.day = dayComps.day
                comps.hour = 9
                comps.minute = 0

                await scheduleOne(
                    identifier: "vehicle.\(vehicle.id).\(spec.key).offset\(days)",
                    title: "\(String(localized: "Promemoria")): \(spec.title): \(label)",
                    body: Self.offsetBody(days: days),
                    familyId: vehicle.familyId,
                    vehicleId: vehicle.id,
                    kind: spec.key,
                    slot: "offset\(days)",
                    components: comps,
                    repeats: true
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
        components: DateComponents,
        repeats: Bool
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

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            KBLog.sync.kbDebug("[VehicleReminder] scheduled id=\(identifier)")
        } catch {
            KBLog.sync.kbError("[VehicleReminder] schedule FAIL id=\(identifier) err=\(error.localizedDescription)")
        }
    }
}
