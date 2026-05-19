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
    @Published var streamingMessageId: String?
    @Published var isLoading = false
    @Published var isLoadingContext = false
    @Published var errorMessage: String?
    @Published var usageToday: Int = 0
    @Published var dailyLimit: Int = 0
    @Published var actionExecutionSummary: String? = nil
    /// Unità messaggio stimate per la prossima richiesta (contesto ampio).
    @Published private(set) var estimatedMessageUnits: Int = 1
    /// Costo stimato della domanda con contesto sanitario già riassunto.
    @Published private(set) var estimatedCompactMessageUnits: Int = 1
    /// Costo una tantum per generare il riassunto (0 se già in cache nella sessione).
    @Published private(set) var estimatedCompactSetupUnits: Int = 0
    var hasCompactHealthContextCache: Bool { compactHealthContextCache != nil }
    @Published var contextNoticeToast: String?
    @Published var showContextModeChoice = false
    @Published var pendingSendText = ""
    @Published private(set) var isPreparingCompactContext = false
    
    // MARK: - Private
    
    private let modelContext: ModelContext
    private var conversation: KBAIConversation?
    private var systemPrompt: String = ""
    private var contextPrepared = false
    private var compactHealthContextCache: (fingerprint: Int, summary: String)?
    private var didShowLargeContextNotice = false
    
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
            
            systemPrompt = withFamilyMemory(
                HealthContextBuilder.buildSystemPrompt(
                    subjectName:        subjectName,
                    subjectId:          subjectId,
                    exams:              exams,
                    visits:             visits,
                    treatments:         treatments,
                    vaccines:           vaccines,
                    documentsByExamId:  documentsByExamId,
                    documentsByVisitId: documentsByVisitId
                )
            )
            
            contextPrepared  = true
            isLoadingContext = false
            refreshPayloadCostEstimate(pendingUserText: "")
            Task { await refreshUsage() }
            KBLog.ai.kbInfo("HealthAIChatVM context ready chars=\(systemPrompt.count) units=\(estimatedMessageUnits)")
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
            streamingMessageId = nil
            errorMessage = nil
            compactHealthContextCache = nil
            didShowLargeContextNotice = false
            contextNoticeToast = nil
            refreshPayloadCostEstimate(pendingUserText: "")
            KBLog.ai.kbInfo("HealthAIChatVM clearConversation OK")
        } catch {
            errorMessage = "Non sono riuscito a cancellare la conversazione."
            KBLog.ai.kbError("HealthAIChatVM clearConversation FAILED: \(error)")
        }
    }
    
    func finishStreaming(messageId: String) {
        AIChatStreamingDelivery.finishReveal(messageId: messageId, streamingMessageId: &streamingMessageId)
    }

    func refreshPayloadCostEstimate(pendingUserText: String) {
        guard contextPrepared else { return }
        syncCompactCacheValidity()
        let convo = conversation
        let payload = convo.map { buildPayloadMessages(conversation: $0) } ?? []
        let prompt = convo.map { buildFinalSystemPrompt(conversation: $0) } ?? systemPrompt
        let total = AIAskAIPayload.totalChars(
            systemPrompt: prompt,
            messages: payload,
            pendingUserText: pendingUserText
        )
        let units = AIAskAIPayload.messageUnits(totalChars: total)
        estimatedMessageUnits = units
        estimatedCompactMessageUnits = estimateCompactAskMessageUnits(
            conversation: convo,
            pendingUserText: pendingUserText
        )
        estimatedCompactSetupUnits = estimateCompactSetupMessageUnits()
        presentLargeContextNoticeIfNeeded(isLarge: AIAskAIPayload.isLargeContext(totalChars: total))
    }

    func dismissContextNotice() {
        contextNoticeToast = nil
    }

    private func presentLargeContextNoticeIfNeeded(isLarge: Bool) {
        guard isLarge, !didShowLargeContextNotice else { return }
        didShowLargeContextNotice = true
        let notice = AIAskAIPayload.transientLargeContextNotice()
        contextNoticeToast = notice
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if contextNoticeToast == notice {
                contextNoticeToast = nil
            }
        }
    }

    // MARK: - Send

    func requestSend(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading, !isPreparingCompactContext else { return }
        guard contextPrepared, conversation != nil else {
            if isLoadingContext {
                errorMessage = "Attendi il caricamento del contesto sanitario."
            } else if !contextPrepared {
                loadOrCreateConversation()
                errorMessage = "Contesto sanitario in preparazione. Riprova tra un attimo."
            } else {
                errorMessage = "Conversazione non disponibile."
            }
            return
        }
        refreshPayloadCostEstimate(pendingUserText: trimmed)
        if estimatedMessageUnits > 1 {
            switch AISettings.shared.healthContextSendPreference {
            case .askEachTime:
                pendingSendText = trimmed
                showContextModeChoice = true
                return
            case .fullAccuracy:
                Task { await performSend(text: trimmed, mode: .fullAccuracy) }
                return
            case .compactSummary:
                Task { await performSend(text: trimmed, mode: .compactSummary) }
                return
            }
        }
        Task { await performSend(text: trimmed, mode: .fullAccuracy) }
    }

    func cancelPendingSend() {
        pendingSendText = ""
        showContextModeChoice = false
    }

    func confirmSend(mode: HealthContextSendMode) {
        let text = pendingSendText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSendText = ""
        showContextModeChoice = false
        guard !text.isEmpty else { return }
        AISettings.shared.healthContextSendPreference = HealthContextSendPreference.from(sendMode: mode)
        Task { await performSend(text: text, mode: mode) }
    }

    private func performSend(text: String, mode: HealthContextSendMode) async {
        guard !text.isEmpty, !isLoading else { return }
        guard let conversation else {
            errorMessage = "Conversazione non disponibile."
            return
        }

        errorMessage = nil
        isLoading = true

        do {
            let userMessage = makeMessage(role: .user, text: text)
            userMessage.conversation = conversation
            modelContext.insert(userMessage)
            try modelContext.save()
            messages.append(userMessage)

            let payloadMessages = buildPayloadMessages(conversation: conversation)
            let finalSystemPrompt = try await resolveSystemPrompt(
                for: mode,
                conversation: conversation
            )
            let payloadChars = AIAskAIPayload.totalChars(
                systemPrompt: finalSystemPrompt,
                messages: payloadMessages,
                pendingUserText: ""
            )
            let units = AIAskAIPayload.messageUnits(totalChars: payloadChars)
            KBLog.ai.kbInfo(
                "HealthAIChatVM calling AIService mode=\(mode.rawValue) payload=\(payloadMessages.count) chars=\(payloadChars) units=\(units)"
            )

            let response = try await AIService.shared.sendMessage(
                messages: payloadMessages,
                systemPrompt: finalSystemPrompt
            )
            usageToday = response.usageToday
            dailyLimit = response.dailyLimit
            refreshPayloadCostEstimate(pendingUserText: "")

            let familyId = resolveFamilyId()
            let outcome = await KidBoxAIActionPipeline.processReply(
                response.reply,
                modelContext: modelContext,
                familyId: familyId,
                defaultChildId: subjectId,
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
        } catch {
            isLoading = false
            isPreparingCompactContext = false
            errorMessage = error.localizedDescription
            KBLog.ai.kbError("HealthAIChatVM send FAILED: \(error)")
        }
    }

    private var healthContextFingerprint: Int { systemPrompt.count }

    private func syncCompactCacheValidity() {
        if compactHealthContextCache?.fingerprint != healthContextFingerprint {
            compactHealthContextCache = nil
        }
    }

    private func estimatedCompactSummaryLength() -> Int {
        min(12_000, max(4_000, systemPrompt.count / 6))
    }

    private func estimateCompactAskMessageUnits(
        conversation: KBAIConversation?,
        pendingUserText: String
    ) -> Int {
        syncCompactCacheValidity()
        let payload = conversation.map { buildPayloadMessages(conversation: $0) } ?? []
        let summaryText: String
        if let cache = compactHealthContextCache {
            summaryText = cache.summary
        } else {
            summaryText = String(repeating: "·", count: estimatedCompactSummaryLength())
        }
        let prompt = compactSystemPrompt(
            healthSummary: summaryText,
            conversation: conversation
        )
        let total = AIAskAIPayload.totalChars(
            systemPrompt: prompt,
            messages: payload,
            pendingUserText: pendingUserText
        )
        return AIAskAIPayload.messageUnits(totalChars: total)
    }

    private func estimateCompactSetupMessageUnits() -> Int {
        syncCompactCacheValidity()
        guard compactHealthContextCache == nil else { return 0 }
        return AIAskAIPayload.messageUnits(
            totalChars: systemPrompt.count
                + HealthContextCompaction.summarizationSystemPrompt.count
                + 256
        )
    }

    private func compactSystemPrompt(
        healthSummary: String,
        conversation: KBAIConversation?
    ) -> String {
        var prompt = HealthContextCompaction.buildCompactSystemPrompt(
            summary: healthSummary,
            subjectName: subjectName
        )
        if let s = conversation?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            prompt += "\n\nRIASSUNTO CONVERSAZIONE PRECEDENTE\n\(s)"
        }
        return prompt
    }

    private func resolveSystemPrompt(
        for mode: HealthContextSendMode,
        conversation: KBAIConversation
    ) async throws -> String {
        switch mode {
        case .fullAccuracy:
            return buildFinalSystemPrompt(conversation: conversation)
        case .compactSummary:
            isPreparingCompactContext = true
            defer { isPreparingCompactContext = false }
            let summary = try await compactHealthContextSummary()
            return compactSystemPrompt(healthSummary: summary, conversation: conversation)
        }
    }

    private func compactHealthContextSummary() async throws -> String {
        syncCompactCacheValidity()
        if let cache = compactHealthContextCache {
            return cache.summary
        }
        let response = try await AIService.shared.sendMessage(
            messages: [
                KBAIMessage(
                    role: .user,
                    content: "Comprimi il seguente contesto sanitario:\n\n\(systemPrompt)"
                ),
            ],
            systemPrompt: HealthContextCompaction.summarizationSystemPrompt
        )
        let summary = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            throw AIServiceError.serverError("Impossibile riassumere il contesto sanitario.")
        }
        compactHealthContextCache = (healthContextFingerprint, summary)
        return summary
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
        KBLog.ai.kbDebug("HealthAIChatVM: scheduled family memory extract convId=\(conversation.id)")
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

    private func resolveFamilyId() -> String {
        if !Self.activeFamilyId.isEmpty { return Self.activeFamilyId }
        return exams.first?.familyId
            ?? visits.first?.familyId
            ?? treatments.first?.familyId
            ?? vaccines.first?.familyId
            ?? ""
    }
}
