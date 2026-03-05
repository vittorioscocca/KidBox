//
//  MedicalAIChatViewModel.swift
//  KidBox
//

import Foundation
import SwiftData
import OSLog
import Combine
/// ViewModel for the AI medical chat session.
///
/// Hybrid flow:
/// - First message (with images): calls Anthropic directly via `AnthropicDirectService`
/// - Subsequent messages (text only): calls Firebase Function via `AIService`
@MainActor
final class MedicalAIChatViewModel: ObservableObject {
    
    // MARK: - Published
    
    @Published var messages:         [KBAIMessage] = []
    @Published var isLoading:        Bool          = false
    @Published var errorMessage:     String?       = nil
    @Published var inputText:        String        = ""
    @Published var isLoadingContext: Bool          = true
    
    // MARK: - Dependencies
    
    private let visit:        KBMedicalVisit
    private let child:        KBChild
    private let modelContext: ModelContext
    private let log = Logger(subsystem: "com.kidbox", category: "ai_chat")
    
    // MARK: - Private state
    
    private var conversation:    KBAIConversation?
    private var systemPrompt:    String = ""
    private var cachedImages:    [VisitImageLoader.EncodedImage] = []
    private var contextSentOnce: Bool = false
    
    // MARK: - Init
    
    init(visit: KBMedicalVisit, child: KBChild, modelContext: ModelContext) {
        self.visit        = visit
        self.child        = child
        self.modelContext = modelContext
    }
    
    // MARK: - Setup
    
    func loadOrCreateConversation() {
        Task { @MainActor in
            if loadExistingConversationIfReady() {
                Task.detached(priority: .background) { [weak self] in
                    await self?.prepareContextSilently()
                }
            } else {
                await prepareContext()
                setupConversation()
            }
        }
    }
    
