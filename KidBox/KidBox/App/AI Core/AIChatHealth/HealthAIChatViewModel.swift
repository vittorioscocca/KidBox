//
//  HealthAIChatViewModel.swift
//  KidBox
//
//  ViewModel for the full-health AI chat, opened from PediatricHomeView.
//  Works for both KBChild and KBFamilyMember — callers pass subjectName + subjectId.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - ViewModel

@MainActor
final class HealthAIChatViewModel: ObservableObject {
    
    // MARK: - Public state
    
    let subjectName: String
    let subjectId: String
    let exams: [KBMedicalExam]
    let visits: [KBMedicalVisit]
    let treatments: [KBTreatment]
    let vaccines: [KBVaccine]
    
    @Published var messages: [KBAIMessage] = []
    @Published var isLoading = false
    @Published var isLoadingContext = false
    @Published var errorMessage: String?
    
    // MARK: - Private
    
    private let modelContext: ModelContext
    private var conversation: KBAIConversation?
    private var systemPrompt: String = ""
    private var contextPrepared = false
    
    private let summaryThreshold = 8
    private let recentMessagesToKeepAfterSummary = 4
    
    /// Stable key used to persist/retrieve this conversation in the store.
    private var scopeId: String {
        let hash = (exams.map(\.id) + visits.map(\.id) + treatments.map(\.id) + vaccines.map(\.id))
            .sorted()
            .joined(separator: "-")
            .hashValue
        return "health-overview-\(subjectId)-\(abs(hash))"
    }
    
    // MARK: - Init
    
    init(
        subjectName: String,
        subjectId: String,
        exams: [KBMedicalExam],
        visits: [KBMedicalVisit],
        treatments: [KBTreatment],
        vaccines: [KBVaccine],
        modelContext: ModelContext
    ) {
        self.subjectName  = subjectName
        self.subjectId    = subjectId
        self.exams        = exams
        self.visits       = visits
        self.treatments   = treatments
        self.vaccines     = vaccines
        self.modelContext = modelContext
        
        KBLog.ai.kbInfo("""
        HealthAIChatVM init \
        subjectId=\(subjectId) \
        exams=\(exams.count) \
        visits=\(visits.count) \
        treatments=\(treatments.count) \
        vaccines=\(vaccines.count)
        """)
    }
    
    // MARK: - Load
    
    func loadOrCreateConversation() {
        guard !isLoadingContext else { return }
        isLoadingContext = true
        errorMessage    = nil
        
        do {
            let convo = try fetchOrCreateConversation()
            conversation = convo
            messages     = convo.sortedMessages
            
            let allDocs = try modelContext.fetch(FetchDescriptor<KBDocument>())
            
            let documentsByExamId: [String: [KBDocument]] = Dictionary(
                uniqueKeysWithValues: exams.map { exam in
                    let tag = ExamAttachmentTag.make(exam.id)
                    return (exam.id, allDocs.filter { !$0.isDeleted && $0.notes == tag })
                }
            )
            
            let documentsByVisitId: [String: [KBDocument]] = Dictionary(
                uniqueKeysWithValues: visits.map { visit in
                    let tag = VisitAttachmentTag.make(visit.id)
                    return (visit.id, allDocs.filter { !$0.isDeleted && $0.notes == tag })
                }
            )
            
            systemPrompt = HealthContextBuilder.buildSystemPrompt(
                subjectName:        subjectName,
                subjectId:          subjectId,
                exams:              exams,
                visits:             visits,
                treatments:         treatments,
                vaccines:           vaccines,
                documentsByExamId:  documentsByExamId,
                documentsByVisitId: documentsByVisitId
            )
            
            contextPrepared  = true
            isLoadingContext = false
            KBLog.ai.kbInfo("HealthAIChatVM context ready chars=\(systemPrompt.count)")
        } catch {
            isLoadingContext = false
            errorMessage = "Impossibile preparare il contesto sanitario."
            KBLog.ai.kbError("HealthAIChatVM loadOrCreate FAILED: \(error)")
        }
    }
    
    // MARK: - Clear
    
