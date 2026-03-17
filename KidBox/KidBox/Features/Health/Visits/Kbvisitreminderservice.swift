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
                    title:      "Visita domani 🏥",
                    body:       self.body(reason: reason, childName: childName, date: date),
                    date:       date,
                    userInfo:   self.userInfo(type: "visit_reminder", familyId: familyId, childId: childId, visitId: visitId),
                    completion: completion
                )
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { DispatchQueue.main.async { completion(false) }; return }
                    self.doSchedule(
                        identifier: self.visitReminderId(for: visitId),
                        title:      "Visita domani 🏥",
                        body:       self.body(reason: reason, childName: childName, date: date),
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
                    title:      "Visita domani 🏥",
                    body:       self.body(reason: reason, childName: childName, date: date),
                    date:       date,
                    userInfo:   self.userInfo(type: "visit_reminder", familyId: familyId, childId: childId, visitId: visitId),
                    completion: completion
                )
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { DispatchQueue.main.async { completion(false) }; return }
                    self.doSchedule(
                        identifier: self.nextVisitReminderId(for: visitId),
                        title:      "Visita domani 🏥",
                        body:       self.body(reason: reason, childName: childName, date: date),
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
        title:      String,
        body:       String,
        date:       Date,
        userInfo:   [String: String],
        completion: @escaping (Bool) -> Void
    ) {
        let content       = UNMutableNotificationContent()
        content.title     = title
        content.body      = body
        content.sound     = .default
        content.userInfo  = userInfo
        
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
        
        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }
    
    // MARK: - Helpers
    
    private func body(reason: String, childName: String, date: Date) -> String {
        let name = childName.isEmpty ? "il bambino" : childName
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "it_IT")
        fmt.dateFormat = "HH:mm"
        let timeStr = fmt.string(from: date)
        return reason.isEmpty
        ? "Domani alle \(timeStr) c'è una visita medica per \(name)."
        : "Domani alle \(timeStr) c'è \"\(reason)\" per \(name)."
    }
    
    private func userInfo(type: String, familyId: String, childId: String, visitId: String) -> [String: String] {
        ["type": type, "familyId": familyId, "childId": childId, "visitId": visitId]
    }
}
