//
//  TreatmentNotificationManager.swift
//  KidBox
//

import Foundation
import UserNotifications
import OSLog

enum TreatmentNotificationManager {
    
    // Quanti giorni pianificare in anticipo per volta
    private static let windowDays = 7
    
    // Soglia: se le notifiche pendenti per questa cura scendono sotto N, rischedula
    private static let rescheduleThreshold = 2
    
    private static let log = Logger(
        subsystem: "it.vittorioscocca.kidbox",
        category:  "TreatmentNotifications"
    )
    
    // MARK: - Autorizzazione
    
    static func requestAuthorization() async -> Bool {
        let center   = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return settings.authorizationStatus == .authorized
        }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    
    // MARK: - Schedule (finestra scorrevole)
    
    /// Cancella le notifiche esistenti e pianifica la prima finestra di `windowDays` giorni.
    /// Da chiamare quando si crea/modifica una cura o si cambiano gli orari.
    static func schedule(treatment: KBTreatment, childName: String) {
        cancel(treatmentId: treatment.id)
        guard treatment.reminderEnabled, treatment.isActive else { return }
        
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        
        // Primo giorno da schedulare: max(startDate, oggi)
        let startDay = cal.startOfDay(for: treatment.startDate)
        guard let windowStart = [startDay, today].max() else { return }
        
        // Ultimo giorno della cura (nil = lungo termine → usiamo windowDays)
        let careEnd: Date?
        if treatment.isLongTerm {
            careEnd = nil
        } else {
            let lastDayOffset = treatment.durationDays - 1
            careEnd = cal.date(byAdding: .day, value: lastDayOffset, to: treatment.startDate)
        }
        
        scheduleWindow(
            treatment:   treatment,
            childName:   childName,
            windowStart: windowStart,
            careEnd:     careEnd
        )
    }
    