    /// Carica una conversazione esistente con messaggi senza mostrare il loading.
    /// Restituisce true se trovata, false se non esiste ancora.
    @discardableResult
    private func loadExistingConversationIfReady() -> Bool {
        let visitId     = visit.id
        let providerRaw = AIProvider.claude.rawValue
        let descriptor  = FetchDescriptor<KBAIConversation>(
            predicate: #Predicate { $0.visitId == visitId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard
            let existing = (try? modelContext.fetch(descriptor))?.first(where: { $0.providerRaw == providerRaw }),
            !existing.messages.isEmpty
        else { return false }
        
        self.conversation     = existing
        self.messages         = existing.sortedMessages
        self.contextSentOnce  = true
        self.isLoadingContext  = false
        objectWillChange.send()
        log.debug("AI chat: fast-loaded existing conversation id=\(existing.id)")
        return true
    }
    
    /// Aggiorna system prompt e immagini in background senza mostrare loading.
    /// Usato per tenere il contesto aggiornato nelle riaperture successive.
    private func prepareContextSilently() async {
        Task.detached { VisitImageLoader.clearStaleCache(olderThanDays: 30) }
        
        let treatments = fetchTreatments()
        let photoURLs  = fetchVisitPhotoURLs()
        let images     = await VisitImageLoader.loadImages(from: photoURLs)
        
        await MainActor.run {
            self.cachedImages = images
            self.systemPrompt = MedicalVisitContextBuilder.buildSystemPrompt(
                visit:      visit,
                child:      child,
                treatments: treatments
            )
            log.debug("AI chat: silent context refresh done, images=\(images.count)")
        }
    }
    
    private func prepareContext() async {
        isLoadingContext = true
        defer { isLoadingContext = false }
        
        Task.detached { VisitImageLoader.clearStaleCache(olderThanDays: 30) }
        
        // Trattamenti servono sempre per il system prompt
        let treatments = fetchTreatments()
        log.debug("AI chat: fetched \(treatments.count) treatments")
        
        // Controlla se esiste già una conversazione con messaggi
        // Se sì, le immagini sono già state inviate — non serve ricaricarle
        let hasExistingConversation = checkHasExistingConversation()
        
        if !hasExistingConversation {
            let photoURLs = fetchVisitPhotoURLs()
            log.debug("AI chat: found \(photoURLs.count) photo URLs from KBDocument")
            let images = await VisitImageLoader.loadImages(from: photoURLs)
            self.cachedImages = images
            log.debug("AI chat: loaded \(images.count) images")
        } else {
            log.debug("AI chat: existing conversation — skipping image load")
        }
        
        self.systemPrompt = MedicalVisitContextBuilder.buildSystemPrompt(
            visit:      visit,
            child:      child,
            treatments: treatments
        )
    }
    
    /// Controlla se esiste già una conversazione con messaggi per questa visita.
    /// Usato per evitare di ricaricare le immagini inutilmente.
    private func checkHasExistingConversation() -> Bool {
        let visitId     = visit.id
        let providerRaw = AIProvider.claude.rawValue
        let descriptor  = FetchDescriptor<KBAIConversation>(
            predicate: #Predicate { $0.visitId == visitId }
        )
        let existing = (try? modelContext.fetch(descriptor))?.first { $0.providerRaw == providerRaw }
        return !(existing?.messages.isEmpty ?? true)
    }
    
    /// Legge le foto della visita da KBDocument usando lo stesso tag di VisitAttachmentTag
    private func fetchVisitPhotoURLs() -> [String] {
        let tag = VisitAttachmentTag.make(visit.id)
        let descriptor = FetchDescriptor<KBDocument>(
            predicate: #Predicate<KBDocument> { $0.notes == tag }
        )
        let docs = (try? modelContext.fetch(descriptor)) ?? []
        return docs
            .filter { !$0.isDeleted }
            .compactMap { doc in
                if let url = doc.downloadURL, !url.isEmpty { return url }
                if let local = doc.localFileURL { return local.absoluteString }
                return nil
            }
    }
    
    private func setupConversation() {
        let visitId     = visit.id
        let providerRaw = AIProvider.claude.rawValue
        
        do {
            let descriptor = FetchDescriptor<KBAIConversation>(
                predicate: #Predicate {
                    $0.visitId == visitId
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let existing = try modelContext.fetch(descriptor)
                .first { $0.providerRaw == providerRaw }
            
            if let existing {
                self.conversation    = existing
                self.messages        = existing.sortedMessages
                self.contextSentOnce = !existing.messages.isEmpty
                log.debug("AI chat: loaded existing conversation id=\(existing.id)")
            } else {
                let conv = KBAIConversation(
                    familyId: visit.familyId,
                    childId:  visit.childId,
                    visitId:  visit.id,
                    provider: .claude
                )
                modelContext.insert(conv)
                try modelContext.save()
                self.conversation    = conv
                self.messages        = []
                self.contextSentOnce = false
                log.info("AI chat: created new conversation id=\(conv.id)")
            }
        } catch {
            log.error("AI chat: setupConversation failed: \(error.localizedDescription)")
            errorMessage = "Impossibile caricare la conversazione."
        }
    }
    
    // MARK: - Send
    
    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }
        guard let conversation else {
            errorMessage = "Conversazione non disponibile."
            return
        }
        
        errorMessage = nil
        
        let userMsg = KBAIMessage(role: .user, content: trimmed)
        conversation.messages.append(userMsg)
        messages.append(userMsg)
        saveContext()
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let replyText: String
            
            if !contextSentOnce && !cachedImages.isEmpty {
                // Prima domanda CON immagini → chiama Anthropic direttamente
                log.info("AI chat: sending with \(self.cachedImages.count) images via direct API")
                replyText = try await AnthropicDirectService.shared.sendInitialContext(
                    systemPrompt: systemPrompt,
                    userText:     trimmed,
                    images:       cachedImages
                )
                contextSentOnce = true
                
            } else {
                // Prima domanda senza immagini o messaggi successivi → Firebase Function
                log.debug("AI chat: sending via Firebase Function")
                let response = try await AIService.shared.sendMessage(
                    messages:     messages,
                    systemPrompt: systemPrompt
                )
                replyText       = response.reply
                contextSentOnce = true
            }
            
            let assistantMsg = KBAIMessage(role: .assistant, content: replyText)
            conversation.messages.append(assistantMsg)
            messages.append(assistantMsg)
            saveContext()
            
        } catch let err as AIServiceError {
            errorMessage = err.localizedDescription
            log.error("AI chat: AIServiceError \(err.localizedDescription)")
        } catch {
            errorMessage = "Errore imprevisto: \(error.localizedDescription)"
            log.error("AI chat: unexpected error \(error.localizedDescription)")
        }
    }
    
    // MARK: - Clear
    
    func clearConversation() {
        guard let conversation else { return }
        modelContext.delete(conversation)
        saveContext()
        self.conversation    = nil
        self.messages        = []
        self.contextSentOnce = false
        loadOrCreateConversation()
    }
    
    // MARK: - Private helpers
    
    private func fetchTreatments() -> [KBTreatment] {
        guard !visit.linkedTreatmentIds.isEmpty else { return [] }
        let ids = visit.linkedTreatmentIds
        let descriptor = FetchDescriptor<KBTreatment>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            log.error("AI chat: save failed \(error.localizedDescription)")
        }
    }
}
