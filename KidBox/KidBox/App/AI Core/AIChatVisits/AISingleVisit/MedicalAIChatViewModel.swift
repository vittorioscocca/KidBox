//
//  MedicalAIChatViewModel.swift
//  KidBox
//

import Foundation
import SwiftData
import OSLog
import Combine

@MainActor
final class MedicalAIChatViewModel: ObservableObject {
    
    // MARK: - Published
    
    @Published var messages: [KBAIMessage] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var inputText: String = ""
    @Published var isLoadingContext: Bool = true
    
    // MARK: - Dependencies
    
    private let visit: KBMedicalVisit
    private let child: KBChild
    private let modelContext: ModelContext
    
    // MARK: - Private state
    
    private var conversation: KBAIConversation?
    private var systemPrompt: String = ""
    
    // MARK: - Summary config
    
    private let summaryThreshold               = 8
    private let recentMessagesToKeepAfterSummary = 4
    
    // MARK: - Init
    
    init(visit: KBMedicalVisit, child: KBChild, modelContext: ModelContext) {
        self.visit = visit
        self.child = child
        self.modelContext = modelContext
        
        KBLog.ai.kbDebug("MedicalAIChatViewModel init visitId=\(visit.id) childId=\(child.id)")
    }
    
    // MARK: - Setup
    
    func loadOrCreateConversation() {
        KBLog.ai.kbInfo("loadOrCreateConversation started visitId=\(visit.id)")
        
        Task { @MainActor in
            if loadExistingConversationIfReady() {
                KBLog.ai.kbInfo("Existing conversation fast-loaded, starting silent context refresh")
                
                Task.detached(priority: .background) { [weak self] in
                    await self?.prepareContextSilently()
                }
            } else {
                KBLog.ai.kbInfo("No ready conversation found, preparing full context")
                await prepareContext()
                setupConversation()
            }
        }
    }
    
    @discardableResult
    private func loadExistingConversationIfReady() -> Bool {
        let visitId = visit.id
        let providerRaw = AIProvider.claude.rawValue
        
        KBLog.ai.kbDebug("Trying fast-load conversation visitId=\(visitId) provider=\(providerRaw)")
        
        let descriptor = FetchDescriptor<KBAIConversation>(
            predicate: #Predicate { $0.visitId == visitId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        guard
            let existing = (try? modelContext.fetch(descriptor))?.first(where: { $0.providerRaw == providerRaw }),
            !existing.messages.isEmpty
        else {
            KBLog.ai.kbDebug("Fast-load failed: no non-empty conversation found")
            return false
        }
        
        self.conversation = existing
        self.messages = existing.sortedMessages
        self.isLoadingContext = false
        
        KBLog.ai.kbInfo("Fast-loaded conversation id=\(existing.id) messagesCount=\(existing.messages.count)")
        return true
    }
    
    private func prepareContextSilently() async {
        KBLog.ai.kbDebug("Silent context preparation started visitId=\(visit.id)")
        
        let treatments = fetchTreatments()
        let documents = fetchVisitDocuments()
        
        await MainActor.run {
            self.systemPrompt = MedicalVisitContextBuilder.buildSystemPrompt(
                visit: visit,
                child: child,
                treatments: treatments,
                documents: documents
            )
            
            KBLog.ai.kbInfo("Silent context prepared treatmentsCount=\(treatments.count) documentsCount=\(documents.count) promptLength=\(self.systemPrompt.count)")
        }
    }
    
    private func prepareContext() async {
        KBLog.ai.kbInfo("Full context preparation started visitId=\(visit.id)")
        
        isLoadingContext = true
        defer {
            isLoadingContext = false
            KBLog.ai.kbDebug("Full context preparation ended")
        }
        
        let treatments = fetchTreatments()
        let documents = fetchVisitDocuments()
        
        self.systemPrompt = MedicalVisitContextBuilder.buildSystemPrompt(
            visit: visit,
            child: child,
            treatments: treatments,
            documents: documents
        )
        
        KBLog.ai.kbInfo("Full context prepared treatmentsCount=\(treatments.count) documentsCount=\(documents.count) promptLength=\(systemPrompt.count)")
    }
    
    private func setupConversation() {
        let visitId = visit.id
        let providerRaw = AIProvider.claude.rawValue
        
        KBLog.ai.kbDebug("setupConversation started visitId=\(visitId) provider=\(providerRaw)")
        
        do {
            let descriptor = FetchDescriptor<KBAIConversation>(
                predicate: #Predicate { $0.visitId == visitId },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            
            let existing = try modelContext.fetch(descriptor)
                .first { $0.providerRaw == providerRaw }
            
            if let existing {
                self.conversation = existing
                self.messages = existing.sortedMessages
                
                KBLog.ai.kbInfo("Loaded existing conversation id=\(existing.id) messagesCount=\(existing.messages.count)")
            } else {
                let conv = KBAIConversation(
                    familyId: visit.familyId,
                    childId: visit.childId,
                    visitId: visit.id,
                    provider: .claude
                )
                
                modelContext.insert(conv)
                try modelContext.save()
                
                self.conversation = conv
                self.messages = []
                
                KBLog.ai.kbInfo("Created new conversation id=\(conv.id)")
            }
        } catch {
            KBLog.ai.kbError("setupConversation failed error=\(error.localizedDescription)")
            errorMessage = "Impossibile caricare la conversazione."
        }
    }
    
    // MARK: - Send
    
    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            KBLog.ai.kbDebug("send aborted: empty trimmed text")
            return
        }
        
        guard !isLoading else {
            KBLog.ai.kbDebug("send aborted: already loading")
            return
        }
        
        guard let conversation else {
            KBLog.ai.kbError("send aborted: conversation unavailable")
            errorMessage = "Conversazione non disponibile."
            return
        }
        
        errorMessage = nil
        
        KBLog.ai.kbInfo("send started conversationId=\(conversation.id) currentMessagesCount=\(messages.count) inputLength=\(trimmed.count)")
        
        let userMsg = KBAIMessage(role: .user, content: trimmed)
        conversation.messages.append(userMsg)
        messages.append(userMsg)
        saveContext()
        
        isLoading = true
        defer {
            isLoading = false
            KBLog.ai.kbDebug("send ended isLoading=false")
        }
        
        do {
            try await summarizeIfNeeded(conversation: conversation)
            
            let payloadMessages = buildPayloadMessages(conversation: conversation)
            let finalSystemPrompt = buildFinalSystemPrompt(conversation: conversation)
            
            KBLog.ai.kbDebug("Calling AIService payloadMessagesCount=\(payloadMessages.count) systemPromptLength=\(finalSystemPrompt.count)")
            
            let response = try await AIService.shared.sendMessage(
                messages: payloadMessages,
                systemPrompt: finalSystemPrompt
            )
            
            let replyText = response.reply
            
            KBLog.ai.kbInfo("AIService reply received replyLength=\(replyText.count)")
            
            let assistantMsg = KBAIMessage(role: .assistant, content: replyText)
            conversation.messages.append(assistantMsg)
            messages.append(assistantMsg)
            saveContext()
            
            KBLog.ai.kbInfo("send completed totalMessagesCount=\(messages.count)")
            
        } catch let err as AIServiceError {
            errorMessage = err.localizedDescription
            KBLog.ai.kbError("AIServiceError description=\(err.localizedDescription)")
        } catch {
            errorMessage = "Errore imprevisto: \(error.localizedDescription)"
            KBLog.ai.kbError("Unexpected send error description=\(error.localizedDescription)")
        }
    }
    