    /// Rischedula la finestra successiva se le notifiche pendenti sono poche.
    /// Chiamare da AppDelegate.applicationDidBecomeActive e dal delegate delle notifiche.
    static func rescheduleIfNeeded(treatment: KBTreatment, childName: String) {
        guard treatment.reminderEnabled, treatment.isActive else { return }
        
        let prefix = notificationPrefix(for: treatment.id)
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let pending = requests.filter { $0.identifier.hasPrefix(prefix) }
            
            // Non fare nulla se ci sono ancora abbastanza notifiche
            guard pending.count <= rescheduleThreshold else { return }
            
            // Trova la data più lontana già schedulata (escludendo la sentinella)
            let cal = Calendar.current
            let latestFire: Date? = pending
                .compactMap { req -> Date? in
                    guard !req.identifier.hasSuffix("-sentinel"),
                          let trigger = req.trigger as? UNCalendarNotificationTrigger
                    else { return nil }
                    return cal.date(from: trigger.dateComponents)
                }
                .max()
            
            // La nuova finestra parte dal giorno dopo l'ultima notifica schedulata,
            // oppure da oggi se non ne rimane nessuna
            let today      = cal.startOfDay(for: Date())
            let windowStart: Date
            if let latest = latestFire {
                windowStart = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: latest)) ?? today
            } else {
                windowStart = today
            }
            
            let careEnd: Date?
            if treatment.isLongTerm {
                careEnd = nil
            } else {
                let lastDayOffset = treatment.durationDays - 1
                careEnd = cal.date(byAdding: .day, value: lastDayOffset, to: treatment.startDate)
            }
            
            // Se la nuova finestra è già oltre la fine della cura, non fare nulla
            if let end = careEnd, windowStart > end { return }
            
            scheduleWindow(
                treatment:   treatment,
                childName:   childName,
                windowStart: windowStart,
                careEnd:     careEnd
            )
        }
    }
    
    // MARK: - Cancella
    
    /// Rimuove tutte le notifiche (normali + sentinella) di questa cura.
    static func cancel(treatmentId: String) {
        let prefix = notificationPrefix(for: treatmentId)
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.hasPrefix(prefix) }
                .map    { $0.identifier }
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ids)
            log.info("cancel: removed \(ids.count) notifications for treatment=\(treatmentId)")
        }
    }
    
    /// Rimuove la notifica pendente (e quella già consegnata) per uno slot specifico.
    /// Da chiamare quando si registra una dose — anche in anticipo rispetto all'orario.
    static func cancelSlot(treatmentId: String, dayOffset: Int, slotIndex: Int) {
        let reqId = notificationId(for: treatmentId, dayOffset: dayOffset, slotIndex: slotIndex)
        let center = UNUserNotificationCenter.current()
        // Rimuove se non ancora scattata
        center.removePendingNotificationRequests(withIdentifiers: [reqId])
        // Rimuove se già mostrata nel notification center
        center.removeDeliveredNotifications(withIdentifiers: [reqId])
        log.info("cancelSlot: removed id=\(reqId)")
    }
    
    // MARK: - Privato: pianifica una singola finestra
    
    private static func scheduleWindow(
        treatment:   KBTreatment,
        childName:   String,
        windowStart: Date,
        careEnd:     Date?
    ) {
        let center = UNUserNotificationCenter.current()
        let cal    = Calendar.current
        // Fine della finestra = min(windowStart + windowDays, careEnd)
        var windowEndCandidate = cal.date(byAdding: .day, value: windowDays - 1, to: windowStart)!
        if let end = careEnd {
            windowEndCandidate = min(windowEndCandidate, end)
        }
        let windowEnd = windowEndCandidate
        
        // Itera i giorni della finestra
        var currentDay = windowStart
        var lastRequest: UNNotificationRequest? = nil
        
        while currentDay <= windowEnd {
            let dayOffset = cal.dateComponents([.day], from: cal.startOfDay(for: treatment.startDate), to: currentDay).day ?? 0
            
            for (slotIdx, timeStr) in treatment.scheduleTimes.enumerated() {
                let parts = timeStr.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                
                var dc       = cal.dateComponents([.year, .month, .day], from: currentDay)
                dc.hour      = parts[0]
                dc.minute    = parts[1]
                dc.second    = 0
                
                guard let fire = cal.date(from: dc), fire > Date() else { continue }
                
                let content                    = UNMutableNotificationContent()
                content.title                  = "💊 \(treatment.drugName)"
                let fascia = schedulePeriodLabel(timeStr, slotIndexFallback: slotIdx)
                content.body                   = "\(fascia) · \(treatment.dosageValue.formatted()) \(treatment.dosageUnit) per \(childName)"
                content.sound                  = .default
                content.categoryIdentifier     = TreatmentNotificationCategory.identifier
                content.userInfo               = [
                    "type":        "treatment_reminder",
                    "familyId":    treatment.familyId,
                    "childId":     treatment.childId,
                    "treatmentId": treatment.id,
                    "dayOffset":   dayOffset,
                    "slotIndex":   slotIdx
                ]
                
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                let reqId   = notificationId(for: treatment.id, dayOffset: dayOffset, slotIndex: slotIdx)
                let request = UNNotificationRequest(identifier: reqId, content: content, trigger: trigger)
                
                center.add(request) { err in
                    if let err { log.error("schedule failed id=\(reqId): \(err.localizedDescription)") }
                }
                
                lastRequest = request
            }
            
            currentDay = cal.date(byAdding: .day, value: 1, to: currentDay)!
        }
        
        // ── Sentinella ────────────────────────────────────────────────────────
        // Notifica silenziosa che, quando scatta, triggera rescheduleIfNeeded()
        // dal delegate. Deve avere contenuto non vuoto per essere consegnata
        // in modo affidabile da iOS (anche in DND / Low Power Mode).
        if let last = lastRequest,
           let lastTrigger = last.trigger as? UNCalendarNotificationTrigger,
           let lastFire    = cal.date(from: lastTrigger.dateComponents) {
            
            // La sentinella scatta 1 minuto dopo l'ultimo slot pianificato
            let sentinelFire = lastFire.addingTimeInterval(60)
            guard sentinelFire > Date() else { return }
            
            let sentinelContent                = UNMutableNotificationContent()
            // Titolo e body non vuoti: iOS garantisce la consegna anche in background.
            // La categoria "silent" può essere configurata per non mostrare banner.
            // Se non vuoi che l'utente la veda, usa interruptionLevel = .passive
            sentinelContent.title              = " "   // spazio — non vuoto ma invisibile
            sentinelContent.body               = " "
            sentinelContent.sound              = nil   // nessun suono
            if #available(iOS 15.0, *) {
                sentinelContent.interruptionLevel = .passive  // nessun banner, nessun suono
            }
            sentinelContent.userInfo           = [
                "type":        "treatment_reschedule_sentinel",
                "treatmentId": treatment.id,
                "familyId":    treatment.familyId,
                "childId":     treatment.childId
            ]
            
            let sentinelDc      = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: sentinelFire)
            let sentinelTrigger = UNCalendarNotificationTrigger(dateMatching: sentinelDc, repeats: false)
            let sentinelId      = notificationPrefix(for: treatment.id) + "sentinel"
            let sentinelReq     = UNNotificationRequest(identifier: sentinelId, content: sentinelContent, trigger: sentinelTrigger)
            
            center.add(sentinelReq) { err in
                if let err { log.error("sentinel schedule failed: \(err.localizedDescription)") }
                else       { log.info("sentinel scheduled at \(sentinelFire) for treatment=\(treatment.id)") }
            }
        }
        
        log.info("scheduleWindow: treatment=\(treatment.id) from=\(windowStart) to=\(windowEnd)")
    }
    
    // MARK: - Identifier helpers
    
    static func notificationPrefix(for treatmentId: String) -> String {
        "treatment-\(treatmentId)-"
    }
    
    static func notificationId(for treatmentId: String, dayOffset: Int, slotIndex: Int) -> String {
        "treatment-\(treatmentId)-d\(dayOffset)-s\(slotIndex)"
    }
}

// MARK: - Double formatting helper

private extension Double {
    func formatted() -> String {
        truncatingRemainder(dividingBy: 1) == 0
        ? String(format: "%.0f", self)
        : String(format: "%.1f", self)
    }
}
