//
//  WeeklySummaryService.swift
//  KidBox
//
//  Created by vscocca on 24/03/26.
//

//
//  WeeklySummaryService.swift
//  KidBox
//
//  Genera automaticamente una sintesi settimanale della famiglia usando l'AI
//  e la recapita come notifica locale ogni lunedì mattina alle 08:00.
//
//  Flusso:
//  1. `scheduleWeeklyIfNeeded()` — chiamato all'avvio e quando l'app
//     torna in foreground. Controlla se la sintesi è già stata generata
//     questa settimana (chiave UserDefaults "kb_weeklySummary_lastISOWeek").
//  2. Se mancante, genera il recap chiamando AIService (stessa Cloud
//     Function `askAI` usata dal chat).
//  3. Salva il testo in UserDefaults e schedula una UNNotification
//     locale per lunedì alle 08:00 (se non già schedulata).
//  4. Al tap della notifica, AppDelegate chiama
//     `NotificationManager.shared.setDeepLink(.askExpert)` che apre
//     la PlanningAIChatView con il recap come primo messaggio.
//
//  Note:
//  - Il service non usa SwiftData direttamente: riceve i dati già
//    fetchati da chi lo chiama (tipicamente RootHostView in onAppear).
//  - Non consuma quota AI se la sintesi di questa settimana esiste già.
//  - Preferenza utente: `kb_weeklySummaryEnabled` (Bool, default true).
//

import Foundation
import UserNotifications
import SwiftData
import FirebaseAuth

// MARK: - WeeklySummaryService

@MainActor
final class WeeklySummaryService {
    
    // MARK: - Singleton
    
    static let shared = WeeklySummaryService()
    private init() {}
    
    // MARK: - UserDefaults keys
    
    private enum Keys {
        static let lastISOWeek  = "kb_weeklySummary_lastISOWeek"
        static let lastText     = "kb_weeklySummary_lastText"
        static let enabled      = "kb_weeklySummaryEnabled"
        static let notifId      = "kb_weeklySummary_notifId"
    }
    
    // MARK: - Public API
    
    /// Chiama all'avvio e quando l'app torna in foreground.
    /// Genera la sintesi solo se quella di questa settimana manca ancora.
    /// - Parameter forcedFamilyId: se valorizzato (es. da `RootHostView`), usato per caricare gli allegati life-area anche con `input` minimale.
    func scheduleWeeklyIfNeeded(
        input:        PlanningContextInput,
        familyName:   String,
        modelContext: ModelContext,
        forcedFamilyId: String? = nil
    ) async {
        guard isEnabled else {
            KBLog.ai.kbDebug("WeeklySummaryService: disabled by user preference")
            return
        }
        guard AISettings.shared.isEnabled else {
            KBLog.ai.kbDebug("WeeklySummaryService: AI globally disabled")
            return
        }
        
        let currentWeek = isoWeekKey()
        let lastWeek    = UserDefaults.standard.string(forKey: Keys.lastISOWeek) ?? ""
        
        guard currentWeek != lastWeek else {
            KBLog.ai.kbDebug("WeeklySummaryService: summary already generated for week \(currentWeek)")
            // Assicura che la notifica locale sia schedulata anche se il testo esiste già
            if let text = UserDefaults.standard.string(forKey: Keys.lastText) {
                await scheduleLocalNotification(summaryText: text, familyName: familyName)
            }
            return
        }
        
        KBLog.ai.kbInfo("WeeklySummaryService: generating summary for week \(currentWeek)")
        let enrichedInput = await enrichInputWithLifeAreaDocuments(
            forcedFamilyId: forcedFamilyId,
            base: input,
            modelContext: modelContext
        )
        await generateAndSchedule(input: enrichedInput, familyName: familyName, weekKey: currentWeek)
    }
    
    /// Restituisce la sintesi dell'ultima settimana se disponibile.
    var lastSummaryText: String? {
        UserDefaults.standard.string(forKey: Keys.lastText)
    }
    