    func clearConversation() {
        guard let conversation else { messages.removeAll(); return }
        do {
            for message in conversation.messages { modelContext.delete(message) }
            conversation.summary                = nil
            conversation.summaryUpdatedAt       = nil
            conversation.summarizedMessageCount = 0
            try modelContext.save()
            messages.removeAll()
            errorMessage = nil
            KBLog.ai.kbInfo("HealthAIChatVM clearConversation OK")
        } catch {
            errorMessage = "Non sono riuscito a cancellare la conversazione."
            KBLog.ai.kbError("HealthAIChatVM clearConversation FAILED: \(error)")
        }
    }
    
    // MARK: - Send
    
    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }
        
        if !contextPrepared { loadOrCreateConversation() }
        
        guard let conversation else {
            errorMessage = "Conversazione non disponibile."
            return
        }
        
        errorMessage = nil
        isLoading    = true
        
        do {
            let userMessage = makeMessage(role: .user, text: trimmed)
            userMessage.conversation = conversation
            modelContext.insert(userMessage)
            try modelContext.save()
            messages.append(userMessage)
            
            try await summarizeIfNeeded(conversation: conversation)
            
            let payloadMessages   = buildPayloadMessages(conversation: conversation)
            let finalSystemPrompt = buildFinalSystemPrompt(conversation: conversation)
            
            KBLog.ai.kbInfo("HealthAIChatVM calling AIService payload=\(payloadMessages.count)")
            
            let response = try await AIService.shared.sendMessage(
                messages: payloadMessages,
                systemPrompt: finalSystemPrompt
            )
            
            let assistantMessage = makeMessage(role: .assistant, text: response.reply)
            assistantMessage.conversation = conversation
            modelContext.insert(assistantMessage)
            try modelContext.save()
            messages.append(assistantMessage)
            
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            KBLog.ai.kbError("HealthAIChatVM send FAILED: \(error)")
        }
    }
    
    // MARK: - Persistence helpers
    
    private func fetchOrCreateConversation() throws -> KBAIConversation {
        let sid = scopeId
        let all = try modelContext.fetch(FetchDescriptor<KBAIConversation>())
        if let existing = all.first(where: { $0.visitId == sid }) {
            KBLog.ai.kbInfo("HealthAIChatVM found existing conv id=\(existing.id)")
            return existing
        }
        let newConvo = KBAIConversation(
            familyId: subjectId,
            childId:  subjectId,
            visitId:  sid,
            provider: .claude
        )
        modelContext.insert(newConvo)
        try modelContext.save()
        KBLog.ai.kbInfo("HealthAIChatVM created new conv id=\(newConvo.id)")
        return newConvo
    }
    
    private func makeMessage(role: AIMessageRole, text: String) -> KBAIMessage {
        KBAIMessage(id: UUID().uuidString, role: role, content: text, createdAt: Date())
    }
    
    // MARK: - Summary compression
    
    private func summarizeIfNeeded(conversation: KBAIConversation) async throws {
        let sorted       = conversation.sortedMessages
        let unsummarized = sorted.count - conversation.summarizedMessageCount
        guard unsummarized > summaryThreshold,
              sorted.count > recentMessagesToKeepAfterSummary else { return }
        
        let toSummarize = Array(sorted.prefix(sorted.count - recentMessagesToKeepAfterSummary))
        guard !toSummarize.isEmpty else { return }
        
        let transcript = toSummarize
            .map { "[\($0.role.rawValue)] \($0.content)" }
            .joined(separator: "\n")
        
        let summarySystemPrompt = """
        Riassumi in modo fedele e compatto la conversazione seguente.
        Mantieni:
        - richieste principali dell'utente
        - dati sanitari discussi (cure, vaccini, visite, esami)
        - risultati o referti menzionati
        - eventuali dubbi ancora aperti
        Non aggiungere nulla di nuovo.
        """
        
        let response = try await AIService.shared.sendMessage(
            messages: [KBAIMessage(role: .user, content: transcript)],
            systemPrompt: summarySystemPrompt
        )
        conversation.summary                = response.reply
        conversation.summaryUpdatedAt       = Date()
        conversation.summarizedMessageCount = toSummarize.count
        try modelContext.save()
        KBLog.ai.kbInfo("HealthAIChatVM summary updated chars=\(response.reply.count)")
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
        Array(conversation.sortedMessages.dropFirst(conversation.summarizedMessageCount))
            .map { KBAIMessage(id: $0.id, role: $0.role, content: $0.content, createdAt: $0.createdAt) }
    }
}
