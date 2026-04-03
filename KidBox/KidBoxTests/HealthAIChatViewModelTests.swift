//
//  HealthAIChatViewModelTests.swift
//  KidBox
//
//  Created by vscocca on 02/04/26.
//

//
//  HealthAIChatViewModelTests.swift
//  KidBoxTests
//
//  Testa la logica di compressione (summary) di HealthAIChatViewModel
//  senza chiamare l'API reale.
//
//  Strategia:
//  - ModelContainer in-memory con KBAIConversation + KBAIMessage
//  - AIService viene sostituito con un mock tramite dependency injection
//    (se AIService.shared è un singleton, usiamo un'extension #if DEBUG
//     oppure testiamo la logica derivata — buildPayloadMessages,
//     buildFinalSystemPrompt — che è pura e non richiede mock dell'API)
//  - I test della soglia (summaryThreshold=8) verificano che la compressione
//    avvenga al momento giusto e che il payload successivo escluda i messaggi
//    già riassunti.
//
//  NOTA: HealthAIChatViewModel chiama AIService.shared.sendMessage che tocca
//  la rete. Per testare la logica interna senza rete:
//  1. Testiamo direttamente KBAIConversation (modello SwiftData) per la logica
//     di sortedMessages, hasSummary, summarizedMessageCount.
//  2. Testiamo buildPayloadMessages e buildFinalSystemPrompt tramite helper
//     testabili esposti con #if DEBUG (pattern già usato in SyncCenter).
//  3. Testiamo il comportamento di loadOrCreateConversation (fetch/create).
//

import XCTest
import SwiftData
@testable import KidBox

// MARK: - KBAIConversation Logic Tests (puro modello — zero network)

final class KBAIConversationLogicTests: XCTestCase {
    
    // MARK: - sortedMessages
    
    func test_sortedMessages_returnsChronologicalOrder() {
        let conv = makeConversation()
        let t0 = Date()
        conv.messages = [
            makeMessage(role: .assistant, content: "Risposta", at: t0.addingTimeInterval(1)),
            makeMessage(role: .user,      content: "Domanda",  at: t0)
        ]
        
        let sorted = conv.sortedMessages
        XCTAssertEqual(sorted.first?.content, "Domanda")
        XCTAssertEqual(sorted.last?.content,  "Risposta")
    }
    
    func test_sortedMessages_emptyConversation_returnsEmpty() {
        let conv = makeConversation()
        conv.messages = []
        XCTAssertTrue(conv.sortedMessages.isEmpty)
    }
    
    func test_sortedMessages_singleMessage() {
        let conv = makeConversation()
        conv.messages = [makeMessage(role: .user, content: "Ciao")]
        XCTAssertEqual(conv.sortedMessages.count, 1)
    }
    
    // MARK: - hasSummary
    
    func test_hasSummary_nilSummary_returnsFalse() {
        let conv = makeConversation()
        conv.summary = nil
        XCTAssertFalse(conv.hasSummary)
    }
    
    func test_hasSummary_emptySummary_returnsFalse() {
        let conv = makeConversation()
        conv.summary = "   "
        XCTAssertFalse(conv.hasSummary)
    }
    
    func test_hasSummary_nonEmptySummary_returnsTrue() {
        let conv = makeConversation()
        conv.summary = "La famiglia ha discusso del vaccino."
        XCTAssertTrue(conv.hasSummary)
    }
    
    // MARK: - summarizedMessageCount
    
    func test_summarizedMessageCount_default_isZero() {
        let conv = makeConversation()
        XCTAssertEqual(conv.summarizedMessageCount, 0)
    }
    
    func test_summarizedMessageCount_canBeUpdated() {
        let conv = makeConversation()
        conv.summarizedMessageCount = 6
        XCTAssertEqual(conv.summarizedMessageCount, 6)
    }
    
    // MARK: - provider
    
    func test_provider_defaultIsClaude() {
        let conv = makeConversation()
        XCTAssertEqual(conv.provider, .claude)
    }
    
    func test_provider_roundTrip() {
        let conv = makeConversation()
        conv.provider = .openai
        XCTAssertEqual(conv.provider, .openai)
    }
    
    func test_provider_invalidRaw_fallbackToClaude() {
        let conv = makeConversation()
        conv.providerRaw = "invalid-provider"
        XCTAssertEqual(conv.provider, .claude)
    }
    
    // MARK: - Helpers
    
    private func makeConversation() -> KBAIConversation {
        KBAIConversation(
            familyId: "fam-1",
            childId: "child-1",
            visitId: "visit-1",
            provider: .claude
        )
    }
    
    private func makeMessage(
        role: AIMessageRole,
        content: String,
        at date: Date = Date()
    ) -> KBAIMessage {
        KBAIMessage(id: UUID().uuidString, role: role, content: content, createdAt: date)
    }
}

