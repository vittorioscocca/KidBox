//
//  PlanningAIChatViewModel.swift
//  KidBox
//
//  ViewModel for the family planning AI agent.
//  Mirrors the architecture of HealthAIChatViewModel:
//  - Builds a PlanningContextInput from SwiftData objects passed by the caller.
//  - Persists the conversation via KBAIConversation / KBAIMessage.
//  - Compresses old messages with summary when threshold is reached.
//
//  The caller (view) is responsible for fetching the raw SwiftData objects
//  and passing them in the initialiser — this ViewModel does not own queries.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class PlanningAIChatViewModel: ObservableObject {
    
    // MARK: - Published
    
    @Published var messages:        [KBAIMessage] = []
    @Published var isLoading:       Bool          = false
    @Published var isLoadingContext: Bool         = false
    @Published var errorMessage:    String?       = nil
    @Published var inputText:       String        = ""
    
    // MARK: - Input data (injected by the view)
    
    let familyId:   String
    let familyName: String
    
    // Planning data
    let memberNames:            [String: String]
    let horizonDays:            Int
    let calendarEvents:         [KBCalendarEvent]
    let openTodos:              [KBTodoItem]
    let activeRoutines:         [KBRoutine]
    let todayChecks:            Set<String>
    let childNames:             [String: String]
    let activeTreatments:       [KBTreatment]
    let visitsWithNextDate:     [KBMedicalVisit]
    let visitsWithPendingExams: [KBMedicalVisit]
    let upcomingVaccines:       [KBVaccine]
    
    // ── Memoria famiglia ─────────────────────────────────────────
    let recentNotes:          [KBNote]
    let recentExpenses:       [KBExpense]
    let expenseCategoryNames: [String: String]
    let pendingGroceryItems:  [KBGroceryItem]
    let recentChatMessages:   [KBChatMessage]
    
    // ── Pediatria avanzata ────────────────────────────────────────
    let children:          [KBChild]
    let pediatricProfiles: [String: KBPediatricProfile]
    let allVisits:         [KBMedicalVisit]
    let allExams:          [KBMedicalExam]
    let allVaccines:       [KBVaccine]
    
    // Alias pubblici usati dal PlanningActionParser nella view
    // per abbinare oggetti SwiftData alle action cards di reminder.
    var todosForParser:    [KBTodoItem]     { openTodos }
    var visitsForParser:   [KBMedicalVisit] { visitsWithNextDate }
    var treatmentsForParser:[KBTreatment]   { activeTreatments }
    
    // MARK: - Private
    
    private let modelContext: ModelContext
    private var conversation: KBAIConversation?
    private var systemPrompt: String = ""
    private var contextPrepared = false
    
    private let summaryThreshold               = 8
    private let recentMessagesToKeepAfterSummary = 4
    
    /// Scope key stabile — una sola conversazione per famiglia.
    /// NON include hash dei dati: il contesto cambia ad ogni apertura
    /// (nuovi eventi, to-do, cure) ma la conversazione deve persistere.
    private var scopeId: String {
        "planning-agent-\(familyId)"
    }
    
    // MARK: - Init
    
    init(
        familyId:               String,
        familyName:             String,
        memberNames:            [String: String]  = [:],
        horizonDays:            Int               = 14,
        calendarEvents:         [KBCalendarEvent] = [],
        openTodos:              [KBTodoItem]      = [],
        activeRoutines:         [KBRoutine]       = [],
        todayChecks:            Set<String>       = [],
        childNames:             [String: String]  = [:],
        activeTreatments:       [KBTreatment]     = [],
        visitsWithNextDate:     [KBMedicalVisit]  = [],
        visitsWithPendingExams: [KBMedicalVisit]  = [],
        upcomingVaccines:       [KBVaccine]       = [],
        recentNotes:            [KBNote]          = [],
        recentExpenses:         [KBExpense]       = [],
        expenseCategoryNames:   [String: String]  = [:],
        pendingGroceryItems:    [KBGroceryItem]   = [],
        recentChatMessages:     [KBChatMessage]   = [],
        children:               [KBChild]         = [],
        pediatricProfiles:      [String: KBPediatricProfile] = [:],
        allVisits:              [KBMedicalVisit]  = [],
        allExams:               [KBMedicalExam]   = [],
        allVaccines:            [KBVaccine]       = [],
        modelContext:           ModelContext
    ) {
        self.familyId               = familyId
        self.familyName             = familyName
        self.memberNames            = memberNames
        self.horizonDays            = horizonDays
        self.calendarEvents         = calendarEvents
        self.openTodos              = openTodos
        self.activeRoutines         = activeRoutines
        self.todayChecks            = todayChecks
        self.childNames             = childNames
        self.activeTreatments       = activeTreatments
        self.visitsWithNextDate     = visitsWithNextDate
        self.visitsWithPendingExams = visitsWithPendingExams
        self.upcomingVaccines       = upcomingVaccines
        self.recentNotes            = recentNotes
        self.recentExpenses         = recentExpenses
        self.expenseCategoryNames   = expenseCategoryNames
        self.pendingGroceryItems    = pendingGroceryItems
        self.recentChatMessages     = recentChatMessages
        self.children               = children
        self.pediatricProfiles      = pediatricProfiles
        self.allVisits              = allVisits
        self.allExams               = allExams
        self.allVaccines            = allVaccines
        self.modelContext           = modelContext
        
        KBLog.ai.kbInfo("""
        PlanningAIChatVM init \
        familyId=\(familyId) \
        horizonDays=\(horizonDays) \
        events=\(calendarEvents.count) \
        todos=\(openTodos.count) \
        routines=\(activeRoutines.count) \
        treatments=\(activeTreatments.count)
        """)
    }
    
    // MARK: - Load
    
    func loadOrCreateConversation() {
        guard !isLoadingContext else { return }
        isLoadingContext = true
        errorMessage     = nil
        
        do {
            let convo    = try fetchOrCreateConversation()
            conversation = convo
            messages     = convo.sortedMessages
            
            systemPrompt = PlanningContextBuilder.buildSystemPrompt(
                input: PlanningContextInput(
                    familyName:             familyName,
                    memberNames:            memberNames,
                    horizonDays:            horizonDays,
                    calendarEvents:         calendarEvents,
                    openTodos:              openTodos,
                    activeRoutines:         activeRoutines,
                    todayChecks:            todayChecks,
                    childNames:             childNames,
                    activeTreatments:       activeTreatments,
                    visitsWithNextDate:     visitsWithNextDate,
                    visitsWithPendingExams: visitsWithPendingExams,
                    upcomingVaccines:       upcomingVaccines,
                    recentNotes:            recentNotes,
                    recentExpenses:         recentExpenses,
                    expenseCategoryNames:   expenseCategoryNames,
                    pendingGroceryItems:    pendingGroceryItems,
                    recentChatMessages:     recentChatMessages,
                    children:               children,
                    pediatricProfiles:      pediatricProfiles,
                    allVisits:              allVisits,
                    allExams:               allExams,
                    allVaccines:            allVaccines
                )
            )
            
            contextPrepared  = true
            isLoadingContext = false
            KBLog.ai.kbInfo("PlanningAIChatVM context ready chars=\(systemPrompt.count)")
        } catch {
            isLoadingContext = false
            errorMessage     = "Impossibile preparare il contesto di pianificazione."
            KBLog.ai.kbError("PlanningAIChatVM loadOrCreate error: \(error)")
        }
    }
    
    // MARK: - Send
    
    func send() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading, contextPrepared else { return }
        
        guard let conversation else {
            errorMessage = "Conversazione non inizializzata."
            return
        }
        
        inputText    = ""
        errorMessage = nil
        
        KBLog.ai.kbInfo("PlanningAIChatVM send start messagesCount=\(messages.count) inputLength=\(trimmed.count)")
        
        let userMessage = makeMessage(role: .user, text: trimmed)
        conversation.messages.append(userMessage)
        messages.append(userMessage)
        try? modelContext.save()
        
        isLoading = true
        
        do {
            try await summarizeIfNeeded(conversation: conversation)
            
            let payloadMessages   = buildPayloadMessages(conversation: conversation)
            let finalSystemPrompt = buildFinalSystemPrompt(conversation: conversation)
            
            KBLog.ai.kbDebug("PlanningAIChatVM calling AIService payloadCount=\(payloadMessages.count) promptChars=\(finalSystemPrompt.count)")
            
            let response = try await AIService.shared.sendMessage(
                messages:     payloadMessages,
                systemPrompt: finalSystemPrompt
            )
            
            let assistantMessage = makeMessage(role: .assistant, text: response.reply)
            conversation.messages.append(assistantMessage)
            messages.append(assistantMessage)
            try? modelContext.save()
            
            KBLog.ai.kbInfo("PlanningAIChatVM send done replyChars=\(response.reply.count) usage=\(response.usageToday)/\(response.dailyLimit)")
            
            isLoading = false
        } catch {
            isLoading    = false
            errorMessage = error.localizedDescription
            KBLog.ai.kbError("PlanningAIChatVM send FAILED: \(error)")
        }
    }
    
    // MARK: - Clear
    
    func clearConversation() {
        guard let conversation else { return }
        KBLog.ai.kbInfo("PlanningAIChatVM clearConversation id=\(conversation.id)")
        conversation.messages.removeAll()
        conversation.summary                  = nil
        conversation.summaryUpdatedAt         = nil
        conversation.summarizedMessageCount   = 0
        try? modelContext.save()
        messages = []
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
            childId:  familyId,
            visitId:  sid,
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
    
    // MARK: - Summary compression
    
    private func summarizeIfNeeded(conversation: KBAIConversation) async throws {
        let sorted        = conversation.sortedMessages
        let unsummarized  = sorted.count - conversation.summarizedMessageCount
        
        KBLog.ai.kbInfo("PlanningAIChatVM summarizeIfNeeded unsummarized=\(unsummarized)")
        
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
        - richieste di pianificazione dell'utente
        - eventi, to-do o scadenze discussi
        - proposte accettate o rifiutate dall'utente
        - eventuali preferenze o vincoli emersi
        Non aggiungere nulla di nuovo.
        """
        
        KBLog.ai.kbInfo("PlanningAIChatVM summarize calling AIService toSummarize=\(toSummarize.count)")
        
        let response = try await AIService.shared.sendMessage(
            messages:     [KBAIMessage(role: .user, content: transcript)],
            systemPrompt: summarySystemPrompt
        )
        
        conversation.summary                  = response.reply
        conversation.summaryUpdatedAt         = Date()
        conversation.summarizedMessageCount   = toSummarize.count
        try modelContext.save()
        
        KBLog.ai.kbInfo("PlanningAIChatVM summary updated chars=\(response.reply.count)")
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
