//
//  PlanningAIChatViewModel.swift
//  KidBox
//
//  L'assistente unico di KidBox: si apre dalla Home e, con un focus, dai
//  pulsanti di Salute (persona, visite, singola visita, esami).
//
//  - Il contesto è il quaderno di schede (`AgentMemoryBook`), ricostruito dai
//    dati locali a ogni domanda: il ViewModel non riceve più i dati dalla view.
//  - Una sola conversazione per famiglia (`planning-agent-{familyId}`),
//    sincronizzata fra i dispositivi come le chat Salute.
//  - Quaderno più grande di un messaggio: stessa scelta della chat Salute
//    (`healthContextSendPreference`); la versione ridotta non costa un riassunto.
//
//  Disegno in `internal/assistente-unico.md`.
//

import Foundation
import SwiftData
import Combine
import FirebaseAuth

@MainActor
final class PlanningAIChatViewModel: ObservableObject {

    // MARK: - Published

    @Published var messages: [KBAIMessage] = []
    @Published var streamingMessageId: String?
    @Published var isLoading = false
    @Published var isLoadingContext = false
    @Published var errorMessage: String? = nil
    @Published var inputText = ""
    @Published var actionExecutionSummary: String? = nil
    /// Messaggi il cui blocco `KIDBOX_ACTIONS` è già stato eseguito — niente card duplicate.
    @Published private(set) var autoExecutedMessageIds: Set<String> = []
    /// Da dove si è aperto l'assistente (Salute); `nil` = dalla Home.
    @Published var focus: AgentFocus?
    /// Messaggi usati e tetto, per il contatore sopra il campo di testo
    /// (nil finché il server non risponde).
    @Published private(set) var quota: AssistantQuota?

    // Scelta «accurata / ridotta» quando il quaderno non sta in un messaggio.
    @Published var showContextModeChoice = false
    @Published private(set) var pendingSendText = ""
    @Published private(set) var choiceFullUnits = 1
    @Published private(set) var choiceReducedUnits = 1

    /// Ultimo snapshot letto: serve alle card d'azione della view.
    @Published private(set) var snapshot: AgentMemorySnapshot?

    // MARK: - Identity

    let familyId: String
    let familyName: String

    var openTodos: [KBTodoItem] { snapshot?.openTodos ?? [] }
    var visitsWithNextDate: [KBMedicalVisit] { snapshot?.visitsWithNextDate ?? [] }
    var activeTreatments: [KBTreatment] { snapshot?.activeTreatments ?? [] }
    var children: [KBChild] { snapshot?.children ?? [] }
    var pendingGroceryItems: [KBGroceryItem] { snapshot?.pendingGrocery ?? [] }

    // MARK: - Private

    private let modelContext: ModelContext
    private var conversation: KBAIConversation?
    private var contextPrepared = false
    private var pendingPlan: ContextPlan?
    private var aiChatChangedCancellable: AnyCancellable?

    private let compactionThreshold: Double = 0.60
    private var lastCompactionThreshold: Int = 0
    private var usageTodaySnapshot: Int = 0
    private var dailyLimitSnapshot: Int = 0
    /// Periodo della quota (`lifetime` = bonus Free); nil finché il server non risponde.
    private var quotaPeriodSnapshot: AIQuotaPeriod?

    /// Documenti da far leggere (OCR) a ogni apertura: pochi, perché ogni
    /// lettura parte subito in parallelo. Alle aperture successive tocca agli altri.
    private static let extractionBatchSize = 5
    /// Margine sotto i 50.000 caratteri di un messaggio, per le righe di contorno.
    private static let unitSafetyMargin = 1_500

    /// Scope key stabile — una sola conversazione per famiglia.
    /// NON include hash dei dati: il contesto cambia ad ogni apertura
    /// (nuovi eventi, to-do, cure) ma la conversazione deve persistere.
    private var scopeId: String {
        "planning-agent-\(familyId)"
    }

    // MARK: - Init

    init(familyId: String, familyName: String, focus: AgentFocus? = nil, modelContext: ModelContext) {
        self.familyId = familyId
        self.familyName = familyName
        self.focus = focus
        self.modelContext = modelContext
        KBLog.ai.kbInfo("PlanningAIChatVM init familyId=\(familyId) focus=\(focus?.label ?? "-")")
    }

