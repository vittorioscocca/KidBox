//
//  VehicleReminderService.swift
//  KidBox
//

import Foundation
import UserNotifications

/// Notifiche locali ricorrenti (stesso giorno ogni anno) per le scadenze veicolo in Garage.
///
/// Strategia:
/// - Identificativi deterministici `vehicle.<vehicleId>.<kind>.<slot>` (`due` | `week`) così
///   aggiornare/cancellare è idempotente.
/// - `UNCalendarNotificationTrigger` con `repeats: true` su mese/giorno/ora (09:00) per
///   ricorrenza annuale (allineata al calendario utente).
/// - Due slot per scadenza: giorno della scadenza e 7 giorni prima.
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

        let specs: [(key: String, dueTitle: String, weekTitle: String, date: Date?)] = [
            ("insurance", "Assicurazione", "Assicurazione (tra 7 giorni)", vehicle.insuranceExpiryDate),
            ("revision", "Revisione", "Revisione (tra 7 giorni)", vehicle.revisionExpiryDate),
            ("tax", "Bollo", "Bollo (tra 7 giorni)", vehicle.taxExpiryDate),
            ("service", "Tagliando", "Tagliando (tra 7 giorni)", vehicle.nextServiceDate),
        ]

        for spec in specs {
            guard let deadline = spec.date else { continue }
            let startOfDeadline = calendar.startOfDay(for: deadline)
            guard let weekBefore = calendar.date(byAdding: .day, value: -7, to: startOfDeadline) else { continue }

            let dueDay = calendar.dateComponents([.month, .day], from: startOfDeadline)
            var dueComps = DateComponents()
            dueComps.month = dueDay.month
            dueComps.day = dueDay.day
            dueComps.hour = 9
            dueComps.minute = 0

            let weekDay = calendar.dateComponents([.month, .day], from: weekBefore)
            var weekComps = DateComponents()
            weekComps.month = weekDay.month
            weekComps.day = weekDay.day
            weekComps.hour = 9
            weekComps.minute = 0

            await scheduleOne(
                identifier: "vehicle.\(vehicle.id).\(spec.key).due",
                title: "\(spec.dueTitle): \(label)",
                body: "Scadenza oggi — tocca in Garage.",
                familyId: vehicle.familyId,
                vehicleId: vehicle.id,
                kind: spec.key,
                slot: "due",
                components: dueComps,
                repeats: true
            )
            await scheduleOne(
                identifier: "vehicle.\(vehicle.id).\(spec.key).week",
                title: "\(spec.weekTitle): \(label)",
                body: "Tra una settimana — Garage.",
                familyId: vehicle.familyId,
                vehicleId: vehicle.id,
                kind: spec.key,
                slot: "week",
                components: weekComps,
                repeats: true
            )
        }
    }

    // MARK: - Private

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
