//
//  KBVisitReminderService.swift
//  KidBox
//

import Foundation
import UserNotifications

// MARK: - KBVisitReminderService

/// Gestisce le notifiche locali di promemoria per le visite mediche.
/// Pattern identico a KBExamReminderService.
///
/// Due tipi di promemoria per ogni visita:
///   - "visit-reminder-{visitId}"  → giorno della visita (ore 09:00 del giorno prima)
///   - "next-visit-{visitId}"      → visita successiva programmata (ore 09:00 del giorno prima)
final class KBVisitReminderService {
    
    static let shared = KBVisitReminderService()
    private init() {}
    
    // MARK: - Identifier helpers
    
    func visitReminderId(for visitId: String) -> String  { "visit-reminder-\(visitId)" }
    func nextVisitReminderId(for visitId: String) -> String { "next-visit-\(visitId)" }
    
    // MARK: - Permessi
    
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }
    
    // MARK: - Pianifica promemoria visita
    
    /// Pianifica (o sostituisce) il promemoria per la visita principale.
    func scheduleVisitReminder(
        visitId:   String,
        date:      Date,
        reason:    String,
        childName: String,
        familyId:  String,
        childId:   String,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.doSchedule(
                    identifier: self.visitReminderId(for: visitId),
                    titleKey:   "Visita domani 🏥",
                    bodyKey:    Self.bodyKey(reason: reason),
                    bodyArgs:   self.bodyArgs(reason: reason, childName: childName, date: date),
                    date:       date,
                    userInfo:   self.userInfo(type: "visit_reminder", familyId: familyId, childId: childId, visitId: visitId),
                    completion: completion
                )
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { DispatchQueue.main.async { completion(false) }; return }
                    self.doSchedule(
                        identifier: self.visitReminderId(for: visitId),
                        titleKey:   "Visita domani 🏥",
                        bodyKey:    Self.bodyKey(reason: reason),
                        bodyArgs:   self.bodyArgs(reason: reason, childName: childName, date: date),
                        date:       date,
                        userInfo:   self.userInfo(type: "visit_reminder", familyId: familyId, childId: childId, visitId: visitId),
                        completion: completion
                    )
                }
            default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    // MARK: - Pianifica promemoria visita successiva
    
    /// Pianifica (o sostituisce) il promemoria per la visita successiva programmata.
    func scheduleNextVisitReminder(
        visitId:   String,
        date:      Date,
        reason:    String,
        childName: String,
        familyId:  String,
        childId:   String,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.doSchedule(
                    identifier: self.nextVisitReminderId(for: visitId),
                    titleKey:   "Visita domani 🏥",
                    bodyKey:    Self.bodyKey(reason: reason),
                    bodyArgs:   self.bodyArgs(reason: reason, childName: childName, date: date),
                    date:       date,
                    userInfo:   self.userInfo(type: "visit_reminder", familyId: familyId, childId: childId, visitId: visitId),
                    completion: completion
                )
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { DispatchQueue.main.async { completion(false) }; return }
                    self.doSchedule(
                        identifier: self.nextVisitReminderId(for: visitId),
                        titleKey:   "Visita domani 🏥",
                        bodyKey:    Self.bodyKey(reason: reason),
                        bodyArgs:   self.bodyArgs(reason: reason, childName: childName, date: date),
                        date:       date,
                        userInfo:   self.userInfo(type: "visit_reminder", familyId: familyId, childId: childId, visitId: visitId),
                        completion: completion
                    )
                }
            default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    // MARK: - Cancella
    
    func cancelVisitReminder(visitId: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [visitReminderId(for: visitId)])
    }
    
    func cancelNextVisitReminder(visitId: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [nextVisitReminderId(for: visitId)])
    }
    
    func cancelAll(visitId: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [
                visitReminderId(for: visitId),
                nextVisitReminderId(for: visitId)
            ])
    }
    
    // MARK: - Core scheduling (identico a KBExamReminderService.doSchedule)
    
    private func doSchedule(
        identifier: String,
        titleKey:   String,
        bodyKey:    String,
        bodyArgs:   [KBNotificationLocalization.Arg],
        date:       Date,
        userInfo:   [String: String],
        completion: @escaping (Bool) -> Void
    ) {
        let content       = UNMutableNotificationContent()
        content.sound     = .default
        content.userInfo  = userInfo
        KBNotificationLocalization.setText(
            on: content,
            titleKey: titleKey,
            bodyKey: bodyKey,
            bodyArgs: bodyArgs
        )
        
        let cal = Calendar.current
        
        // Notifica = giorno prima, stessa ora della visita
        guard let fireDate = cal.date(byAdding: .day, value: -1, to: date),
              fireDate > Date() else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        
        let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        Task {
            let scheduled = await KBLocalNotificationBudget.shared.add(request, priority: .deadline)
            await MainActor.run { completion(scheduled) }
        }
    }
    
    // MARK: - Helpers
    
    /// Chiave del corpo: cambia se la visita ha un motivo indicato.
    private static func bodyKey(reason: String) -> String {
        reason.isEmpty
        ? "Domani alle %@ c'è una visita medica per %@."
        : "Domani alle %@ c'è \"%@\" per %@."
    }

    /// Argomenti del corpo, nell'ordine dei `%@` della chiave corrispondente.
    ///
    /// Quando il nome manca, il fallback resta una chiave: così si ri-traduce
    /// con il resto della frase invece di restare nella lingua di quando il
    /// promemoria è stato programmato.
    private func bodyArgs(
        reason: String,
        childName: String,
        date: Date
    ) -> [KBNotificationLocalization.Arg] {
        let name: KBNotificationLocalization.Arg = childName.isEmpty
            ? .localized("il bambino")
            : .text(childName)
        let fmt = DateFormatter()
        fmt.locale = kbDeviceLocale()
        fmt.dateFormat = "HH:mm"
        let timeStr = fmt.string(from: date)
        return reason.isEmpty ? [.text(timeStr), name] : [.text(timeStr), .text(reason), name]
    }
    
    private func userInfo(type: String, familyId: String, childId: String, visitId: String) -> [String: String] {
        ["type": type, "familyId": familyId, "childId": childId, "visitId": visitId]
    }
}