    // MARK: - Load

    func loadOrCreateConversation() async {
        guard !isLoadingContext else { return }
        isLoadingContext = true
        errorMessage = nil
        defer { isLoadingContext = false }

        do {
            let convo = try fetchOrCreateConversation()
            conversation = convo
            messages = convo.sortedMessages
            if convo.summary?.isEmpty == false { lastCompactionThreshold = 3 }

            let snap = AgentMemorySnapshot.load(familyId: familyId, familyName: familyName, modelContext: modelContext)
            snapshot = snap
            enqueuePendingExtractions(snapshot: snap)
            subscribeToAIChatSync()
            // Quanti messaggi restano: decide se il contesto ridotto parte da solo.
            Task { [weak self] in
                guard let usage = try? await AIService.shared.fetchUsage() else { return }
                self?.usageTodaySnapshot = usage.usageToday
                self?.dailyLimitSnapshot = usage.dailyLimit
                self?.quotaPeriodSnapshot = usage.period
                self?.quota = AssistantQuota(
                    used: usage.usageToday,
                    limit: usage.dailyLimit,
                    period: usage.period,
                    monthlyUsed: usage.monthlyUsage,
                    monthlyLimit: usage.monthlyLimit
                )
            }

            contextPrepared = true
            KBLog.ai.kbInfo("PlanningAIChatVM ready docs=\(snap.documents.count) events=\(snap.events.count) facts=\(snap.memoryFacts.count)")
        } catch {
            errorMessage = NSLocalizedString("Impossibile preparare il contesto di pianificazione.", comment: "Assistant load error")
            KBLog.ai.kbError("PlanningAIChatVM loadOrCreate error: \(error)")
        }
    }

    /// Inietta il briefing AI come messaggio assistente (es. tap notifica mattutina).
    /// Con `force: true` inserisce anche se la conversazione ha già messaggi (salta solo duplicati identici).
    func injectInitialAssistantMessageIfNeeded(_ text: String, force: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let conversation else {
            KBLog.ai.kbDebug("PlanningAIChatVM inject skipped: no conversation")
            return
        }
        if !force && !messages.isEmpty {
            KBLog.ai.kbDebug("PlanningAIChatVM inject skipped: messages not empty")
            return
        }
        if messages.contains(where: {
            $0.role == .assistant &&
            $0.content.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }) {
            KBLog.ai.kbDebug("PlanningAIChatVM inject skipped: duplicate briefing")
            return
        }

        let assistant = makeMessage(role: .assistant, text: trimmed)
        assistant.conversation = conversation
        conversation.messages.append(assistant)
        messages.append(assistant)
        try? modelContext.save()
        SyncCenter.shared.pushAIConversation(conversation, modelContext: modelContext)
        KBLog.ai.kbInfo("PlanningAIChatVM injected briefing chars=\(trimmed.count) force=\(force)")
    }

    func finishStreaming(messageId: String) {
        AIChatStreamingDelivery.finishReveal(messageId: messageId, streamingMessageId: &streamingMessageId)
    }

    func clearFocus() {
        focus = nil
    }

    // MARK: - Send

    func send() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading, contextPrepared, conversation != nil else { return }
        inputText = ""
        errorMessage = nil

