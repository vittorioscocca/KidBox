//
//  KBVaccineReminderService.swift
//  KidBox
//
//  Promemoria locale solo per vaccini in stato «Da programmare» (planned),
//  il giorno prima della data prevista del richiamo alle 9:00.
//

import Foundation
import UserNotifications

@MainActor
final class KBVaccineReminderService {
    static let shared = KBVaccineReminderService()
    private init() {}

    private func notificationId(vaccineId: String) -> String {
        "kb.vaccine.reminder.\(vaccineId)"
    }

    nonisolated func cancel(vaccineId: String) {
        let id = "kb.vaccine.reminder.\(vaccineId)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    private static func fireDayBeforeNine(from nextDose: Date) -> Date {
        let cal = Calendar.current
        guard let dayBefore = cal.date(byAdding: .day, value: -1, to: nextDose) else { return nextDose }
        var c = cal.dateComponents([.year, .month, .day], from: dayBefore)
        c.hour = 9
        c.minute = 0
        c.second = 0
        return cal.date(from: c) ?? dayBefore
    }

    func sync(vaccine: KBVaccine, childName: String) async {
        cancel(vaccineId: vaccine.id)
        guard vaccine.reminderOn,
              vaccine.status == .planned,
              let next = vaccine.nextDoseDate,
              next > Date()
        else { return }

        let fire = Self.fireDayBeforeNine(from: next)
        guard fire > Date() else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            break
        case .notDetermined:
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                    cont.resume(returning: ok)
                }
            }
            guard granted else { return }
        default:
            return
        }

        let nm = (vaccine.commercialName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let titleText = nm.isEmpty ? vaccine.vaccineType.displayName : nm
        let who = childName.trimmingCharacters(in: .whitespacesAndNewlines)
        let whoLabel = who.isEmpty ? "il bambino" : who

        let content = UNMutableNotificationContent()
        content.title = "Promemoria vaccino"
        content.body = "Domani alle 9:00: vaccino «\(titleText)» per \(whoLabel)."
        content.sound = .default
        content.userInfo = [
            "type": "vaccine_reminder",
            "familyId": vaccine.familyId,
            "childId": vaccine.childId,
            "vaccineId": vaccine.id,
        ]

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationId(vaccineId: vaccine.id),
            content: content,
            trigger: trigger,
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