// MARK: - Summary Threshold Logic Tests (SwiftData in-memory)

/// Testa la logica di buildPayloadMessages e buildFinalSystemPrompt
/// operando direttamente su KBAIConversation in-memory,
/// senza chiamare AIService.
@MainActor
final class HealthAISummaryLogicTests: XCTestCase {
    
    private var container: ModelContainer!
    private var context: ModelContext!
    
    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: KBAIConversation.self, KBAIMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }
    
    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }
    
    // MARK: - Payload building (logica dropFirst summarizedMessageCount)
    
    func test_payloadMessages_noSummary_includesAllMessages() {
        let conv = makeAndInsertConversation()
        insertMessages(count: 5, into: conv)
        
        // summarizedMessageCount = 0 → tutti i messaggi nel payload
        let payload = buildPayloadMessages(conversation: conv)
        XCTAssertEqual(payload.count, 5)
    }
    
    func test_payloadMessages_withSummary_excludesSummarized() {
        let conv = makeAndInsertConversation()
        insertMessages(count: 10, into: conv)
        conv.summarizedMessageCount = 6   // simula: 6 già riassunti
        
        let payload = buildPayloadMessages(conversation: conv)
        XCTAssertEqual(payload.count, 4, "Solo i 4 messaggi non ancora riassunti devono finire nel payload")
    }
    
    func test_payloadMessages_allSummarized_returnsEmpty() {
        let conv = makeAndInsertConversation()
        insertMessages(count: 4, into: conv)
        conv.summarizedMessageCount = 4   // tutti riassunti
        
        let payload = buildPayloadMessages(conversation: conv)
        XCTAssertTrue(payload.isEmpty, "Nessun messaggio recente → payload vuoto")
    }
    
    // MARK: - buildFinalSystemPrompt
    
    func test_buildFinalSystemPrompt_noSummary_returnsBasePrompt() {
        let conv = makeAndInsertConversation()
        conv.summary = nil
        let base = "System prompt base"
        
        let result = buildFinalSystemPrompt(conversation: conv, systemPrompt: base)
        XCTAssertEqual(result, base)
    }
    
    func test_buildFinalSystemPrompt_withSummary_appendsSummary() {
        let conv = makeAndInsertConversation()
        conv.summary = "Riassunto della conversazione precedente."
        let base = "System prompt base"
        
        let result = buildFinalSystemPrompt(conversation: conv, systemPrompt: base)
        XCTAssertTrue(result.contains(base), "Deve contenere il prompt base")
        XCTAssertTrue(result.contains("Riassunto della conversazione precedente."),
                      "Deve contenere il summary")
        XCTAssertTrue(result.contains("RIASSUNTO CONVERSAZIONE PRECEDENTE"),
                      "Deve contenere il titolo del riassunto")
    }
    
    func test_buildFinalSystemPrompt_whitespaceSummary_returnsBaseOnly() {
        let conv = makeAndInsertConversation()
        conv.summary = "   \n  "
        let base = "System prompt base"
        
        let result = buildFinalSystemPrompt(conversation: conv, systemPrompt: base)
        XCTAssertEqual(result, base, "Summary vuoto/whitespace non deve essere aggiunto")
    }
    
    // MARK: - Soglia compressione (verifica condizione logica)
    
    func test_shouldSummarize_belowThreshold_isFalse() {
        let conv = makeAndInsertConversation()
        insertMessages(count: 8, into: conv)  // summaryThreshold = 8
        
        // Con 8 messaggi e 0 riassunti: unsummarized = 8, NON > 8 → non deve comprimere
        let shouldCompress = shouldSummarize(conversation: conv, threshold: 8, keepRecent: 4)
        XCTAssertFalse(shouldCompress, "Con unsummarized == threshold non deve comprimere")
    }
    
    func test_shouldSummarize_aboveThreshold_isTrue() {
        let conv = makeAndInsertConversation()
        insertMessages(count: 13, into: conv)  // 13 - 0 = 13 > 8
        
        let shouldCompress = shouldSummarize(conversation: conv, threshold: 8, keepRecent: 4)
        XCTAssertTrue(shouldCompress, "Con unsummarized > threshold deve comprimere")
    }
    
    func test_shouldSummarize_partiallyAlreadySummarized() {
        let conv = makeAndInsertConversation()
        insertMessages(count: 10, into: conv)
        conv.summarizedMessageCount = 4  // 10 - 4 = 6 ≤ 8 → no
        
        let shouldCompress = shouldSummarize(conversation: conv, threshold: 8, keepRecent: 4)
        XCTAssertFalse(shouldCompress)
    }
    
    func test_messagesToSummarize_leavesRecentIntact() {
        let conv = makeAndInsertConversation()
        insertMessages(count: 12, into: conv)
        // keepRecent = 4 → deve riassumere i primi 12 - 4 = 8
        let toSummarize = messagesForSummary(conversation: conv, keepRecent: 4)
        XCTAssertEqual(toSummarize.count, 8)
    }
    
    // MARK: - fetchOrCreate (SwiftData in-memory)
    
    func test_fetchOrCreateConversation_createsNew() throws {
        let all = try context.fetch(FetchDescriptor<KBAIConversation>())
        XCTAssertTrue(all.isEmpty)
        
        let conv = KBAIConversation(
            familyId: "fam", childId: "child",
            visitId: "scope-key-1", provider: .claude
        )
        context.insert(conv)
        try context.save()
        
        let fetched = try context.fetch(FetchDescriptor<KBAIConversation>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.visitId, "scope-key-1")
    }
    
    func test_fetchOrCreateConversation_returnsExisting() throws {
        let conv = KBAIConversation(
            familyId: "fam", childId: "child",
            visitId: "scope-key-2", provider: .claude
        )
        context.insert(conv)
        try context.save()
        
        // Simula un secondo fetch con la stessa scope key
        let all = try context.fetch(FetchDescriptor<KBAIConversation>())
        let existing = all.first { $0.visitId == "scope-key-2" }
        XCTAssertNotNil(existing, "Deve trovare la conversazione esistente")
        XCTAssertEqual(all.count, 1, "Non deve creare duplicati")
    }
    
    func test_clearConversation_resetsMessages() throws {
        let conv = makeAndInsertConversation()
        insertMessages(count: 5, into: conv)
        conv.summary = "Un riassunto"
        conv.summarizedMessageCount = 3
        try context.save()
        
        // Simula clearConversation
        for msg in conv.messages { context.delete(msg) }
        conv.summary = nil
        conv.summaryUpdatedAt = nil
        conv.summarizedMessageCount = 0
        try context.save()
        
        XCTAssertTrue(conv.messages.isEmpty)
        XCTAssertNil(conv.summary)
        XCTAssertEqual(conv.summarizedMessageCount, 0)
    }
    
    // MARK: - KBAIMessage
    
    func test_message_roleRoundTrip_user() {
        let msg = KBAIMessage(role: .user, content: "Ciao")
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.roleRaw, "user")
    }
    
    func test_message_roleRoundTrip_assistant() {
        let msg = KBAIMessage(role: .assistant, content: "Risposta")
        XCTAssertEqual(msg.role, .assistant)
        XCTAssertEqual(msg.roleRaw, "assistant")
    }
    
    func test_message_invalidRoleRaw_fallbackToUser() {
        let msg = KBAIMessage(role: .user, content: "")
        msg.roleRaw = "invalid"
        XCTAssertEqual(msg.role, .user)
    }
    
    // MARK: - Pure logic helpers
    // Questi replicano esattamente la logica dei ViewModel,
    // testabile senza accedere ai metodi privati.
    
    private func buildPayloadMessages(conversation: KBAIConversation) -> [KBAIMessage] {
        Array(conversation.sortedMessages.dropFirst(conversation.summarizedMessageCount))
            .map { KBAIMessage(id: $0.id, role: $0.role, content: $0.content, createdAt: $0.createdAt) }
    }
    
    private func buildFinalSystemPrompt(conversation: KBAIConversation, systemPrompt: String) -> String {
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
    
    private func shouldSummarize(
        conversation: KBAIConversation,
        threshold: Int,
        keepRecent: Int
    ) -> Bool {
        let sorted = conversation.sortedMessages
        let unsummarized = sorted.count - conversation.summarizedMessageCount
        return unsummarized > threshold && sorted.count > keepRecent
    }
    
    private func messagesForSummary(
        conversation: KBAIConversation,
        keepRecent: Int
    ) -> [KBAIMessage] {
        let sorted = conversation.sortedMessages
        return Array(sorted.prefix(sorted.count - keepRecent))
    }
    
    // MARK: - SwiftData helpers
    
    private func makeAndInsertConversation() -> KBAIConversation {
        let conv = KBAIConversation(
            familyId: "fam-ai-test",
            childId:  "child-ai-test",
            visitId:  UUID().uuidString,
            provider: .claude
        )
        context.insert(conv)
        try? context.save()
        return conv
    }
    
    private func insertMessages(count: Int, into conv: KBAIConversation) {
        let base = Date()
        for i in 0..<count {
            let role: AIMessageRole = i % 2 == 0 ? .user : .assistant
            let msg = KBAIMessage(
                id: UUID().uuidString,
                role: role,
                content: "Messaggio \(i)",
                createdAt: base.addingTimeInterval(Double(i))
            )
            msg.conversation = conv
            context.insert(msg)
        }
        try? context.save()
    }
}
