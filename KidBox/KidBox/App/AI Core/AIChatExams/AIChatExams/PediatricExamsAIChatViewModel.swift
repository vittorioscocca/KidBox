//
//  PediatricExamsAIChatViewModel.swift
//  KidBox
//

import Foundation
import SwiftUI
import SwiftData
import Combine


import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - Scope

enum ExamAIChatScope {
    case single(KBMedicalExam)
    case all([KBMedicalExam])
    
    var exams: [KBMedicalExam] {
        switch self {
        case .single(let e): return [e]
        case .all(let es):   return es
        }
    }
    
    var scopeId: String {
        switch self {
        case .single(let e): return "exam-single-\(e.id)"
        case .all(let es):
            let hash = es.map(\.id).sorted().joined(separator: "-").hashValue
            return "exam-all-\(abs(hash))"
        }
    }
    
    var isSingle: Bool {
        if case .single = self { return true }
        return false
    }
}


// MARK: - ViewModel
@MainActor
final class PediatricExamsAIChatViewModel: ObservableObject {
    
    // MARK: - Public
    
    let subjectName: String
    let scope: ExamAIChatScope
    
    // MARK: - Private
    
    private let modelContext: ModelContext
    private var conversation: KBAIConversation?
    private var systemPrompt: String = ""
    private var contextPrepared = false
    
    private let summaryThreshold = 8
    private let recentMessagesToKeepAfterSummary = 4
    
    // MARK: - Published
    
    @Published var messages: [KBAIMessage] = []
    @Published var isLoading = false
    @Published var isLoadingContext = false
    @Published var errorMessage: String?
    
    // MARK: - Init
    
    init(subjectName: String, scope: ExamAIChatScope, modelContext: ModelContext) {
        self.subjectName  = subjectName
        self.scope        = scope
        self.modelContext = modelContext
        KBLog.ai.kbInfo("ExamsAIChatVM init subjectName=\(subjectName) scope=\(scope.scopeId) exams=\(scope.exams.count)")
    }
    
    // MARK: - Load
    
    func loadOrCreateConversation() {
        guard !isLoadingContext else { return }
        isLoadingContext = true
        errorMessage = nil
        
        do {
            let convo = try fetchOrCreateConversation()
            conversation = convo
            messages = convo.sortedMessages
            
            let contextExams = scope.exams
                .filter { !$0.isDeleted }
                .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            
            let documentsByExamId = try fetchDocumentsByExamId(exams: contextExams)
            
            systemPrompt = buildSystemPrompt(
                subjectName: subjectName,
                scope: scope,
                exams: contextExams,
                documentsByExamId: documentsByExamId
            )
            
            contextPrepared  = true
            isLoadingContext = false
            KBLog.ai.kbInfo("ExamsAIChatVM context ready chars=\(systemPrompt.count)")
        } catch {
            isLoadingContext = false
            errorMessage = "Impossibile preparare il contesto degli esami."
            KBLog.ai.kbError("ExamsAIChatVM loadOrCreate FAILED: \(error)")
        }
    }
    
    // MARK: - Clear
    
    func clearConversation() {
        guard let conversation else { messages.removeAll(); return }
        do {
            for message in conversation.messages { modelContext.delete(message) }
            conversation.summary = nil
            conversation.summaryUpdatedAt = nil
            conversation.summarizedMessageCount = 0
            try modelContext.save()
            messages.removeAll()
            errorMessage = nil
            KBLog.ai.kbInfo("ExamsAIChatVM clearConversation OK")
        } catch {
            errorMessage = "Non sono riuscito a cancellare la conversazione."
            KBLog.ai.kbError("ExamsAIChatVM clearConversation FAILED: \(error)")
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
            
            KBLog.ai.kbInfo("ExamsAIChatVM calling AIService payload=\(payloadMessages.count)")
            
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
            KBLog.ai.kbError("ExamsAIChatVM send FAILED: \(error)")
        }
    }
    
    // MARK: - Conversation persistence
    
    private func fetchOrCreateConversation() throws -> KBAIConversation {
        let sid = scope.scopeId
        let all = try modelContext.fetch(FetchDescriptor<KBAIConversation>())
        if let existing = all.first(where: { $0.visitId == sid }) {
            KBLog.ai.kbInfo("ExamsAIChatVM found existing conv id=\(existing.id)")
            return existing
        }
        let newConvo = KBAIConversation(
            familyId: "pediatric-exams",
            childId:  "pediatric-exams",
            visitId:  sid,
            provider: .claude
        )
        modelContext.insert(newConvo)
        try modelContext.save()
        KBLog.ai.kbInfo("ExamsAIChatVM created new conv id=\(newConvo.id)")
        return newConvo
    }
    
    private func makeMessage(role: AIMessageRole, text: String) -> KBAIMessage {
        KBAIMessage(id: UUID().uuidString, role: role, content: text, createdAt: Date())
    }
    
    // MARK: - Summary compression
    
    private func summarizeIfNeeded(conversation: KBAIConversation) async throws {
        let sorted = conversation.sortedMessages
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
        - esami discussi e loro stato
        - risultati, referti o allegati menzionati
        - eventuali dubbi ancora aperti
        Non aggiungere nulla di nuovo.
        """
        
        let response = try await AIService.shared.sendMessage(
            messages: [KBAIMessage(role: .user, content: transcript)],
            systemPrompt: summarySystemPrompt
        )
        conversation.summary = response.reply
        conversation.summaryUpdatedAt = Date()
        conversation.summarizedMessageCount = toSummarize.count
        try modelContext.save()
        KBLog.ai.kbInfo("ExamsAIChatVM summary updated chars=\(response.reply.count)")
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
    
    // MARK: - Fetch documents
    
    private func fetchDocumentsByExamId(exams: [KBMedicalExam]) throws -> [String: [KBDocument]] {
        guard !exams.isEmpty else { return [:] }
        let allDocs = try modelContext.fetch(FetchDescriptor<KBDocument>())
        var result: [String: [KBDocument]] = [:]
        for exam in exams {
            let tag = ExamAttachmentTag.make(exam.id)
            result[exam.id] = allDocs.filter { !$0.isDeleted && $0.notes == tag }
        }
        return result
    }
    
    // MARK: - System prompt (delegated to ExamContextBuilder)
    
    private func buildSystemPrompt(
        subjectName: String,
        scope: ExamAIChatScope,
        exams: [KBMedicalExam],
        documentsByExamId: [String: [KBDocument]]
    ) -> String {
        switch scope {
        case .single(let exam):
            return ExamContextBuilder.buildSystemPrompt(
                exam: exam,
                subjectName: subjectName,
                documents: documentsByExamId[exam.id] ?? []
            )
        case .all:
            return ExamContextBuilder.buildSystemPrompt(
                exams: exams,
                subjectName: subjectName,
                documentsByExamId: documentsByExamId
            )
        }
    }
}
