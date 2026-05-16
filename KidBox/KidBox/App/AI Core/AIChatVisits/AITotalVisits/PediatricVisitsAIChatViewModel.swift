//
//  PediatricVisitsAIChatViewModel.swift
//  KidBox
//

import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
final class PediatricVisitsAIChatViewModel: ObservableObject {
    
    // MARK: - Public
    
    let subjectName: String
    let visibleVisits: [KBMedicalVisit]
    let selectedPeriod: PeriodFilter
    let scopeId: String
    
    // MARK: - Private
    
    private let modelContext: ModelContext
    private var conversation: KBAIConversation?
    private var contextVisits: [KBMedicalVisit] = []
    private var systemPrompt: String = ""
    private var contextPrepared = false
    let customStartDate: Date?
    let customEndDate: Date?
    
    
    private let compactionThreshold: Double = 0.60
    private var lastCompactionThreshold: Int = 0
    
    // MARK: - Published
    
    @Published var messages: [KBAIMessage] = []
    @Published var streamingMessageId: String?
    @Published var isLoading = false
    @Published var isLoadingContext = false
    @Published var errorMessage: String?
    @Published var usageToday: Int = 0
    @Published var dailyLimit: Int = 0
    @Published var actionExecutionSummary: String? = nil
    
    // MARK: - Init
    
    init(
        subjectName: String,
        visibleVisits: [KBMedicalVisit],
        selectedPeriod: PeriodFilter,
        customStartDate: Date? = nil,
        customEndDate: Date? = nil,
        scopeId: String,
        modelContext: ModelContext
    ){
        self.subjectName = subjectName
        self.visibleVisits = visibleVisits
        self.selectedPeriod = selectedPeriod
        self.scopeId = scopeId
        self.modelContext = modelContext
        self.customStartDate = customStartDate
        self.customEndDate = customEndDate
        
        KBLog.ai.kbInfo("AIChatVM init subjectName=\(subjectName)")
        KBLog.ai.kbInfo("AIChatVM init selectedPeriod=\(selectedPeriod.rawValue)")
        KBLog.ai.kbInfo("AIChatVM init scopeId=\(scopeId)")
        KBLog.ai.kbInfo("AIChatVM init visibleVisits.count=\(visibleVisits.count)")
        KBLog.ai.kbDebug("AIChatVM init visitIds=\(visibleVisits.map(\.id).joined(separator: ","))")
    }
    
    // MARK: - Public
    
    func loadOrCreateConversation() {
        KBLog.ai.kbInfo("loadOrCreateConversation START")
        
        guard !isLoadingContext else {
            KBLog.ai.kbDebug("loadOrCreateConversation skipped: already loading")
            return
        }
        
        isLoadingContext = true
        errorMessage = nil
        
        do {
            let convo = try fetchOrCreateConversation()
            conversation = convo
            messages = convo.sortedMessages
            if convo.summary?.isEmpty == false { lastCompactionThreshold = 3 }
            
            contextVisits = visibleVisits
                .filter { !$0.isDeleted }
                .sorted { $0.date < $1.date }
            
            KBLog.ai.kbInfo("conversation loaded id=\(convo.id)")
            KBLog.ai.kbInfo("messages loaded count=\(messages.count)")
            KBLog.ai.kbInfo("contextVisits.count=\(contextVisits.count)")
            KBLog.ai.kbDebug("contextVisitIds=\(contextVisits.map(\.id).joined(separator: ","))")
            
            let treatmentsByVisitId = try fetchTreatmentsByVisitId(visits: contextVisits)
            let documentsByVisitId = try fetchDocumentsByVisitId(visits: contextVisits)
            
            systemPrompt = withFamilyMemory(
                buildSystemPrompt(
                    subjectName: subjectName,
                    visits: contextVisits,
                    treatmentsByVisitId: treatmentsByVisitId,
                    documentsByVisitId: documentsByVisitId
                )
            )
            
            contextPrepared = true
            isLoadingContext = false
            Task { await refreshUsage() }
            
            KBLog.ai.kbInfo("loadOrCreateConversation END systemPromptChars=\(systemPrompt.count)")
        } catch {
            isLoadingContext = false
            errorMessage = "Impossibile preparare il contesto delle visite."
            KBLog.ai.kbError("loadOrCreateConversation FAILED error=\(String(describing: error))")
        }
    }
    