    // MARK: - Clear
    
    func clearConversation() {
        guard let conversation else {
            KBLog.ai.kbDebug("clearConversation ignored: no active conversation")
            return
        }
        
        KBLog.ai.kbInfo("clearConversation started conversationId=\(conversation.id) messagesCount=\(conversation.messages.count)")
        
        modelContext.delete(conversation)
        saveContext()
        
        self.conversation = nil
        self.messages = []
        
        KBLog.ai.kbInfo("Conversation cleared, recreating conversation")
        loadOrCreateConversation()
    }
    
    // MARK: - Summary / compaction
    
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
        - richieste principali del genitore
        - diagnosi, raccomandazioni, terapie, cure, esami menzionati
        - farmaci prescritti e relative istruzioni
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
        
        conversation.summary                  = response.reply
        conversation.summaryUpdatedAt         = Date()
        conversation.summarizedMessageCount   = messagesToSummarize.count
        
        try modelContext.save()
        
        KBLog.ai.kbInfo("summarizeIfNeeded updated summary chars=\(response.reply.count)")
        KBLog.ai.kbInfo("summarizeIfNeeded summarizedMessageCount=\(conversation.summarizedMessageCount)")
    }
    
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
            KBAIMessage(id: $0.id, role: $0.role, content: $0.content, createdAt: $0.createdAt)
        }
    }
    
    // MARK: - Private helpers
    
    private func fetchVisitDocuments() -> [KBDocument] {
        let tag = VisitAttachmentTag.make(visit.id)
        let familyId = visit.familyId
        
        KBLog.ai.kbDebug("fetchVisitDocuments started familyId=\(familyId) visitId=\(visit.id)")
        
        let descriptor = FetchDescriptor<KBDocument>(
            predicate: #Predicate<KBDocument> {
                $0.familyId == familyId && $0.isDeleted == false
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let filtered = all.filter { $0.notes == tag }
        
        KBLog.ai.kbInfo("fetchVisitDocuments completed totalDocuments=\(all.count) filteredDocuments=\(filtered.count)")
        
        return filtered
    }
    
    private func fetchTreatments() -> [KBTreatment] {
        guard !visit.linkedTreatmentIds.isEmpty else {
            KBLog.ai.kbDebug("fetchTreatments skipped: no linked treatment ids")
            return []
        }
        
        let ids = visit.linkedTreatmentIds
        
        KBLog.ai.kbDebug("fetchTreatments started linkedIdsCount=\(ids.count)")
        
        let descriptor = FetchDescriptor<KBTreatment>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        
        let treatments = (try? modelContext.fetch(descriptor)) ?? []
        
        KBLog.ai.kbInfo("fetchTreatments completed linkedIdsCount=\(ids.count) fetchedTreatments=\(treatments.count)")
        
        return treatments
    }
    
    private func saveContext() {
        do {
            try modelContext.save()
            KBLog.ai.kbDebug("SwiftData context saved")
        } catch {
            KBLog.ai.kbError("SwiftData save failed error=\(error.localizedDescription)")
        }
    }
}
