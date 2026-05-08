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
    @Published var usageToday: Int = 0
    @Published var dailyLimit: Int = 0
    
    // MARK: - Private
    
    private let modelContext: ModelContext
    private var conversation: KBAIConversation?
    private var systemPrompt: String = ""
    private var contextPrepared = false
    
    private let compactionThreshold: Double = 0.60
    private var lastCompactionThreshold: Int = 0
    
    /// Stable key used to persist/retrieve this conversation in the store.
    private var scopeId: String {
        "health-overview-v2-\(subjectId)"
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
            if convo.summary?.isEmpty == false { lastCompactionThreshold = 3 }
            
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
            Task { await refreshUsage() }
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
            
            let payloadMessages   = buildPayloadMessages(conversation: conversation)
            let finalSystemPrompt = buildFinalSystemPrompt(conversation: conversation)
            
            KBLog.ai.kbInfo("HealthAIChatVM calling AIService payload=\(payloadMessages.count)")
            
            let response = try await AIService.shared.sendMessage(
                messages: payloadMessages,
                systemPrompt: finalSystemPrompt
            )
            usageToday = response.usageToday
            dailyLimit = response.dailyLimit
            
            let assistantMessage = makeMessage(role: .assistant, text: response.reply)
            assistantMessage.conversation = conversation
            modelContext.insert(assistantMessage)
            try modelContext.save()
            messages.append(assistantMessage)
            try await compactIfNeeded(
                conversation: conversation,
                messagesInSession: response.usageToday,
                dailyLimit: response.dailyLimit
            )
            
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            KBLog.ai.kbError("HealthAIChatVM send FAILED: \(error)")
        }
    }
    
    private func refreshUsage() async {
        do {
            let usage = try await AIService.shared.fetchUsage()
            usageToday = usage.usageToday
            dailyLimit = usage.dailyLimit
        } catch {
            // Non-blocking: UI can still work without counters.
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
    
    // MARK: - Compaction
    
    private func shouldCompact(messagesInSession: Int, dailyLimit: Int) -> Bool {
        guard dailyLimit > 0 else { return false }
        return Double(messagesInSession) >= Double(dailyLimit) * compactionThreshold
    }
    
    private func compactIfNeeded(
        conversation: KBAIConversation,
        messagesInSession: Int,
        dailyLimit: Int
    ) async throws {
        guard shouldCompact(messagesInSession: messagesInSession, dailyLimit: dailyLimit) else { return }
        let stepBase = Double(dailyLimit) * 0.20
        guard stepBase > 0 else { return }
        let currentThresholdStep = Int(Double(messagesInSession) / stepBase)
        guard currentThresholdStep > lastCompactionThreshold else { return }
        
        let fullMessages = conversation.sortedMessages
        guard !fullMessages.isEmpty else { return }
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
            .map { KBAIMessage(id: $0.id, role: $0.role, content: $0.content, createdAt: $0.createdAt) }
        return ([summaryMessage].compactMap { $0 } + recent).prefix(7).map { $0 }
    }
    
    private static let compactionSystemPrompt = "Riassumi in modo conciso ma completo la conversazione seguente, mantenendo i punti chiave, le decisioni prese e il contesto importante. Il riassunto sarà usato come contesto per continuare la conversazione."
}
