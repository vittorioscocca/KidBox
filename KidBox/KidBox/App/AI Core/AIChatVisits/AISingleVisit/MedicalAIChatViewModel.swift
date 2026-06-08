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
    @Published var streamingMessageId: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var inputText: String = ""
    @Published var isLoadingContext: Bool = true
    @Published var actionExecutionSummary: String? = nil
    
    // MARK: - Dependencies
    
    private let visit: KBMedicalVisit
    private let child: KBChild
    private let modelContext: ModelContext
    
    // MARK: - Private state
    
    private var conversation: KBAIConversation?
    private var systemPrompt: String = ""
    private var aiChatChangedCancellable: AnyCancellable?
    
    // MARK: - Summary config
    
    private let compactionThreshold: Double = 0.60
    private var lastCompactionThreshold: Int = 0
    private var usageTodaySnapshot: Int = 0
    private var dailyLimitSnapshot: Int = 0
    
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
        
        subscribeToAIChatSync()
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
    
    /// Ricarica i messaggi quando la sync cross-device aggiorna lo storico.
    private func subscribeToAIChatSync() {
        aiChatChangedCancellable?.cancel()
        aiChatChangedCancellable = SyncCenter.shared.aiChatChanged
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isLoading, self.streamingMessageId == nil else { return }
                let visitId = self.visit.id
                let providerRaw = AIProvider.claude.rawValue
                let descriptor = FetchDescriptor<KBAIConversation>(
                    predicate: #Predicate { $0.visitId == visitId },
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
                guard let convo = (try? self.modelContext.fetch(descriptor))?
                    .first(where: { $0.providerRaw == providerRaw }) else { return }
                self.conversation = convo
                self.messages = convo.sortedMessages
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
            self.systemPrompt = self.withFamilyMemory(
                MedicalVisitContextBuilder.buildSystemPrompt(
                    visit: visit,
                    child: child,
                    treatments: treatments,
                    documents: documents
                )
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
        
        self.systemPrompt = withFamilyMemory(
            MedicalVisitContextBuilder.buildSystemPrompt(
                visit: visit,
                child: child,
                treatments: treatments,
                documents: documents
            )
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
                if existing.summary?.isEmpty == false { lastCompactionThreshold = 3 }
                
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
        SyncCenter.shared.pushAIConversation(conversation, modelContext: modelContext)

        isLoading = true

        do {
            let payloadMessages = buildPayloadMessages(conversation: conversation)
            let finalSystemPrompt = buildFinalSystemPrompt(conversation: conversation)
            
            KBLog.ai.kbDebug("Calling AIService payloadMessagesCount=\(payloadMessages.count) systemPromptLength=\(finalSystemPrompt.count)")
            
            let response = try await AIService.shared.sendMessage(
                messages: payloadMessages,
                systemPrompt: finalSystemPrompt
            )
            usageTodaySnapshot = response.usageToday
            dailyLimitSnapshot = response.dailyLimit
            
            let familyId = child.familyId ?? visit.familyId
            let outcome = await KidBoxAIActionPipeline.processReply(
                response.reply,
                modelContext: modelContext,
                familyId: familyId,
                defaultChildId: child.id,
                pendingGroceryNames: KidBoxAIActionPipeline.fetchPendingGroceryNames(
                    familyId: familyId,
                    modelContext: modelContext
                )
            )
            actionExecutionSummary = outcome.executionSummary
            
            KBLog.ai.kbInfo("AIService reply received replyLength=\(outcome.displayText.count)")
            
            let assistantMsg = KBAIMessage(role: .assistant, content: outcome.displayText)
            conversation.messages.append(assistantMsg)
            isLoading = false
            messages.append(assistantMsg)
            AIChatStreamingDelivery.beginAssistantReveal(
                messageId: assistantMsg.id,
                streamingMessageId: &streamingMessageId
            )
            try await compactIfNeeded(conversation: conversation)
            saveContext()
            SyncCenter.shared.pushAIConversation(conversation, modelContext: modelContext)

            KBLog.ai.kbInfo("send completed totalMessagesCount=\(messages.count)")

        } catch let err as AIServiceError {
            isLoading = false
            errorMessage = err.localizedDescription
            KBLog.ai.kbError("AIServiceError description=\(err.localizedDescription)")
        } catch {
            isLoading = false
            errorMessage = "Errore imprevisto: \(error.localizedDescription)"
            KBLog.ai.kbError("Unexpected send error description=\(error.localizedDescription)")
        }
        KBLog.ai.kbDebug("send ended isLoading=\(isLoading)")
    }

    func finishStreaming(messageId: String) {
        AIChatStreamingDelivery.finishReveal(messageId: messageId, streamingMessageId: &streamingMessageId)
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
        streamingMessageId = nil

        KBLog.ai.kbInfo("Conversation cleared, recreating conversation")
        loadOrCreateConversation()
        // Propaga lo svuotamento agli altri dispositivi (stesso remoteDocId).
        if let convo = self.conversation {
            SyncCenter.shared.pushAIConversation(convo, modelContext: modelContext)
        }
    }
    
    // MARK: - Compaction
    
    private func shouldCompact(messagesInSession: Int, dailyLimit: Int) -> Bool {
        guard dailyLimit > 0 else { return false }
        return Double(messagesInSession) >= Double(dailyLimit) * compactionThreshold
    }
    
    private func compactIfNeeded(conversation: KBAIConversation) async throws {
        guard shouldCompact(messagesInSession: usageTodaySnapshot, dailyLimit: dailyLimitSnapshot) else { return }
        let stepBase = Double(dailyLimitSnapshot) * 0.20
        guard stepBase > 0 else { return }
        let currentThresholdStep = Int(Double(usageTodaySnapshot) / stepBase)
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
        conversation.messages.removeAll()
        conversation.messages.append(compacted)
        conversation.summary = summaryReply.reply
        conversation.summaryUpdatedAt = Date()
        conversation.summarizedMessageCount = 0
        lastCompactionThreshold = currentThresholdStep
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
        KBLog.ai.kbDebug("MedicalAIChatVM: scheduled family memory extract convId=\(conversation.id)")
    }
    
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
        let recentMessages = sorted
            .filter { msg in
                guard let summary else { return true }
                return !(msg.role == .assistant && msg.content == summary)
            }
            .suffix(6)
        KBLog.ai.kbInfo("buildPayloadMessages recentMessages.count=\(recentMessages.count)")
        let payload = ([summaryMessage].compactMap { $0 } + recentMessages.map {
            KBAIMessage(id: $0.id, role: $0.role, content: $0.content, createdAt: $0.createdAt)
        }).prefix(7).map { $0 }
        return payload
    }
    
    private static let compactionSystemPrompt = "Riassumi in modo conciso ma completo la conversazione seguente, mantenendo i punti chiave, le decisioni prese e il contesto importante. Il riassunto sarà usato come contesto per continuare la conversazione."
    
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
