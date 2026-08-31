//
//  TreatmentNotificationManager.swift
//  KidBox
//

import Foundation
import SwiftData
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
        KBDeviceReminderLedger.record(KBDeviceReminderLedger.treatment(treatment.id))
        
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
    
    /// Avanza la finestra di tutte le cure attive (o di una sola, se `treatmentId`
    /// è valorizzato), risolvendo il nome del bambino o dell'animale.
    ///
    /// iOS non può ripianificare da solo mentre l'app è chiusa: questo è il punto
    /// unico da cui la finestra avanza, richiamato al rientro in app e al tap su
    /// una notifica dose.
    @MainActor
    static func rescheduleActiveTreatments(context: ModelContext, treatmentId: String? = nil) {
        let descriptor = FetchDescriptor<KBTreatment>(
            predicate: #Predicate {
                $0.reminderEnabled == true &&
                $0.isActive        == true &&
                $0.isDeleted       == false
            }
        )
        guard let treatments = try? context.fetch(descriptor) else { return }
        // Solo le cure già armate su questo device: il refresh rinnova, non crea.
        // Una cura arrivata dal sync non deve iniziare ad avvisare qui.
        for treatment in treatments
        where (treatmentId == nil || treatment.id == treatmentId)
            && KBDeviceReminderLedger.contains(KBDeviceReminderLedger.treatment(treatment.id)) {
            rescheduleIfNeeded(treatment: treatment, childName: displayName(for: treatment, context: context))
        }
    }

    @MainActor
    private static func displayName(for treatment: KBTreatment, context: ModelContext) -> String {
        if treatment.petId.isEmpty {
            let childId = treatment.childId
            let descriptor = FetchDescriptor<KBChild>(predicate: #Predicate { $0.id == childId })
            return (try? context.fetch(descriptor).first?.name) ?? ""
        }
        let petId = treatment.petId
        let descriptor = FetchDescriptor<KBPet>(predicate: #Predicate { $0.id == petId })
        return ((try? context.fetch(descriptor).first?.name) ?? nil) ?? String(localized: "Animale domestico")
    }

    // MARK: - Cancella
    
    /// Rimuove tutte le notifiche (normali + sentinella) di questa cura.
    static func cancel(treatmentId: String) {
        KBDeviceReminderLedger.forget(KBDeviceReminderLedger.treatment(treatmentId))
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
        let cal = Calendar.current
        // Fine della finestra = min(windowStart + windowDays, careEnd)
        var windowEndCandidate = cal.date(byAdding: .day, value: windowDays - 1, to: windowStart)!
        if let end = careEnd {
            windowEndCandidate = min(windowEndCandidate, end)
        }
        let windowEnd = windowEndCandidate
        
        // Itera i giorni della finestra
        var currentDay = windowStart
        // Le richieste si accumulano e partono in un solo lotto: il budget vede
        // la finestra intera e sacrifica la coda, invece di scartare a caso.
        var requests: [UNNotificationRequest] = []
        
        while currentDay <= windowEnd {
            let dayOffset = cal.dateComponents([.day], from: cal.startOfDay(for: treatment.startDate), to: currentDay).day ?? 0

            if treatment.intervalBetweenDosesDays > 0 {
                let n = treatment.intervalBetweenDosesDays
                guard dayOffset >= 0, dayOffset % n == 0 else {
                    currentDay = cal.date(byAdding: .day, value: 1, to: currentDay)!
                    continue
                }
                guard let timeStr = treatment.scheduleTimes.first else {
                    currentDay = cal.date(byAdding: .day, value: 1, to: currentDay)!
                    continue
                }
                let slotIdx = 0
                let parts = timeStr.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else {
                    currentDay = cal.date(byAdding: .day, value: 1, to: currentDay)!
                    continue
                }

                var dc = cal.dateComponents([.year, .month, .day], from: currentDay)
                dc.hour = parts[0]
                dc.minute = parts[1]
                dc.second = 0

                guard let fire = cal.date(from: dc), fire > Date() else {
                    currentDay = cal.date(byAdding: .day, value: 1, to: currentDay)!
                    continue
                }

                let content = UNMutableNotificationContent()
                let fascia = schedulePeriodLabelArg(timeStr, slotIndexFallback: slotIdx)
                let dose = "\(treatment.dosageValue.formatted()) \(treatment.dosageUnit)"
                content.sound = .default
                content.categoryIdentifier = TreatmentNotificationCategory.identifier
                content.userInfo = [
                    "type": "treatment_reminder",
                    "familyId": treatment.familyId,
                    "childId": treatment.childId,
                    "treatmentId": treatment.id,
                    "dayOffset": dayOffset,
                    "slotIndex": slotIdx,
                ]
                KBNotificationLocalization.setText(
                    on: content,
                    titleKey: "💊 %@",
                    titleArgs: [.text(treatment.drugName)],
                    bodyKey: "%@ · %@",
                    bodyArgs: [fascia, .text(dose)]
                )

                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                let reqId = notificationId(for: treatment.id, dayOffset: dayOffset, slotIndex: slotIdx)
                let request = UNNotificationRequest(identifier: reqId, content: content, trigger: trigger)

                requests.append(request)

                currentDay = cal.date(byAdding: .day, value: 1, to: currentDay)!
                continue
            }

            for (slotIdx, timeStr) in treatment.scheduleTimes.enumerated() {
                let parts = timeStr.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                
                var dc       = cal.dateComponents([.year, .month, .day], from: currentDay)
                dc.hour      = parts[0]
                dc.minute    = parts[1]
                dc.second    = 0
                
                guard let fire = cal.date(from: dc), fire > Date() else { continue }
                
                let content                    = UNMutableNotificationContent()
                let fascia = schedulePeriodLabelArg(timeStr, slotIndexFallback: slotIdx)
                let dose = "\(treatment.dosageValue.formatted()) \(treatment.dosageUnit)"
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
                KBNotificationLocalization.setText(
                    on: content,
                    titleKey: "💊 %@",
                    titleArgs: [.text(treatment.drugName)],
                    bodyKey: "%@ · %@",
                    bodyArgs: [fascia, .text(dose)]
                )
                
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                let reqId   = notificationId(for: treatment.id, dayOffset: dayOffset, slotIndex: slotIdx)
                let request = UNNotificationRequest(identifier: reqId, content: content, trigger: trigger)
                
                requests.append(request)
            }
            
            currentDay = cal.date(byAdding: .day, value: 1, to: currentDay)!
        }
        
        // Nessuna sentinella: una notifica locale `.passive` non risveglia l'app.
        // `didReceive` scatta solo se l'utente tocca la notifica e `willPresent`
        // solo se l'app è già in primo piano, quindi una sentinella silenziosa non
        // può ripianificare nulla — occupava uno dei 64 slot senza fare il suo
        // lavoro. La finestra ora avanza da `KidBoxApp` a ogni rientro in app e
        // dal tap su una notifica dose (vedi AppDelegate).

        let batch = requests
        let treatmentId = treatment.id
        Task {
            let accepted = await KBLocalNotificationBudget.shared.add(batch, priority: .critical)
            log.info("scheduleWindow: treatment=\(treatmentId) pianificate \(accepted)/\(batch.count)")
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