    private var periodDescription: String {
        if selectedPeriod == .custom,
           let customStartDate,
           let customEndDate {
            let start = min(customStartDate, customEndDate)
            let end = max(customStartDate, customEndDate)
            return "\(start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))"
        }
        
        return selectedPeriod.rawValue
    }
    
    func clearConversation() {
        KBLog.ai.kbInfo("clearConversation START")
        
        guard let conversation else {
            messages.removeAll()
            streamingMessageId = nil
            KBLog.ai.kbDebug("clearConversation no conversation in memory")
            return
        }
        
        do {
            for message in conversation.messages {
                modelContext.delete(message)
            }
            conversation.summary = nil
            conversation.summaryUpdatedAt = nil
            conversation.summarizedMessageCount = 0
            
            try modelContext.save()
            
            messages.removeAll()
            streamingMessageId = nil
            errorMessage = nil

            KBLog.ai.kbInfo("clearConversation END")
        } catch {
            errorMessage = "Non sono riuscito a cancellare la conversazione."
            KBLog.ai.kbError("clearConversation FAILED error=\(String(describing: error))")
        }
    }
    
    func finishStreaming(messageId: String) {
        AIChatStreamingDelivery.finishReveal(messageId: messageId, streamingMessageId: &streamingMessageId)
    }

    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        KBLog.ai.kbInfo("send called textLength=\(trimmed.count)")
        
        guard !trimmed.isEmpty else {
            KBLog.ai.kbDebug("send aborted empty text")
            return
        }
        
        guard !isLoading else {
            KBLog.ai.kbDebug("send aborted already loading")
            return
        }
        
        if !contextPrepared {
            KBLog.ai.kbInfo("context not ready -> loading")
            loadOrCreateConversation()
        }
        
        guard let conversation else {
            errorMessage = "Conversazione non disponibile."
            KBLog.ai.kbError("send aborted conversation nil")
            return
        }
        
        errorMessage = nil
        isLoading = true
        
