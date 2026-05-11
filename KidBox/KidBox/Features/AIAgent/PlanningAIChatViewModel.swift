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
    let recentDocuments:      [KBDocument]
    let recentWalletTickets:  [KBWalletTicket]
    
    // ── Pediatria avanzata ────────────────────────────────────────
    let children:          [KBChild]
    let pediatricProfiles: [String: KBPediatricProfile]
    let allVisits:         [KBMedicalVisit]
    let allExams:          [KBMedicalExam]
    let allVaccines:       [KBVaccine]
    
    let pets:              [KBPet]
    let petEvents:         [KBPetEvent]
    let homeItems:         [KBHomeItem]
    let vehicles:          [KBVehicle]
    let vehicleEvents:     [KBVehicleEvent]
    
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
    
    private let compactionThreshold: Double = 0.60
    private var lastCompactionThreshold: Int = 0
    private var usageTodaySnapshot: Int = 0
    private var dailyLimitSnapshot: Int = 0
    
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
        recentDocuments:        [KBDocument]      = [],
        recentWalletTickets:    [KBWalletTicket]  = [],
        children:               [KBChild]         = [],
        pediatricProfiles:      [String: KBPediatricProfile] = [:],
        allVisits:              [KBMedicalVisit]  = [],
        allExams:               [KBMedicalExam]   = [],
        allVaccines:            [KBVaccine]       = [],
        pets:                   [KBPet]           = [],
        petEvents:              [KBPetEvent]      = [],
        homeItems:              [KBHomeItem]      = [],
        vehicles:               [KBVehicle]       = [],
        vehicleEvents:          [KBVehicleEvent]  = [],
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
        self.recentDocuments        = recentDocuments
        self.recentWalletTickets    = recentWalletTickets
        self.children               = children
        self.pediatricProfiles      = pediatricProfiles
        self.allVisits              = allVisits
        self.allExams               = allExams
        self.allVaccines            = allVaccines
        self.pets                   = pets
        self.petEvents              = petEvents
        self.homeItems              = homeItems
        self.vehicles               = vehicles
        self.vehicleEvents          = vehicleEvents
        self.modelContext           = modelContext
        
        KBLog.ai.kbInfo("""
        PlanningAIChatVM init \
        familyId=\(familyId) \
        horizonDays=\(horizonDays) \
        events=\(calendarEvents.count) \
        todos=\(openTodos.count) \
        routines=\(activeRoutines.count) \
        treatments=\(activeTreatments.count) \
        docs=\(recentDocuments.count) \
        wallet=\(recentWalletTickets.count) \
        pets=\(pets.count) homeItems=\(homeItems.count) vehicles=\(vehicles.count)
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
            if convo.summary?.isEmpty == false { lastCompactionThreshold = 3 }
            
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
                    recentDocuments:        recentDocuments,
                    recentWalletTickets:    recentWalletTickets,
                    pets:                   pets,
                    petEvents:              petEvents,
                    homeItems:              homeItems,
                    vehicles:               vehicles,
                    vehicleEvents:          vehicleEvents,
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
            usageTodaySnapshot = response.usageToday
            dailyLimitSnapshot = response.dailyLimit
            
            try await compactIfNeeded(conversation: conversation)
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
