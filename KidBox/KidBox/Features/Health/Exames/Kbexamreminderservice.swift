//
//  Kbexamreminderservice.swift
//  KidBox
//
//  Created by vscocca on 13/03/26.
//


import Foundation
import UserNotifications

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
    ///   - examId:    Identificatore dell'esame.
    ///   - examName:  Nome dell'esame, usato nel corpo della notifica.
    ///   - childName: Nome del bambino.
    ///   - date:      Data a cui mostrare il promemoria (alle 08:00 del mattino).
    ///   - completion: Chiude con `true` se la notifica è stata pianificata con successo.
    func schedule(
        examId:    String,
        examName:  String,
        childName: String,
        date:      Date,
        completion: @escaping (Bool) -> Void
    ) {
        requestAuthorization { [weak self] granted in
            guard let self, granted else {
                completion(false)
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = "Promemoria esame 🩺"
            content.body  = "\(childName) ha l'esame \"\(examName)\" oggi."
            content.sound = .default
            
            // Scatta alle 08:00 della data indicata
            var components        = Calendar.current.dateComponents([.year, .month, .day], from: date)
            components.hour       = 8
            components.minute     = 0
            
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
            
            let request = UNNotificationRequest(
                identifier: self.notificationId(for: examId),
                content:    content,
                trigger:    trigger
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                DispatchQueue.main.async { completion(error == nil) }
            }
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
    
    private func notificationId(for examId: String) -> String {
        idPrefix + examId
    }
}