        do {
            let userMessage = makeMessage(role: .user, text: trimmed)
            userMessage.conversation = conversation
            modelContext.insert(userMessage)
            try modelContext.save()
            messages.append(userMessage)
            
            KBLog.ai.kbInfo("user message saved id=\(userMessage.id)")
            
            let payloadMessages = buildPayloadMessages(conversation: conversation)
            let finalSystemPrompt = buildFinalSystemPrompt(conversation: conversation)
            
            KBLog.ai.kbInfo("calling AIService payloadMessages.count=\(payloadMessages.count)")
            KBLog.ai.kbInfo("calling AIService finalSystemPrompt.chars=\(finalSystemPrompt.count)")
            
            let response = try await AIService.shared.sendMessage(
                messages: payloadMessages,
                systemPrompt: finalSystemPrompt
            )
            usageToday = response.usageToday
            dailyLimit = response.dailyLimit
            
            KBLog.ai.kbInfo("AI reply received chars=\(response.reply.count)")
            KBLog.ai.kbInfo("AI usage=\(response.usageToday)/\(response.dailyLimit)")
            
            let familyId = contextVisits.first?.familyId ?? visibleVisits.first?.familyId ?? ""
            let childId = contextVisits.first?.childId ?? visibleVisits.first?.childId
            let outcome = await KidBoxAIActionPipeline.processReply(
                response.reply,
                modelContext: modelContext,
                familyId: familyId,
                defaultChildId: childId,
                pendingGroceryNames: KidBoxAIActionPipeline.fetchPendingGroceryNames(
                    familyId: familyId,
                    modelContext: modelContext
                )
            )
            actionExecutionSummary = outcome.executionSummary
            
            let assistantMessage = makeMessage(role: .assistant, text: outcome.displayText)
            assistantMessage.conversation = conversation
            modelContext.insert(assistantMessage)
            try modelContext.save()
            isLoading = false
            messages.append(assistantMessage)
            AIChatStreamingDelivery.beginAssistantReveal(
                messageId: assistantMessage.id,
                streamingMessageId: &streamingMessageId
            )
            try await compactIfNeeded(
                conversation: conversation,
                messagesInSession: response.usageToday,
                dailyLimit: response.dailyLimit
            )

            KBLog.ai.kbInfo("assistant message saved id=\(assistantMessage.id)")
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            KBLog.ai.kbError("send FAILED error=\(String(describing: error))")
        }
    }
    
    private func refreshUsage() async {
        do {
            let usage = try await AIService.shared.fetchUsage()
            usageToday = usage.usageToday
            dailyLimit = usage.dailyLimit
        } catch {
            // Non-blocking: counters can fail silently.
        }
    }
    
    // MARK: - Conversation
    
    private func fetchOrCreateConversation() throws -> KBAIConversation {
        KBLog.ai.kbInfo("fetchOrCreateConversation scopeId=\(scopeId)")
        
        let all = try modelContext.fetch(FetchDescriptor<KBAIConversation>())
        
        if let existing = all.first(where: { $0.visitId == scopeId }) {
            KBLog.ai.kbInfo("fetchOrCreateConversation found existing id=\(existing.id)")
            return existing
        }
        
        KBLog.ai.kbInfo("fetchOrCreateConversation creating new conversation")
        
        let newConversation = KBAIConversation(
            familyId: "pediatric-visits",
            childId: "pediatric-visits",
            visitId: scopeId,
            provider: .claude
        )
        
        modelContext.insert(newConversation)
        try modelContext.save()
        
        KBLog.ai.kbInfo("fetchOrCreateConversation created id=\(newConversation.id)")
        return newConversation
    }
    
    private func makeMessage(role: AIMessageRole, text: String) -> KBAIMessage {
        KBAIMessage(
            id: UUID().uuidString,
            role: role,
            content: text,
            createdAt: Date()
        )
    }
    
    // MARK: - Compaction
    
    private func shouldCompact(messagesInSession: Int, dailyLimit: Int) -> Bool {
        guard dailyLimit > 0 else { return false }
        return Double(messagesInSession) >= Double(dailyLimit) * compactionThreshold
    }
    
    private func compactIfNeeded(conversation: KBAIConversation, messagesInSession: Int, dailyLimit: Int) async throws {
        guard shouldCompact(messagesInSession: messagesInSession, dailyLimit: dailyLimit) else { return }
        let stepBase = Double(dailyLimit) * 0.20
        guard stepBase > 0 else { return }
        let currentThresholdStep = Int(Double(messagesInSession) / stepBase)
        guard currentThresholdStep > lastCompactionThreshold else { return }
        
        let fullMessages = conversation.sortedMessages
        guard !fullMessages.isEmpty else { return }
        let messagesForMemoryExtraction = fullMessages
        let summaryReply = try await AIService.shared.sendMessage(
            messages: fullMessages.map { KBAIMessage(id: $0.id, role: $0.role, content: $0.content, createdAt: $0.createdAt) },
            systemPrompt: Self.compactionSystemPrompt
        )
        let compacted = KBAIMessage(
            id: "summary-\(conversation.id)",
            role: .assistant,
            content: summaryReply.reply
        )
        compacted.conversation = conversation
        conversation.messages.removeAll()
        modelContext.insert(compacted)
        conversation.summary = summaryReply.reply
        conversation.summaryUpdatedAt = Date()
        conversation.summarizedMessageCount = 0
        lastCompactionThreshold = currentThresholdStep
        try modelContext.save()
        messages = [compacted]

        let fid = Self.activeFamilyId
        let ctx = modelContext
        let memorySnapshot = messagesForMemoryExtraction
        Task {
            await FamilyMemoryService.shared.extractAndStore(
                from: conversation,
                familyId: fid,
                modelContext: ctx,
                transcriptMessages: memorySnapshot
            )
        }
        KBLog.ai.kbDebug("PediatricVisitsAIChatVM: scheduled family memory extract convId=\(conversation.id)")
    }
    
    // MARK: - Payload building
    
    private func buildFinalSystemPrompt(conversation: KBAIConversation) -> String {
        systemPrompt
    }
    
    private func buildPayloadMessages(conversation: KBAIConversation) -> [KBAIMessage] {
        let sorted = conversation.sortedMessages
        let summary = conversation.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryMessage = summary.flatMap { s -> KBAIMessage? in
            guard !s.isEmpty else { return nil }
            return KBAIMessage(role: .assistant, content: s)
        }
        let recent = sorted
            .filter { msg in
                guard let summary else { return true }
                return !(msg.role == .assistant && msg.content == summary)
            }
            .suffix(6)
            .map {
            KBAIMessage(
                id: $0.id,
                role: $0.role,
                content: $0.content,
                createdAt: $0.createdAt
            )
        }
        let payload = ([summaryMessage].compactMap { $0 } + recent).prefix(7).map { $0 }
        KBLog.ai.kbInfo("buildPayloadMessages payload.count=\(payload.count)")
        return payload
    }
    
    private static let compactionSystemPrompt = "Riassumi in modo conciso ma completo la conversazione seguente, mantenendo i punti chiave, le decisioni prese e il contesto importante. Il riassunto sarà usato come contesto per continuare la conversazione."
    
    // MARK: - Fetch context
    
    private func fetchTreatmentsByVisitId(
        visits: [KBMedicalVisit]
    ) throws -> [String: [KBTreatment]] {
        let treatmentIds = Set(visits.flatMap(\.linkedTreatmentIds))
        guard !treatmentIds.isEmpty else { return [:] }
        
        let allTreatments = try modelContext.fetch(FetchDescriptor<KBTreatment>())
        let filtered = allTreatments.filter { treatmentIds.contains($0.id) && !$0.isDeleted }
        let map = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, $0) })
        
        var result: [String: [KBTreatment]] = [:]
        for visit in visits {
            result[visit.id] = visit.linkedTreatmentIds.compactMap { map[$0] }
        }
        return result
    }
    
    private func fetchDocumentsByVisitId(
        visits: [KBMedicalVisit]
    ) throws -> [String: [KBDocument]] {
        let visitIds = Set(visits.map(\.id))
        guard !visitIds.isEmpty else { return [:] }
        
        let allDocs = try modelContext.fetch(FetchDescriptor<KBDocument>())
        
        var result: [String: [KBDocument]] = [:]
        for visitId in visitIds {
            let tag = VisitAttachmentTag.make(visitId)
            result[visitId] = allDocs.filter { !$0.isDeleted && $0.notes == tag }
        }
        return result
    }
    
    // MARK: - Prompt
    
    private func buildSystemPrompt(
        subjectName: String,
        visits: [KBMedicalVisit],
        treatmentsByVisitId: [String: [KBTreatment]],
        documentsByVisitId: [String: [KBDocument]]
    ) -> String {
        KBLog.ai.kbInfo("buildSystemPrompt START subjectName=\(subjectName)")
        KBLog.ai.kbInfo("buildSystemPrompt visits.count=\(visits.count)")
        
        var lines: [String] = []
        
        lines.append("CONTESTO VISITE KIDBOX")
        lines.append("Persona: \(subjectName)")
        lines.append("Periodo selezionato: \(periodDescription)")
        lines.append("Numero visite visibili: \(visits.count)")
        lines.append("")
        lines.append("Sei l'assistente AI di KidBox.")
        lines.append("Rispondi in italiano.")
        lines.append("Usa solo le informazioni presenti sotto.")
        lines.append("Non inventare dati mancanti.")
        lines.append("Se un dato non è disponibile, dillo chiaramente.")
        lines.append("Non sostituisci il medico.")
        
        for (index, visit) in visits.enumerated() {
            lines.append("")
            lines.append("==========")
            lines.append("VISITA \(index + 1)")
            lines.append("ID visita: \(visit.id)")
            lines.append("Data visita: \(visit.date.formatted(date: .abbreviated, time: .shortened))")
            lines.append("Titolo/Motivo visita: \(visit.reason)")
            
            if let doctorName = visit.doctorName,
               !doctorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("Dottore: \(doctorName)")
            }
            
            if let spec = visit.doctorSpecializationRaw,
               !spec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("Specializzazione: \(spec)")
            }
            
            if let diagnosis = visit.diagnosis,
               !diagnosis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("Diagnosi: \(diagnosis)")
            }
            
            if let recommendations = visit.recommendations,
               !recommendations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("Raccomandazioni: \(recommendations)")
            }
            
            if let notes = visit.notes,
               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("Appunti visita / Note: \(notes)")
            }
            
            if let nextVisitDate = visit.nextVisitDate {
                lines.append("Prossima visita: \(nextVisitDate.formatted(date: .abbreviated, time: .omitted))")
            }
            
            if let nextVisitReason = visit.nextVisitReason,
               !nextVisitReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("Motivo prossima visita: \(nextVisitReason)")
            }
            
            if !visit.therapyTypes.isEmpty {
                lines.append("Tipi di terapia: \(visit.therapyTypes.map(\.rawValue).joined(separator: ", "))")
            }
            
            if !visit.asNeededDrugs.isEmpty {
                lines.append("Farmaci al bisogno:")
                for drug in visit.asNeededDrugs {
                    var row = "- \(drug.drugName) \(String(format: "%.0f", drug.dosageValue)) \(drug.dosageUnit)"
                    if let instructions = drug.instructions,
                       !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        row += " | istruzioni: \(instructions)"
                    }
                    lines.append(row)
                }
            }
            
            if !visit.prescribedExams.isEmpty {
                lines.append("Esami prescritti:")
                for exam in visit.prescribedExams {
                    var row = "- \(exam.name)"
                    if exam.isUrgent {
                        row += " | urgente"
                    }
                    if let deadline = exam.deadline {
                        row += " | entro: \(deadline.formatted(date: .abbreviated, time: .omitted))"
                    }
                    if let preparation = exam.preparation,
                       !preparation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        row += " | preparazione: \(preparation)"
                    }
                    lines.append(row)
                }
            }
            
            let treatments = treatmentsByVisitId[visit.id] ?? []
            if !treatments.isEmpty {
                lines.append("Cure collegate:")
                for treatment in treatments {
                    var row = "- \(treatment.drugName)"
                    row += " | dose: \(String(format: "%.0f", treatment.dosageValue)) \(treatment.dosageUnit)"
                    row += " | frequenza: \(treatment.frequencyDisplayLabel)"
                    if treatment.isLongTerm {
                        row += " | lungo termine"
                    } else {
                        row += " | durata: \(treatment.durationDays) giorni"
                    }
                    lines.append(row)
                }
            }
            
            let docs = documentsByVisitId[visit.id] ?? []
            if !docs.isEmpty {
                lines.append("Allegati / Referti:")
                for doc in docs {
                    lines.append("- Titolo allegato: \(doc.title)")
                    lines.append("  Nome file: \(doc.fileName)")
                    lines.append("  MIME: \(doc.mimeType)")
                    lines.append("  Stato estrazione: \(doc.extractionStatus.rawValue)")
                    
                    if let extracted = doc.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !extracted.isEmpty {
                        lines.append("  Testo estratto allegato:")
                        lines.append("  \(extracted)")
                    } else {
                        lines.append("  Testo estratto allegato: non disponibile")
                    }
                }
            }
        }
        
        let prompt = lines.joined(separator: "\n")
        KBLog.ai.kbInfo("buildSystemPrompt END chars=\(prompt.count)")
        return prompt
    }

    private static var activeFamilyId: String {
        UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?.string(forKey: "activeFamilyId") ?? ""
    }

    private func withFamilyMemory(_ base: String) -> String {
        let memFacts = FamilyMemoryService.shared.fetchFacts(
            for: Self.activeFamilyId,
            modelContext: modelContext
        ).map(\.content)
        guard !memFacts.isEmpty else { return base }
        var prompt = base
        prompt += "\n\n## Memoria famiglia\n"
        prompt += memFacts.map { "• \($0)" }.joined(separator: "\n")
        prompt += "\nUsa questi fatti per personalizzare le risposte senza citare esplicitamente che li hai memorizzati."
        return prompt
    }
}
