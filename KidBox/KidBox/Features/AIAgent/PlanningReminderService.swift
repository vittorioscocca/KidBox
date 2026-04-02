//
//  PlanningReminderService.swift
//  KidBox
//
//  Created by vscocca on 24/03/26.
//
//  FIX (02/04/26):
//  - TodoReminderService.schedule ora richiede listId, familyId, childId
//    → aggiornate le chiamate nei case existingTodo e freeText.
//  - prescribedExam: rimossa logica "giorno prima" — KBExamReminderService
//    ora schedula nella data dell'esame (allineato al fix del 02/04/26).
//

import Foundation
import UserNotifications
import SwiftData
import FirebaseAuth

// MARK: - Request types

/// Richiesta di reminder originata dall'agente AI.
enum PlanningReminderRequest {
    
    /// Attiva il reminder su un to-do già esistente.
    case existingTodo(todo: KBTodoItem, dueAt: Date)
    
    /// Attiva il reminder per la nextVisitDate di una visita.
    case nextVisit(visit: KBMedicalVisit, childName: String)
    
    /// Attiva il reminder per un esame prescritto con deadline.
    case prescribedExam(
        examName:  String,
        examId:    String,
        childName: String,
        familyId:  String,
        childId:   String,
        deadline:  Date
    )
    
    /// Attiva i reminder di dose per una cura attiva.
    case treatment(treatment: KBTreatment, childName: String)
    
    /// Crea un to-do libero con reminder (proposto dall'agente da zero).
    case freeText(
        title:    String,
        dueAt:    Date,
        familyId: String,
        childId:  String,
        listId:   String?
    )
}

// MARK: - Result

enum PlanningReminderResult {
    case scheduled(description: String)
    case notAuthorized
    case failed(Error)
}

// MARK: - Service

@MainActor
enum PlanningReminderService {
    
    // MARK: - Main entry point
    
    /// Schedula il reminder descritto dalla `request`.
    /// Restituisce sempre un `PlanningReminderResult` — non lancia.
    static func schedule(
        request:      PlanningReminderRequest,
        modelContext: ModelContext
    ) async -> PlanningReminderResult {
        
        // Verifica permessi prima di qualsiasi operazione
        let granted = await ensurePermission()
        guard granted else {
            KBLog.ai.kbInfo("PlanningReminderService: notifications not authorized")
            return .notAuthorized
        }
        
        switch request {
            
            // ── 1. To-do esistente ────────────────────────────────────────────
        case .existingTodo(let todo, let dueAt):
            return await scheduleExistingTodo(todo: todo, dueAt: dueAt, modelContext: modelContext)
            
            // ── 2. Visita di controllo ────────────────────────────────────────
        case .nextVisit(let visit, let childName):
            return scheduleNextVisit(visit: visit, childName: childName, modelContext: modelContext)
            
            // ── 3. Esame prescritto ───────────────────────────────────────────
        case .prescribedExam(let name, let examId, let childName, let familyId, let childId, let deadline):
            return schedulePrescribedExam(
                examName:  name,
                examId:    examId,
                childName: childName,
                familyId:  familyId,
                childId:   childId,
                deadline:  deadline
            )
            
            // ── 4. Cura attiva ────────────────────────────────────────────────
        case .treatment(let treatment, let childName):
            return scheduleTreatment(treatment: treatment, childName: childName, modelContext: modelContext)
            
            // ── 5. Reminder libero (crea to-do) ──────────────────────────────
        case .freeText(let title, let dueAt, let familyId, let childId, let listId):
            return await scheduleFreeText(
                title:        title,
                dueAt:        dueAt,
                familyId:     familyId,
                childId:      childId,
                listId:       listId,
                modelContext: modelContext
            )
        }
    }
    
    // MARK: - Permission check
    
    private static func ensurePermission() async -> Bool {
        let center   = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }
    
    // MARK: - Case 1: existing todo
    