        let plan = prepareContext(question: trimmed)
        guard let reduced = plan.reducedPrompt, plan.fullUnits > 1 else {
            await performSend(text: trimmed, systemPrompt: plan.fullPrompt, mode: "full")
            return
        }
        if mustUseReduced(fullUnits: plan.fullUnits) {
            await performSend(text: trimmed, systemPrompt: reduced, mode: "reduced-auto")
            return
        }
        switch AISettings.shared.healthContextSendPreference {
        case .askEachTime:
            pendingPlan = plan
            pendingSendText = trimmed
            choiceFullUnits = plan.fullUnits
            choiceReducedUnits = plan.reducedUnits
            showContextModeChoice = true
        case .fullAccuracy:
            await performSend(text: trimmed, systemPrompt: plan.fullPrompt, mode: "full")
        case .compactSummary:
            await performSend(text: trimmed, systemPrompt: reduced, mode: "reduced")
        }
    }

    /// Contesto ridotto senza chiedere, qualunque sia la preferenza: sul Free,
    /// dove i messaggi sono 5 in tutto, e sugli altri piani quando il completo
    /// costerebbe più dei messaggi rimasti (il server lo rifiuterebbe per intero).
    /// Stessa regola su Android e web.
    private func mustUseReduced(fullUnits: Int) -> Bool {
        let period = quotaPeriodSnapshot ?? (KBSubscriptionManager.shared.currentPlan == .free ? .lifetime : nil)
        if period == .lifetime { return true }
        guard dailyLimitSnapshot > 0 else { return false }
        return dailyLimitSnapshot - usageTodaySnapshot < fullUnits
    }

    /// Scelta dal dialogo: diventa la preferenza, come nella chat Salute.
    func confirmSend(mode: HealthContextSendMode) {
        guard let plan = pendingPlan else { return }
        let text = pendingSendText
        pendingPlan = nil
        pendingSendText = ""
        showContextModeChoice = false
        guard !text.isEmpty else { return }

        let preference = HealthContextSendPreference.from(sendMode: mode)
        AISettings.shared.healthContextSendPreference = preference
        Task {
            try? await NotificationManager.shared.setHealthContextSendPreference(preference)
            switch mode {
            case .fullAccuracy:
                await performSend(text: text, systemPrompt: plan.fullPrompt, mode: "full")
            case .compactSummary:
                await performSend(text: text, systemPrompt: plan.reducedPrompt ?? plan.fullPrompt, mode: "reduced")
            }
        }
    }

    /// Annullato: la domanda torna nel campo, non si perde.
    func cancelPendingSend() {
        if !pendingSendText.isEmpty, inputText.isEmpty {
            inputText = pendingSendText
        }
        pendingPlan = nil
        pendingSendText = ""
        showContextModeChoice = false
    }

    private func performSend(text: String, systemPrompt: AgentSystemPrompt, mode: String) async {
        guard let conversation else {
            errorMessage = NSLocalizedString("Conversazione non inizializzata.", comment: "Assistant error")
            return
        }
        KBLog.ai.kbInfo("PlanningAIChatVM send start mode=\(mode) messagesCount=\(messages.count) inputLength=\(text.count)")

        let userMessage = makeMessage(role: .user, text: text)
        conversation.messages.append(userMessage)
        messages.append(userMessage)
        try? modelContext.save()
        SyncCenter.shared.pushAIConversation(conversation, modelContext: modelContext)

        isLoading = true
        do {
            let payloadMessages = buildPayloadMessages(conversation: conversation)
            KBLog.ai.kbDebug("PlanningAIChatVM calling AIService payloadCount=\(payloadMessages.count) promptChars=\(systemPrompt.count)")

            let response = try await AIService.shared.sendMessage(
                messages: payloadMessages,
                systemPrompt: systemPrompt.volatile,
                systemPromptStable: systemPrompt.stable,
                systemPromptTail: systemPrompt.tail,
                purpose: "familyAgent"
            )
            // Con il focus di Salute vale come la vecchia chat Salute: la serie
            // dell'evento resta confrontabile con quella di prima.
            AppAnalytics.aiMessageSent(
                agentType: focus == nil ? "assistente" : "salute",
                plan: KBSubscriptionManager.shared.currentPlan.rawValue
            )

            let outcome = await KidBoxAIActionPipeline.processReply(
                response.reply,
                modelContext: modelContext,
                familyId: familyId,
                defaultChildId: defaultChildId,
                pendingGroceryNames: pendingGroceryItems.map(\.name)
            )
            let assistantMessage = makeMessage(role: .assistant, text: outcome.displayText)
            conversation.messages.append(assistantMessage)
            isLoading = false
            messages.append(assistantMessage)
            AIChatStreamingDelivery.beginAssistantReveal(
                messageId: assistantMessage.id,
                streamingMessageId: &streamingMessageId
            )
            actionExecutionSummary = outcome.executionSummary
            if outcome.didAutoExecute {
                autoExecutedMessageIds.insert(assistantMessage.id)
            }

            // Il mese avanza di quanto è avanzato il periodo (giorno o prova):
            // la risposta porta solo quello, `getAIUsage` lo rilegge alla
            // prossima apertura. Un giorno nuovo riparte da zero.
            let previous = quota
            let advanced = response.usageToday >= usageTodaySnapshot
                ? response.usageToday - usageTodaySnapshot
                : response.usageToday
            usageTodaySnapshot = response.usageToday
            dailyLimitSnapshot = response.dailyLimit
            quotaPeriodSnapshot = response.period
            quota = AssistantQuota(
                used: response.usageToday,
                limit: response.dailyLimit,
                period: response.period,
                monthlyUsed: min(previous?.monthlyLimit ?? 0, (previous?.monthlyUsed ?? 0) + advanced),
                monthlyLimit: previous?.monthlyLimit ?? 0
            )

            try await compactIfNeeded(conversation: conversation)
            try? modelContext.save()
            SyncCenter.shared.pushAIConversation(conversation, modelContext: modelContext)

            KBLog.ai.kbInfo("PlanningAIChatVM send done replyChars=\(response.reply.count) units=\(response.messageUnitsConsumed) usage=\(response.usageToday)/\(response.dailyLimit)")
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            KBLog.ai.kbError("PlanningAIChatVM send FAILED: \(error)")
        }
    }

    /// Il figlio a cui attribuire un to-do creato dall'assistente: quello del
    /// focus se è un figlio, altrimenti il primo (come prima dell'unificazione).
    private var defaultChildId: String? {
        if let focus, children.contains(where: { $0.id == focus.personId }) {
            return focus.personId
        }
        return children.first?.id
    }

    // MARK: - Context

    private struct ContextPlan {
        let fullPrompt: AgentSystemPrompt
        let fullUnits: Int
        /// `nil` se la versione completa sta già in un messaggio.
        let reducedPrompt: AgentSystemPrompt?
        let reducedUnits: Int
    }

    /// Quaderno completo e, se non sta in un messaggio, quello ridotto per
    /// questa domanda.
    private func prepareContext(question: String) -> ContextPlan {
        let snap = AgentMemorySnapshot.load(familyId: familyId, familyName: familyName, modelContext: modelContext)
        snapshot = snap
        let builder = AgentMemoryBookBuilder(snapshot: snap)
        let history = conversation.map { buildPayloadMessages(conversation: $0) } ?? []

        let fullPrompt = AgentPrompt.systemPrompt(familyName: familyName, book: builder.build(docAllowance: nil), focus: focus)
        let fullChars = AIAskAIPayload.totalChars(systemPromptChars: fullPrompt.count, messages: history, pendingUserText: question)
        let fullUnits = AIAskAIPayload.messageUnits(totalChars: fullChars)
        guard fullUnits > 1 else {
            KBLog.ai.kbInfo("PlanningAIChatVM context full chars=\(fullChars) units=1")
            return ContextPlan(fullPrompt: fullPrompt, fullUnits: 1, reducedPrompt: nil, reducedUnits: 1)
        }

        // Ridotto: si misura lo scheletro (tutti i testi a zero) e si divide il
        // resto del messaggio fra i documenti, i più utili per primi.
        let textDocs = builder.textDocuments()
        let zero = Dictionary(textDocs.map { ($0.doc.id, 0) }, uniquingKeysWith: { a, _ in a })
        let skeleton = AgentPrompt.systemPrompt(familyName: familyName, book: builder.build(docAllowance: zero), focus: focus)
        let skeletonChars = AIAskAIPayload.totalChars(systemPromptChars: skeleton.count, messages: history, pendingUserText: question)
        // Di solito lo scheletro sta in un messaggio e il ridotto costa 1. Se già
        // lo scheletro non ci sta (02/10/2026: una famiglia con 30 esami e 88
        // documenti, 50.449 caratteri senza un rigo di testo letto), il ridotto
        // paga i messaggi che servono allo scheletro e li riempie di testi.
        let target = AIAskAIPayload.messageUnits(totalChars: skeletonChars + Self.unitSafetyMargin) * AIAskAIPayload.standardChars
            - Self.unitSafetyMargin
        let personNames = Dictionary(
            (snap.children.map { ($0.id, $0.name) } + snap.members.compactMap { m in m.displayName.map { (m.userId, $0) } }),
            uniquingKeysWith: { a, _ in a }
        )
        var reducedPrompt: AgentSystemPrompt?
        var reducedChars = 0

        // Base + appendice: nelle schede ogni testo ha una base che dipende solo
        // dai dati, uguale per ogni domanda, così resta nella cache; i testi
        // scelti per la domanda vanno in coda, in domanda.md. Misurato il
        // 05/10/2026: col budget diviso per domanda le due domande condividevano
        // 2.165 caratteri e la cache non serviva mai. Stesso giro su Android e web.
        if let base = AgentContextFitter.baseAllowances(
            textDocuments: textDocs,
            stableChars: skeleton.stable.count,
            unitSafetyMargin: Self.unitSafetyMargin
        ) {
            let withBase = AgentPrompt.systemPrompt(familyName: familyName, book: builder.build(docAllowance: base), focus: focus)
            var budget = target
                - AIAskAIPayload.totalChars(systemPromptChars: withBase.count, messages: history, pendingUserText: question)
                - AgentContextFitter.appendixOverhead
            var attempt = 0
            while budget >= 0 && attempt < 3 {
                attempt += 1
                let appendix = AgentContextFitter.allowances(
                    textDocuments: textDocs,
                    question: question,
                    focus: focus,
                    focusItemTags: focusItemTags,
                    personNames: personNames,
                    availableChars: budget,
                    targetedOnly: true,
                    floor: base
                )
                let prompt = AgentPrompt.systemPrompt(
                    familyName: familyName,
                    book: builder.build(docAllowance: base, appendix: appendix),
                    focus: focus
                )
                reducedPrompt = prompt
                reducedChars = AIAskAIPayload.totalChars(systemPromptChars: prompt.count, messages: history, pendingUserText: question)
                if reducedChars <= target || budget == 0 { break }
                budget = max(0, budget - (reducedChars - target))
            }
            if reducedChars > target { reducedPrompt = nil }
        }

        // Senza spazio per la base (storico lungo, scheletro enorme): il budget
        // si divide per domanda come prima, e la parte dei testi esce dalla cache.
        if reducedPrompt == nil {
            var available = max(0, target - skeletonChars)
            reducedPrompt = skeleton
            reducedChars = skeletonChars
            // Il contorno stimato per documento non basta quando un allegato ha molte
            // righe (ognuna indentata): se sfora, lo sforamento esce dal budget e si
            // ridistribuisce. Stesso giro su Android e web.
            for _ in 0..<3 {
                let allowance = AgentContextFitter.allowances(
                    textDocuments: textDocs,
                    question: question,
                    focus: focus,
                    focusItemTags: focusItemTags,
                    personNames: personNames,
                    availableChars: available
                )
                let prompt = AgentPrompt.systemPrompt(familyName: familyName, book: builder.build(docAllowance: allowance), focus: focus)
                reducedPrompt = prompt
                reducedChars = AIAskAIPayload.totalChars(systemPromptChars: prompt.count, messages: history, pendingUserText: question)
                if reducedChars <= target || available == 0 { break }
                available = max(0, available - (reducedChars - target))
            }
        }
        let reducedUnits = AIAskAIPayload.messageUnits(totalChars: reducedChars)
        KBLog.ai.kbInfo("PlanningAIChatVM context full chars=\(fullChars) units=\(fullUnits) reduced chars=\(reducedChars) units=\(reducedUnits) docs=\(textDocs.count)")
        // Un ridotto che costa quanto il completo non è una scelta: si manda il completo.
        guard reducedUnits < fullUnits else {
            return ContextPlan(fullPrompt: fullPrompt, fullUnits: fullUnits, reducedPrompt: nil, reducedUnits: fullUnits)
        }
        return ContextPlan(fullPrompt: fullPrompt, fullUnits: fullUnits, reducedPrompt: reducedPrompt, reducedUnits: reducedUnits)
    }

    /// Tag degli allegati della visita o dell'esame del focus: passano interi.
    private var focusItemTags: Set<String> {
        switch focus?.scope {
        case .visit(let id)?: return ["visit:\(id)"]
        case .exam(let id)?: return [ExamAttachmentTag.make(id)]
        default: return []
        }
    }

    /// Mette in coda la lettura (OCR) dei documenti mai letti, i più recenti per
    /// primi. Mai i documenti d'identità del Wallet: il loro testo non deve
    /// finire da nessuna parte.
    private func enqueuePendingExtractions(snapshot snap: AgentMemorySnapshot) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let pending = snap.documents.filter { doc in
            guard doc.notes?.hasPrefix(KBWalletDocumentKind.notesPrefix) != true else { return false }
            guard doc.extractionStatus == .none || (doc.extractionStatus == .pending && !doc.hasExtractedText) else { return false }
            guard doc.isPDFDocument || doc.isImageDocument else { return false }
            return doc.localFileURL != nil
        }
        for doc in pending.prefix(Self.extractionBatchSize) {
            DocumentTextExtractionCoordinator.shared.enqueueExtraction(for: doc, updatedBy: uid, modelContext: modelContext)
        }
        if !pending.isEmpty {
            KBLog.ai.kbInfo("PlanningAIChatVM enqueued OCR \(min(pending.count, Self.extractionBatchSize))/\(pending.count)")
        }
    }

    // MARK: - Clear

    func clearConversation() {
        guard let conversation else { return }
        KBLog.ai.kbInfo("PlanningAIChatVM clearConversation id=\(conversation.id)")
        conversation.messages.removeAll()
        conversation.summary = nil
        conversation.summaryUpdatedAt = nil
        conversation.summarizedMessageCount = 0
        try? modelContext.save()
        SyncCenter.shared.pushAIConversation(conversation, modelContext: modelContext)
        messages = []
        streamingMessageId = nil
        autoExecutedMessageIds = []
    }

    // MARK: - Sync

    /// Ricarica i messaggi quando la sync porta lo storico scritto da un altro
    /// dispositivo (web, Android, un altro iPhone).
    private func subscribeToAIChatSync() {
        aiChatChangedCancellable?.cancel()
        aiChatChangedCancellable = SyncCenter.shared.aiChatChanged
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isLoading, self.streamingMessageId == nil else { return }
                do {
                    let convo = try self.fetchOrCreateConversation()
                    self.conversation = convo
                    self.messages = convo.sortedMessages
                    KBLog.ai.kbDebug("PlanningAIChatVM messages reloaded after aiChat sync count=\(self.messages.count)")
                } catch {
                    KBLog.ai.kbError("PlanningAIChatVM reload after aiChat sync FAILED: \(error)")
                }
            }
    }

    // MARK: - Persistence helpers

    private func fetchOrCreateConversation() throws -> KBAIConversation {
        let sid = scopeId
        let all = try modelContext.fetch(FetchDescriptor<KBAIConversation>())
        if let existing = all.first(where: { $0.visitId == sid }) {
            KBLog.ai.kbInfo("PlanningAIChatVM found existing conv id=\(existing.id)")
            return existing
        }
        let newConvo = KBAIConversation(
            familyId: familyId,
            childId: familyId,
            visitId: sid,
            provider: .claude
        )
        modelContext.insert(newConvo)
        try modelContext.save()
        KBLog.ai.kbInfo("PlanningAIChatVM created new conv id=\(newConvo.id)")
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

        let convoId = conversation.id
        let fid = familyId
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
        KBLog.ai.kbDebug("FamilyMemoryService: scheduled extract after compaction convId=\(convoId)")
    }

    // MARK: - Payload building

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

/// Messaggi AI usati e rimasti, per il contatore dell'assistente: il periodo
/// della quota (oggi, prova o bonus Free) e, sui piani a pagamento e nella
/// prova, il tetto del mese.
struct AssistantQuota: Equatable {
    let used: Int
    let limit: Int
    let period: AIQuotaPeriod
    let monthlyUsed: Int
    let monthlyLimit: Int

    var isNearLimit: Bool { limit > 0 && used >= Int(Double(limit) * 0.8) }
    /// Il mese compare solo quando si avvicina: prima sarebbe rumore.
    var showsMonth: Bool { monthlyLimit > 0 && monthlyUsed >= Int(Double(monthlyLimit) * 0.8) }
}
