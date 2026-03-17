//
//  Kbexamreminderservice.swift
//  KidBox
//
//  Created by vscocca on 13/03/26.
//

import Foundation
import UserNotifications

// MARK: - Notification.Name

extension Notification.Name {
    /// Postata ogni volta che un promemoria esame viene aggiunto o rimosso,
    /// così la lista può aggiornare le badge campanellina senza aspettare onAppear.
    static let examReminderChanged = Notification.Name("kb.examReminderChanged")
}

// MARK: - KBExamReminderService

/// Gestisce le notifiche locali di promemoria per gli esami medici.
/// L'identificatore della notifica è basato sull'`examId` così da
/// poter aggiornare/cancellare in modo preciso.
final class KBExamReminderService {
    
    static let shared = KBExamReminderService()
    private init() {}
    
    // Prefisso usato per tutti gli identifier delle notifiche esame
    private let idPrefix = "kb.exam.reminder."
    
    // MARK: - Permessi
    
    /// Richiede l'autorizzazione alle notifiche, se non ancora concessa.
    /// - Parameter completion: `true` se il permesso è stato concesso.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }
    
    /// Verifica in modo asincrono se esiste già una notifica pianificata per questo esame.
    func isScheduled(examId: String, completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let found = requests.contains { $0.identifier == self.notificationId(for: examId) }
            DispatchQueue.main.async { completion(found) }
        }
    }
    
    // MARK: - Pianifica
    
    /// Pianifica (o sostituisce) un promemoria per un esame.
    /// - Parameters:
    ///   - examId:       Identificatore dell'esame.
    ///   - examName:     Nome dell'esame, usato nel corpo della notifica.
    ///   - childName:    Nome del bambino / membro.
    ///   - familyId:     ID famiglia, necessario per il deep link.
    ///   - childId:      ID bambino, necessario per il deep link.
    ///   - date:         Data a cui mostrare il promemoria.
    ///   - reminderTime: Orario del promemoria. Se nil, scatta alle 08:00.
    ///   - completion:   Chiude con `true` se la notifica è stata pianificata con successo.
    func schedule(
        examId:       String,
        examName:     String,
        childName:    String,
        familyId:     String,
        childId:      String,
        date:         Date,
        reminderTime: Date? = nil,
        completion:   @escaping (Bool) -> Void
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.doSchedule(examId: examId, examName: examName, childName: childName,
                                familyId: familyId, childId: childId,
                                date: date, reminderTime: reminderTime, completion: completion)
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { DispatchQueue.main.async { completion(false) }; return }
                    self.doSchedule(examId: examId, examName: examName, childName: childName,
                                    familyId: familyId, childId: childId,
                                    date: date, reminderTime: reminderTime, completion: completion)
                }
            default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    private func doSchedule(
        examId:       String,
        examName:     String,
        childName:    String,
        familyId:     String,
        childId:      String,
        date:         Date,
        reminderTime: Date?,
        completion:   @escaping (Bool) -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Promemoria esame domani 🩺"
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "it_IT")
        fmt.dateFormat = "HH:mm"
        let timeStr = fmt.string(from: date)
        content.body  = examName.isEmpty
        ? "Domani alle \(timeStr) \(childName) ha un esame."
        : "Domani alle \(timeStr) \(childName) ha l'esame \"\(examName)\"."
        content.sound = .default
        content.userInfo = [
            "type":     "exam_reminder",
            "familyId": familyId,
            "childId":  childId,
            "examId":   examId
        ]
        
        let cal = Calendar.current
        guard let dayBefore = cal.date(byAdding: .day, value: -1, to: date) else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        
        // Se l'utente ha scelto un orario specifico, usalo; altrimenti usa la stessa ora dell'esame
        let components: DateComponents
        if let time = reminderTime {
            var c = cal.dateComponents([.year, .month, .day], from: dayBefore)
            let tc = cal.dateComponents([.hour, .minute], from: time)
            c.hour   = tc.hour   ?? 8
            c.minute = tc.minute ?? 0
            components = c
        } else {
            components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: dayBefore)
        }
        
        guard let fireDate = cal.date(from: components), fireDate > Date() else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        _ = fireDate
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: self.notificationId(for: examId),
            content:    content,
            trigger:    trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }
    
    // MARK: - Cancella
    
    /// Rimuove il promemoria pianificato per un esame (se presente).
    func cancel(examId: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: [notificationId(for: examId)]
            )
    }
    
    // MARK: - Privato
    
    func notificationId(for examId: String) -> String {
        idPrefix + examId
    }
}