    private static func scheduleExistingTodo(
        todo:         KBTodoItem,
        dueAt:        Date,
        modelContext: ModelContext
    ) async -> PlanningReminderResult {
        
        // Cancella eventuali reminder precedenti
        if let existing = todo.reminderId {
            TodoReminderService.cancel(reminderId: existing)
        }
        
        do {
            // FIX: aggiornata firma con listId, familyId, childId
            let reminderId = try await TodoReminderService.schedule(
                todoId:   todo.id,
                listId:   todo.listId ?? "",
                familyId: todo.familyId,
                childId:  todo.childId,
                title:    todo.title,
                dueAt:    dueAt
            )
            
            todo.dueAt           = dueAt
            todo.reminderEnabled = true
            todo.reminderId      = reminderId
            todo.updatedAt       = Date()
            todo.updatedBy       = Auth.auth().currentUser?.uid ?? "ai-agent"
            todo.syncState       = .pendingUpsert
            
            try? modelContext.save()
            SyncCenter.shared.enqueueTodoUpsert(todoId: todo.id, familyId: todo.familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            
            KBLog.ai.kbInfo("PlanningReminderService: todo reminder set todoId=\(todo.id) dueAt=\(dueAt)")
            return .scheduled(description: "Promemoria impostato per \"\(todo.title)\" — \(formatDateTime(dueAt))")
            
        } catch {
            KBLog.ai.kbError("PlanningReminderService: todo reminder failed: \(error)")
            return .failed(error)
        }
    }
    
    // MARK: - Case 2: next visit
    
    private static func scheduleNextVisit(
        visit:        KBMedicalVisit,
        childName:    String,
        modelContext: ModelContext
    ) -> PlanningReminderResult {
        
        guard let nextDate = visit.nextVisitDate else {
            return .failed(PlanningReminderError.missingDate)
        }
        
        KBVisitReminderService.shared.scheduleNextVisitReminder(
            visitId:   visit.id,
            date:      nextDate,
            reason:    visit.nextVisitReason ?? visit.reason,
            childName: childName,
            familyId:  visit.familyId,
            childId:   visit.childId
        ) { success in
            if success {
                KBLog.ai.kbInfo("PlanningReminderService: next visit reminder set visitId=\(visit.id)")
            }
        }
        
        visit.nextVisitReminderOn = true
        visit.updatedAt           = Date()
        visit.updatedBy           = Auth.auth().currentUser?.uid ?? "ai-agent"
        visit.syncState           = .pendingUpsert
        
        try? modelContext.save()
        SyncCenter.shared.enqueueVisitUpsert(visitId: visit.id, familyId: visit.familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        return .scheduled(description: "Promemoria visita impostato per il \(formatDate(nextDate))")
    }
    
    // MARK: - Case 3: prescribed exam
    
    private static func schedulePrescribedExam(
        examName:  String,
        examId:    String,
        childName: String,
        familyId:  String,
        childId:   String,
        deadline:  Date
    ) -> PlanningReminderResult {
        
        // FIX: schedula nella data della deadline (non più il giorno prima).
        // KBExamReminderService ora gestisce data + orario scelto dall'utente
        // o 08:00 di default — allineato al fix del 02/04/26.
        KBExamReminderService.shared.schedule(
            examId:    examId,
            examName:  examName,
            childName: childName,
            familyId:  familyId,
            childId:   childId,
            date:      deadline
        ) { success in
            KBLog.ai.kbInfo("PlanningReminderService: exam reminder result=\(success) examId=\(examId)")
        }
        
        return .scheduled(description: "Promemoria esame \"\(examName)\" il \(formatDate(deadline))")
    }
    
    // MARK: - Case 4: treatment
    
    private static func scheduleTreatment(
        treatment:    KBTreatment,
        childName:    String,
        modelContext: ModelContext
    ) -> PlanningReminderResult {
        
        treatment.reminderEnabled = true
        treatment.updatedAt       = Date()
        treatment.updatedBy       = Auth.auth().currentUser?.uid ?? "ai-agent"
        treatment.syncState       = .pendingUpsert
        
        TreatmentNotificationManager.schedule(treatment: treatment, childName: childName)
        
        try? modelContext.save()
        SyncCenter.shared.enqueueTreatmentUpsert(
            treatmentId: treatment.id,
            familyId:    treatment.familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        KBLog.ai.kbInfo("PlanningReminderService: treatment reminders set treatmentId=\(treatment.id)")
        return .scheduled(description: "Promemoria attivati per \(treatment.drugName) — \(treatment.scheduleTimes.joined(separator: ", "))")
    }
    
    // MARK: - Case 5: free text (crea to-do + reminder)
    
    private static func scheduleFreeText(
        title:        String,
        dueAt:        Date,
        familyId:     String,
        childId:      String,
        listId:       String?,
        modelContext: ModelContext
    ) async -> PlanningReminderResult {
        
        let uid = Auth.auth().currentUser?.uid ?? "ai-agent"
        let now = Date()
        
        // Crea il to-do
        let todo = KBTodoItem(
            familyId:  familyId,
            childId:   childId,
            title:     title,
            listId:    listId,
            dueAt:     dueAt,
            isDone:    false,
            updatedBy: uid,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        todo.createdBy   = uid
        todo.priorityRaw = 0
        todo.syncState   = .pendingUpsert
        
        modelContext.insert(todo)
        
        // Schedula il reminder
        // FIX: aggiornata firma con listId, familyId, childId
        do {
            let reminderId = try await TodoReminderService.schedule(
                todoId:   todo.id,
                listId:   listId ?? "",
                familyId: familyId,
                childId:  childId,
                title:    title,
                dueAt:    dueAt
            )
            todo.reminderEnabled = true
            todo.reminderId      = reminderId
        } catch {
            // To-do creato comunque, solo senza reminder
            KBLog.ai.kbError("PlanningReminderService: free text reminder failed: \(error)")
        }
        
        try? modelContext.save()
        SyncCenter.shared.enqueueTodoUpsert(todoId: todo.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        KBLog.ai.kbInfo("PlanningReminderService: free text todo+reminder created todoId=\(todo.id)")
        return .scheduled(description: "Promemoria creato: \"\(title)\" — \(formatDateTime(dueAt))")
    }
    
    // MARK: - Cancel
    
    /// Cancella il reminder associato a un to-do.
    static func cancelTodoReminder(_ todo: KBTodoItem, modelContext: ModelContext) {
        guard todo.reminderEnabled, let rid = todo.reminderId else { return }
        TodoReminderService.cancel(reminderId: rid)
        todo.reminderEnabled = false
        todo.reminderId      = nil
        todo.syncState       = .pendingUpsert
        try? modelContext.save()
        SyncCenter.shared.enqueueTodoUpsert(todoId: todo.id, familyId: todo.familyId, modelContext: modelContext)
        KBLog.ai.kbInfo("PlanningReminderService: todo reminder cancelled todoId=\(todo.id)")
    }
    
    // MARK: - Formatting helpers
    
    private static func formatDate(_ date: Date) -> String {
        let f        = DateFormatter()
        f.locale     = Locale(identifier: "it_IT")
        f.dateStyle  = .long
        f.timeStyle  = .none
        return f.string(from: date)
    }
    
    private static func formatDateTime(_ date: Date) -> String {
        let f        = DateFormatter()
        f.locale     = Locale(identifier: "it_IT")
        f.dateStyle  = .medium
        f.timeStyle  = .short
        return f.string(from: date)
    }
}

// MARK: - Errors

enum PlanningReminderError: LocalizedError {
    case missingDate
    case notAuthorized
    
    var errorDescription: String? {
        switch self {
        case .missingDate:   return "Nessuna data disponibile per il promemoria."
        case .notAuthorized: return "Notifiche non autorizzate. Vai in Impostazioni per abilitarle."
        }
    }
}
