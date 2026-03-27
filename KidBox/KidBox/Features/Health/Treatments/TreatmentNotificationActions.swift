//
//  TreatmentNotificationActions.swift
//  KidBox
//

import UserNotifications
import SwiftData
import FirebaseAuth
import OSLog

// MARK: - Notification.Name

extension Notification.Name {
    /// Postata dopo ogni quick action dose (Assunto / Saltato).
    static let treatmentDoseQuickAction = Notification.Name("kb.treatmentDoseQuickAction")
}

// MARK: - Payload keys

enum TreatmentDoseQuickActionKey {
    static let treatmentId = "treatmentId"
    static let dayOffset   = "dayOffset"
    static let slotIndex   = "slotIndex"
    static let taken       = "taken"
}

// MARK: - Category identifiers

enum TreatmentNotificationCategory {
    static let identifier      = "TREATMENT_DOSE_REMINDER"
    static let actionTaken     = "TREATMENT_DOSE_TAKEN"
    static let actionSkipped   = "TREATMENT_DOSE_SKIPPED"
    static let actionSnooze    = "TREATMENT_DOSE_SNOOZE"
}

// MARK: - Registration

extension TreatmentNotificationCategory {
    
    /// Registra la categoria con le tre azioni rapide.
    /// Chiamare una volta sola in AppDelegate.didFinishLaunching.
    static func register() {
        let taken = UNNotificationAction(
            identifier: actionTaken,
            title: "✅ Assunto",
            options: []
        )
        let skipped = UNNotificationAction(
            identifier: actionSkipped,
            title: "⏭ Saltato",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: actionSnooze,
            title: "⏰ Ricordamelo tra 10 min",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: identifier,
            actions: [taken, skipped, snooze],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        Logger(subsystem: "it.vittorioscocca.kidbox", category: "Notifications")
            .info("TreatmentNotificationCategory registered")
    }
}

// MARK: - Quick-action handler

@MainActor
enum TreatmentDoseActionHandler {
    
    /// Gestisce Assunto / Saltato / Snooze dalla notifica.
    /// - Returns: true se è una quick action (non un tap normale).
    @discardableResult
    static func handle(
        response:     UNNotificationResponse,
        modelContext: ModelContext
    ) -> Bool {
        let actionId = response.actionIdentifier
        guard actionId == TreatmentNotificationCategory.actionTaken  ||
                actionId == TreatmentNotificationCategory.actionSkipped ||
                actionId == TreatmentNotificationCategory.actionSnooze
        else { return false }
        
        let userInfo = response.notification.request.content.userInfo
        guard
            let treatmentId = userInfo["treatmentId"] as? String,
            let familyId    = userInfo["familyId"]    as? String,
            let dayOffset   = (userInfo["dayOffset"] as? NSNumber)?.intValue,
            let slotIndex   = (userInfo["slotIndex"] as? NSNumber)?.intValue
        else {
            Logger(subsystem: "it.vittorioscocca.kidbox", category: "Notifications")
                .error("TreatmentDoseActionHandler: missing userInfo keys")
            return false
        }
        
        // Snooze: rischedula tra 10 minuti, non registra la dose
        if actionId == TreatmentNotificationCategory.actionSnooze {
            scheduleSnooze(
                original: response.notification.request.content,
                treatmentId: treatmentId,
                familyId: familyId,
                dayOffset: dayOffset,
                slotIndex: slotIndex
            )
            return true
        }
        
        // Assunto / Saltato: registra la dose
        let taken = (actionId == TreatmentNotificationCategory.actionTaken)
        
        recordDose(
            treatmentId:  treatmentId,
            familyId:     familyId,
            dayOffset:    dayOffset,
            slotIndex:    slotIndex,
            taken:        taken,
            modelContext: modelContext
        )
        
        NotificationCenter.default.post(
            name: .treatmentDoseQuickAction,
            object: nil,
            userInfo: [
                TreatmentDoseQuickActionKey.treatmentId: treatmentId,
                TreatmentDoseQuickActionKey.dayOffset:   dayOffset,
                TreatmentDoseQuickActionKey.slotIndex:   slotIndex,
                TreatmentDoseQuickActionKey.taken:       taken
            ]
        )
        
        return true
    }
    
    // MARK: - Snooze
    
    private static func scheduleSnooze(
        original:    UNNotificationContent,
        treatmentId: String,
        familyId:    String,
        dayOffset:   Int,
        slotIndex:   Int
    ) {
        let log = Logger(subsystem: "it.vittorioscocca.kidbox", category: "Notifications")
        
        let content = UNMutableNotificationContent()
        content.title              = original.title
        content.body               = original.body
        content.sound              = .default
        content.categoryIdentifier = TreatmentNotificationCategory.identifier
        content.userInfo           = original.userInfo
        
        // Scatta tra 10 minuti
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 10 * 60,
            repeats: false
        )
        
        let requestId = "treatment-snooze-\(treatmentId)-d\(dayOffset)-s\(slotIndex)-\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(
            identifier: requestId,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                log.error("TreatmentDoseActionHandler: snooze failed \(error.localizedDescription)")
            } else {
                log.info("TreatmentDoseActionHandler: snooze scheduled in 10min treatmentId=\(treatmentId)")
            }
        }
    }
    
    // MARK: - Persistence
    
    private static func recordDose(
        treatmentId:  String,
        familyId:     String,
        dayOffset:    Int,
        slotIndex:    Int,
        taken:        Bool,
        modelContext: ModelContext
    ) {
        let log = Logger(subsystem: "it.vittorioscocca.kidbox", category: "Notifications")
        let uid = Auth.auth().currentUser?.uid ?? "quick-action"
        let now = Date()
        
        let treatDesc = FetchDescriptor<KBTreatment>(
            predicate: #Predicate { $0.id == treatmentId }
        )
        guard let treatment = try? modelContext.fetch(treatDesc).first else {
            log.error("TreatmentDoseActionHandler: treatment not found id=\(treatmentId)")
            return
        }
        
        let logDesc = FetchDescriptor<KBDoseLog>(
            predicate: #Predicate {
                $0.treatmentId == treatmentId &&
                $0.dayNumber   == dayOffset + 1 &&
                $0.slotIndex   == slotIndex
            }
        )
        
        let existingLog = try? modelContext.fetch(logDesc).first
        
        if let existing = existingLog {
            existing.taken     = taken
            existing.takenAt   = taken ? now : nil
            existing.updatedAt = now
            existing.updatedBy = uid
            existing.syncState = .pendingUpsert
        } else {
            let scheduledTime = treatment.scheduleTimes[safe: slotIndex] ?? "00:00"
            let newLog = KBDoseLog(
                familyId:      familyId,
                childId:       treatment.childId,
                treatmentId:   treatmentId,
                dayNumber:     dayOffset + 1,
                slotIndex:     slotIndex,
                scheduledTime: scheduledTime,
                takenAt:       taken ? now : nil,
                taken:         taken,
                updatedAt:     now,
                updatedBy:     uid
            )
            modelContext.insert(newLog)
        }
        
        do {
            try modelContext.save()
            let saved = (try? modelContext.fetch(logDesc))?.first ?? existingLog
            if let logId = saved?.id {
                SyncCenter.shared.enqueueDoseLogUpsert(
                    logId:        logId,
                    familyId:     familyId,
                    modelContext: modelContext
                )
            }
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            log.info("TreatmentDoseActionHandler: saved taken=\(taken) treatmentId=\(treatmentId) day=\(dayOffset) slot=\(slotIndex)")
        } catch {
            log.error("TreatmentDoseActionHandler: save failed \(error.localizedDescription)")
        }
    }
}
