//
//  Kbexamreminderservice.swift
//  KidBox
//
//  Created by vscocca on 13/03/26.
//
//  FIX (02/04/26):
//  - La notifica ora scatta nella DATA e all'ORARIO scelto dall'utente
//    (non più il giorno prima).
//  - Identifier univoco per data: "kb.exam.reminder.<examId>.<YYYYMMDD>"
//    così più notifiche per lo stesso esame non si sovrascrivono.
//  - cancel(examId:) rimuove TUTTE le notifiche con quel prefisso esame.
//  - isScheduled(examId:) controlla il prefisso, non solo l'id esatto.

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
/// L'identificatore della notifica è "kb.exam.reminder.<examId>.<YYYYMMDD>"
/// così ogni data genera una notifica indipendente che non sovrascrive le altre.
final class KBExamReminderService {
    
    static let shared = KBExamReminderService()
    private init() {}
    
    // Prefisso base usato per tutti gli identifier delle notifiche esame
    private let idPrefix = "kb.exam.reminder."
    
    // MARK: - Identifier helpers
    
    /// Prefisso per tutte le notifiche di un dato esame (usato per cancel/isScheduled).
    func notificationPrefix(for examId: String) -> String {
        idPrefix + examId + "."
    }
    
    /// Identifier univoco per un esame + una data specifica.
    func notificationId(for examId: String, date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year,  from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day,   from: date)
        let dateTag = String(format: "%04d%02d%02d", y, m, d)
        return notificationPrefix(for: examId) + dateTag
    }
    
    /// Mantiene la firma originale per compatibilità con codice esistente:
    /// restituisce il prefisso (senza data) — utile solo per lookup legacy.
    func notificationId(for examId: String) -> String {
        notificationPrefix(for: examId)
    }
    
    // MARK: - Permessi
    
    /// Richiede l'autorizzazione alle notifiche, se non ancora concessa.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }
    
    /// Verifica se esiste almeno una notifica pianificata per questo esame.
    func isScheduled(examId: String, completion: @escaping (Bool) -> Void) {
        let prefix = notificationPrefix(for: examId)
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let found = requests.contains { $0.identifier.hasPrefix(prefix) }
            DispatchQueue.main.async { completion(found) }
        }
    }
    
    // MARK: - Pianifica
    
    /// Pianifica (o sostituisce) un promemoria per un esame.
    /// La notifica scatta nella `date` fornita all'orario scelto in `reminderTime`
    /// (default 08:00 se nil).
    ///
    /// - Parameters:
    ///   - examId:       Identificatore dell'esame.
    ///   - examName:     Nome dell'esame, usato nel corpo della notifica.
    ///   - childName:    Nome del bambino / membro.
    ///   - familyId:     ID famiglia, necessario per il deep link.
    ///   - childId:      ID bambino, necessario per il deep link.
    ///   - date:         Data dell'esame a cui mostrare il promemoria.
    ///   - reminderTime: Orario del promemoria. Se nil, scatta alle 08:00.
    ///   - completion:   Chiude con `true` se la notifica è stata pianificata.
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
                self.doSchedule(
                    examId: examId, examName: examName, childName: childName,
                    familyId: familyId, childId: childId,
                    date: date, reminderTime: reminderTime, completion: completion
                )
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound, .badge]
                ) { granted, _ in
                    guard granted else {
                        DispatchQueue.main.async { completion(false) }
                        return
                    }
                    self.doSchedule(
                        examId: examId, examName: examName, childName: childName,
                        familyId: familyId, childId: childId,
                        date: date, reminderTime: reminderTime, completion: completion
                    )
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
        // ── Contenuto notifica ──
        let content       = UNMutableNotificationContent()
        content.title     = "Promemoria esame 🩺"
        let fmt           = DateFormatter()
        fmt.locale        = kbDeviceLocale()
        fmt.dateFormat    = "HH:mm"
        
        // Determina l'orario effettivo che apparirà nel body
        let displayTime: String
        if let time = reminderTime {
            displayTime = fmt.string(from: time)
        } else {
            // default 08:00
            var dc = Calendar.current.dateComponents([.year, .month, .day], from: date)
            dc.hour = 8; dc.minute = 0
            displayTime = "08:00"
        }
        
        content.body = examName.isEmpty
        ? "Oggi alle \(displayTime) \(childName) ha un esame."
        : "Oggi alle \(displayTime) \(childName) ha l'esame \"\(examName)\"."
        content.sound     = .default
        content.userInfo  = [
            "type":     "exam_reminder",
            "familyId": familyId,
            "childId":  childId,
            "examId":   examId
        ]
        
        // ── Costruisce i DateComponents per il trigger ──
        // Usa la DATA dell'esame + l'ORARIO scelto dall'utente (o 08:00)
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: date)
        
        if let time = reminderTime {
            let tc      = cal.dateComponents([.hour, .minute], from: time)
            components.hour   = tc.hour   ?? 8
            components.minute = tc.minute ?? 0
        } else {
            components.hour   = 8
            components.minute = 0
        }
        components.second = 0
        
        // Controlla che il momento calcolato sia nel futuro
        guard let fireDate = cal.date(from: components), fireDate > Date() else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        _ = fireDate // usato solo per la guard
        
        // ── Identifier univoco per questa data ──
        let uniqueId = notificationId(for: examId, date: date)
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: uniqueId,
            content:    content,
            trigger:    trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }
    
    // MARK: - Cancella
    
    /// Rimuove TUTTE le notifiche pianificate per un esame (qualunque data).
    func cancel(examId: String) {
        let prefix = notificationPrefix(for: examId)
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.hasPrefix(prefix) }
                .map    { $0.identifier }
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
