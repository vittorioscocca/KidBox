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
    
    
    private let summaryThreshold = 8
    private let recentMessagesToKeepAfterSummary = 4
    
    // MARK: - Published
    
    @Published var messages: [KBAIMessage] = []
    @Published var isLoading = false
    @Published var isLoadingContext = false
    @Published var errorMessage: String?
    
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
            
            contextVisits = visibleVisits
                .filter { !$0.isDeleted }
                .sorted { $0.date < $1.date }
            
            KBLog.ai.kbInfo("conversation loaded id=\(convo.id)")
            KBLog.ai.kbInfo("messages loaded count=\(messages.count)")
            KBLog.ai.kbInfo("contextVisits.count=\(contextVisits.count)")
            KBLog.ai.kbDebug("contextVisitIds=\(contextVisits.map(\.id).joined(separator: ","))")
            
            let treatmentsByVisitId = try fetchTreatmentsByVisitId(visits: contextVisits)
            let documentsByVisitId = try fetchDocumentsByVisitId(visits: contextVisits)
            
            systemPrompt = buildSystemPrompt(
                subjectName: subjectName,
                visits: contextVisits,
                treatmentsByVisitId: treatmentsByVisitId,
                documentsByVisitId: documentsByVisitId
            )
            
            contextPrepared = true
            isLoadingContext = false
            
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
            errorMessage = nil
            
            KBLog.ai.kbInfo("clearConversation END")
        } catch {
            errorMessage = "Non sono riuscito a cancellare la conversazione."
            KBLog.ai.kbError("clearConversation FAILED error=\(String(describing: error))")
        }
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
            
            try await summarizeIfNeeded(conversation: conversation)
            
            let payloadMessages = buildPayloadMessages(conversation: conversation)
            let finalSystemPrompt = buildFinalSystemPrompt(conversation: conversation)
            
            KBLog.ai.kbInfo("calling AIService payloadMessages.count=\(payloadMessages.count)")
            KBLog.ai.kbInfo("calling AIService finalSystemPrompt.chars=\(finalSystemPrompt.count)")
            
            let response = try await AIService.shared.sendMessage(
                messages: payloadMessages,
                systemPrompt: finalSystemPrompt
            )
            
            KBLog.ai.kbInfo("AI reply received chars=\(response.reply.count)")
            KBLog.ai.kbInfo("AI usage=\(response.usageToday)/\(response.dailyLimit)")
            
            let assistantMessage = makeMessage(role: .assistant, text: response.reply)
            assistantMessage.conversation = conversation
            modelContext.insert(assistantMessage)
            try modelContext.save()
            messages.append(assistantMessage)
            
            KBLog.ai.kbInfo("assistant message saved id=\(assistantMessage.id)")
            
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            KBLog.ai.kbError("send FAILED error=\(String(describing: error))")
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
    
    // MARK: - Summary compression
    
    private func summarizeIfNeeded(conversation: KBAIConversation) async throws {
        let sorted = conversation.sortedMessages
        let unsummarizedCount = sorted.count - conversation.summarizedMessageCount
        
        KBLog.ai.kbInfo("summarizeIfNeeded unsummarizedCount=\(unsummarizedCount)")
        
        guard unsummarizedCount > summaryThreshold else { return }
        guard sorted.count > recentMessagesToKeepAfterSummary else { return }
        
        let messagesToSummarize = Array(sorted.prefix(sorted.count - recentMessagesToKeepAfterSummary))
        guard !messagesToSummarize.isEmpty else { return }
        
        let transcript = messagesToSummarize.map {
            "[\($0.role.rawValue)] \($0.content)"
        }.joined(separator: "\n")
        
        let summarySystemPrompt = """
        Riassumi in modo fedele e compatto la conversazione seguente.
        Mantieni:
        - richieste principali dell'utente
        - referti o allegati discussi
        - diagnosi, raccomandazioni, terapie, cure, esami menzionati
        - eventuali dubbi ancora aperti
        Non aggiungere nulla di nuovo.
        """
        
        let summaryMessages = [
            KBAIMessage(role: .user, content: transcript)
        ]
        
        KBLog.ai.kbInfo("summarizeIfNeeded calling AIService messages=\(summaryMessages.count)")
        
        let response = try await AIService.shared.sendMessage(
            messages: summaryMessages,
            systemPrompt: summarySystemPrompt
        )
        
        conversation.summary = response.reply
        conversation.summaryUpdatedAt = Date()
        conversation.summarizedMessageCount = messagesToSummarize.count
        
        try modelContext.save()
        
        KBLog.ai.kbInfo("summarizeIfNeeded updated summary chars=\(response.reply.count)")
        KBLog.ai.kbInfo("summarizeIfNeeded summarizedMessageCount=\(conversation.summarizedMessageCount)")
    }
    
    // MARK: - Payload building
    
    private func buildFinalSystemPrompt(conversation: KBAIConversation) -> String {
        guard let summary = conversation.summary,
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return systemPrompt
        }
        
        return """
        \(systemPrompt)
        
        RIASSUNTO CONVERSAZIONE PRECEDENTE
        \(summary)
        """
    }
    
    private func buildPayloadMessages(conversation: KBAIConversation) -> [KBAIMessage] {
        let recentMessages = Array(conversation.sortedMessages.dropFirst(conversation.summarizedMessageCount))
        
        KBLog.ai.kbInfo("buildPayloadMessages recentMessages.count=\(recentMessages.count)")
        
        return recentMessages.map {
            KBAIMessage(
                id: $0.id,
                role: $0.role,
                content: $0.content,
                createdAt: $0.createdAt
            )
        }
    }
    
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
                    row += " | frequenza: \(treatment.dailyFrequency)x/die"
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
}