    /// Preferenza utente per abilitare/disabilitare la sintesi settimanale.
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.enabled) }
    }
    
    // MARK: - Life-area documents (Casa / Garage / Animali)
    
    /// Aggiunge allegati life-area con OCR completato al contesto del recap settimanale
    /// (stessi tag di `OCRRecoveryMigration` / planning AI).
    private func enrichInputWithLifeAreaDocuments(
        forcedFamilyId: String?,
        base: PlanningContextInput,
        modelContext: ModelContext
    ) async -> PlanningContextInput {
        let trimmed = forcedFamilyId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let familyId = !trimmed.isEmpty ? trimmed : Self.resolveFamilyId(from: base)
        guard !familyId.isEmpty else { return base }
        do {
            let fid = familyId
            let desc = FetchDescriptor<KBDocument>(
                predicate: #Predicate { doc in
                    doc.familyId == fid && doc.isDeleted == false
                }
            )
            let rows = try modelContext.fetch(desc)
            let lifeTagged = rows.filter { Self.isLifeAreaTaggedDocument($0) }
            Self.enqueuePendingLifeAreaExtractions(documents: lifeTagged, modelContext: modelContext)
            let completed = lifeTagged.filter { $0.extractionStatus == .completed && $0.hasExtractedText }
            guard !completed.isEmpty else { return base }
            var byId = Dictionary(uniqueKeysWithValues: base.lifeAreaDocuments.map { ($0.id, $0) })
            for d in completed { byId[d.id] = d }
            return base.withLifeAreaDocuments(Array(byId.values).sorted { $0.updatedAt > $1.updatedAt })
        } catch {
            KBLog.ai.kbError("WeeklySummaryService: enrich life-area docs failed \(error.localizedDescription)")
            return base
        }
    }
    
    private static func resolveFamilyId(from input: PlanningContextInput) -> String {
        if let id = input.children.first?.familyId, !id.isEmpty { return id }
        if let id = input.pets.first?.familyId, !id.isEmpty { return id }
        if let id = input.homeItems.first?.familyId, !id.isEmpty { return id }
        if let id = input.housePayments.first?.familyId, !id.isEmpty { return id }
        if let id = input.vehicles.first?.familyId, !id.isEmpty { return id }
        if let id = input.calendarEvents.first?.familyId, !id.isEmpty { return id }
        return ""
    }
    
    private static func isLifeAreaTaggedDocument(_ document: KBDocument) -> Bool {
        let tag = document.notes?.lowercased() ?? ""
        return tag.hasPrefix("homeitem:")
            || tag.hasPrefix("housepayment:")
            || tag.hasPrefix("vehicle:")
            || tag.hasPrefix("vehicleevent:")
            || tag.hasPrefix("petevent:")
    }
    
    private static func enqueuePendingLifeAreaExtractions(
        documents: [KBDocument],
        modelContext: ModelContext
    ) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        for doc in documents {
            guard !doc.isDeleted else { continue }
            let empty = doc.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            let needsWork = empty || doc.extractionStatus == .none || doc.extractionStatus == .pending
                || doc.extractionStatus == .processing || doc.extractionStatus == .failed
            guard needsWork else { continue }
            guard doc.localFileURL != nil else { continue }
            DocumentTextExtractionCoordinator.shared.enqueueExtraction(
                for: doc,
                updatedBy: uid,
                modelContext: modelContext
            )
        }
    }
    
    private static let weeklyLifeDocMaxCharsPerFile = 6_000
    
    private static func sanitizeWeeklyExtractedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
    
    private static func clippedWeeklyLifeExtract(from doc: KBDocument) -> String? {
        guard let raw = doc.extractedText else { return nil }
        let sanitized = sanitizeWeeklyExtractedText(raw)
        guard !sanitized.isEmpty else { return nil }
        if sanitized.count <= weeklyLifeDocMaxCharsPerFile { return sanitized }
        let head = String(sanitized.prefix(weeklyLifeDocMaxCharsPerFile))
        return head + "\n[… troncato per recap settimanale …]"
    }
    
    // MARK: - Generation
    
    private func generateAndSchedule(
        input:      PlanningContextInput,
        familyName: String,
        weekKey:    String
    ) async {
        // Costruisce il system prompt della settimana passata
        let systemPrompt = buildWeeklySummaryPrompt(familyName: familyName)
        
        // Costruisce il messaggio utente con tutti i dati della settimana
        let userMessage = buildWeeklyDataMessage(input: input)
        
        let aiMessages = [KBAIMessage(role: .user, content: userMessage)]
        
        do {
            let response = try await AIService.shared.sendMessage(
                messages:     aiMessages,
                systemPrompt: systemPrompt
            )
            
            let text = response.reply
            KBLog.ai.kbInfo("WeeklySummaryService: generated chars=\(text.count)")
            
            // Persiste
            UserDefaults.standard.set(weekKey, forKey: Keys.lastISOWeek)
            UserDefaults.standard.set(text,    forKey: Keys.lastText)
            
            // Schedula notifica
            await scheduleLocalNotification(summaryText: text, familyName: familyName)
            
        } catch {
            KBLog.ai.kbError("WeeklySummaryService: generation failed \(error.localizedDescription)")
        }
    }
    
    // MARK: - System prompt
    
    private func buildWeeklySummaryPrompt(familyName: String) -> String {
        """
        Sei l'assistente AI di KidBox per la famiglia \(familyName).
        Il tuo compito è generare una sintesi settimanale BREVE (max 5 punti bullet)
        basata sui dati della settimana appena trascorsa e della prossima.
        
        REGOLE:
        - Scrivi in italiano, tono caldo e pratico.
        - Max 5 punti bullet (•), ognuno su una riga.
        - Ogni punto max 15 parole.
        - Niente intestazioni, niente markdown, niente emoji eccessive.
        - Evidenzia: scadenze importanti imminenti, cure in corso, eventi chiave, 
          todo urgenti non completati, spese notevoli.
        - Termina con UN suggerimento pratico per la settimana.
        - Se non ci sono dati significativi, scrivi solo: 
          "Settimana tranquilla! Nessuna scadenza urgente in vista."
        """
    }
    
    // MARK: - Data message
    
    private func buildWeeklyDataMessage(input: PlanningContextInput) -> String {
        var lines: [String] = ["Genera la sintesi settimanale basandoti su questi dati:\n"]
        
        // Periodo
        let cal   = Calendar.current
        let now   = Date()
        let fmt   = DateFormatter()
        fmt.locale    = kbDeviceLocale()
        fmt.dateStyle = .long
        fmt.timeStyle = .none
        
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        _   = cal.date(byAdding: .day, value: 6, to: weekStart) ?? now
        let nextEnd   = cal.date(byAdding: .day, value: 13, to: weekStart) ?? now
        lines.append("Settimana: \(fmt.string(from: weekStart)) — \(fmt.string(from: nextEnd))\n")
        
        // Upcoming events
        let events = input.calendarEvents.filter {
            $0.startDate >= weekStart && $0.startDate <= nextEnd && !$0.isDeleted
        }.sorted { $0.startDate < $1.startDate }
        if !events.isEmpty {
            lines.append("EVENTI (\(events.count)):")
            for e in events.prefix(8) {
                lines.append("  • \(fmt.string(from: e.startDate)): \(e.title)")
            }
        }
        
        // Urgent todos
        let urgent = input.openTodos.filter {
            !$0.isDone && !$0.isDeleted &&
            (($0.priorityRaw ?? 0) >= 1 || ($0.dueAt.map { $0 <= nextEnd } ?? false))
        }
        if !urgent.isEmpty {
            lines.append("\nTO-DO URGENTI (\(urgent.count)):")
            for t in urgent.prefix(5) {
                var line = "  • \(t.title)"
                if let due = t.dueAt { line += " (entro \(fmt.string(from: due)))" }
                lines.append(line)
            }
        }
        
        // Treatments
        let treats = input.activeTreatments.filter { !$0.isDeleted && $0.isActive }
        if !treats.isEmpty {
            lines.append("\nCURE ATTIVE (\(treats.count)):")
            for t in treats.prefix(5) {
                let child = input.childNames[t.childId] ?? t.childId
                lines.append("  • \(t.drugName) per \(child) — \(t.scheduleTimes.count) dose/die")
            }
        }
        
        // Health deadlines
        let nextVisits = input.visitsWithNextDate.compactMap { v -> (String, Date)? in
            guard let d = v.nextVisitDate, d <= nextEnd else { return nil }
            let child = input.childNames[v.childId] ?? v.childId
            return (child, d)
        }
        if !nextVisits.isEmpty {
            lines.append("\nVISITE PROGRAMMATE:")
            for (child, date) in nextVisits.prefix(3) {
                lines.append("  • Visita di \(child): \(fmt.string(from: date))")
            }
        }
        
        let pendingExams = input.visitsWithPendingExams.flatMap { v in
            v.prescribedExams.compactMap { pe -> (String, String, Date)? in
                guard let dl = pe.deadline, dl <= nextEnd else { return nil }
                let child = input.childNames[v.childId] ?? v.childId
                return (child, pe.name, dl)
            }
        }
        if !pendingExams.isEmpty {
            lines.append("\nESAMI IN SCADENZA:")
            for (child, name, dl) in pendingExams.prefix(3) {
                lines.append("  • \(name) per \(child): entro \(fmt.string(from: dl))")
            }
        }
        
        // Expenses
        if !input.recentExpenses.isEmpty {
            let total = input.recentExpenses.reduce(0.0) { $0 + $1.amount }
            lines.append("\nSPESE SETTIMANA: €\(String(format: "%.2f", total)) (\(input.recentExpenses.count) voci)")
        }
        
        // Grocery
        if !input.pendingGroceryItems.isEmpty {
            lines.append("\nLISTA SPESA: \(input.pendingGroceryItems.count) articoli da acquistare")
        }
        
        // Allegati Casa / Garage / Animali (testo estratto OCR)
        let lifeDocs = input.lifeAreaDocuments
            .filter { !$0.isDeleted && $0.extractionStatus == .completed && $0.hasExtractedText }
            .sorted { $0.updatedAt > $1.updatedAt }
        if !lifeDocs.isEmpty {
            lines.append("\nALLEGATI CASA / GARAGE / ANIMALI (testo estratto, max 8 file):")
            for doc in lifeDocs.prefix(8) {
                guard let body = Self.clippedWeeklyLifeExtract(from: doc) else { continue }
                lines.append("  — \(doc.title):")
                for row in body.split(separator: "\n", omittingEmptySubsequences: false) {
                    let s = String(row)
                    if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        lines.append("    \(s)")
                    }
                }
            }
        }
        
        lines.append("\nGenera ora la sintesi seguendo le regole del sistema.")
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Local notification
    
    private func scheduleLocalNotification(
        summaryText: String,
        familyName:  String
    ) async {
        let center = UNUserNotificationCenter.current()
        
        // Rimuove eventuale notifica precedente della stessa settimana
        if let oldId = UserDefaults.standard.string(forKey: Keys.notifId) {
            center.removePendingNotificationRequests(withIdentifiers: [oldId])
        }
        
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            KBLog.ai.kbDebug("WeeklySummaryService: no notification permission")
            return
        }
        
        // Contenuto
        let content = UNMutableNotificationContent()
        content.title = "📋 Settimana di \(familyName)"
        // Prima riga del recap come body
        let firstLine = summaryText
            .components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        ?? "Il tuo recap settimanale è pronto."
        content.body       = firstLine
        content.sound      = .default
        content.userInfo   = [
            "type":     "weekly_summary",
            "fullText": String(summaryText.prefix(500)) // tronca per payload limite APNs
        ]
        
        // Trigger: prossimo lunedì alle 08:00
        var dc          = DateComponents()
        dc.weekday      = 2   // lunedì (domenica = 1)
        dc.hour         = 8
        dc.minute       = 0
        dc.second       = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        
        let notifId = "kb-weekly-summary-\(isoWeekKey())"
        let request = UNNotificationRequest(
            identifier: notifId,
            content:    content,
            trigger:    trigger
        )
        
        do {
            try await center.add(request)
            UserDefaults.standard.set(notifId, forKey: Keys.notifId)
            KBLog.ai.kbInfo("WeeklySummaryService: notification scheduled id=\(notifId)")
        } catch {
            KBLog.ai.kbError("WeeklySummaryService: schedule failed \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    
    /// Chiave ISO settimana: "2026-W13"
    private func isoWeekKey() -> String {
        let cal  = Calendar(identifier: .iso8601)
        let year = cal.component(.yearForWeekOfYear, from: Date())
        let week = cal.component(.weekOfYear, from: Date())
        return String(format: "%04d-W%02d", year, week)
    }
}

// MARK: - Deep link extension

extension NotificationManager.DeepLink {
    /// Deep link dedicato alla sintesi settimanale — apre PlanningAIChatView
    static var weeklySummary: NotificationManager.DeepLink { .askExpert }
}
