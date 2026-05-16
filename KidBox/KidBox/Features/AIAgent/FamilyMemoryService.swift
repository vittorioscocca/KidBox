//
//  FamilyMemoryService.swift
//  KidBox
//
//  Estrae e persiste fatti narrativi dalle conversazioni del planning agent.
//

import Foundation
import SwiftData

@MainActor
final class FamilyMemoryService {

    static let shared = FamilyMemoryService()
    private init() {}

    private static let maxFactsPerFamily = 25
    private static let dedupePrefixWordCount = 6

    private let memoryFactRemoteStore = MemoryFactRemoteStore()
    private var firestoreLoadedFamilyIds = Set<String>()

    private static let extractionSystemPrompt = """
    Sei un estrattore di memoria familiare per KidBox.
    Analizza la conversazione e estrai SOLO fatti DURATURI sulla famiglia \
    (abitudini, preferenze, problemi ricorrenti, relazioni, stili di vita).

    REGOLE:
    - Max 8 fatti, ognuno su una riga separata nel formato: [categoria] fatto
    - Categorie valide: salute, abitudini, preferenze, scuola, relazioni, casa, wallet, animali, altro
    - Ogni fatto: max 20 parole, in italiano, terza persona.
    - IGNORA: eventi one-time, dati già in SwiftData (visite, farmaci, calendari), \
    informazioni temporanee, dati oggettivi già strutturati.
    - INCLUDI: pattern comportamentali, preferenze espresse, osservazioni narrative, \
    cose dette in modo informale dall'utente che rivelano la famiglia.
    - Per 'casa': includi solo pattern ricorrenti (elettrodomestici problematici, \
    abitudini di manutenzione), NON interventi one-time.
    - Per 'wallet': includi pattern di spesa, priorità dichiarate, budget abituali.
    - Per 'animali': includi salute cronica, preferenze veterinarie, abitudini.
    - Se non ci sono fatti duraturi, rispondi esattamente: NESSUN_FATTO
    """

    // MARK: - Extract & store

    /// Estrae fatti dalla conversazione (tipicamente subito prima/dopo la compaction).
    /// Passa `transcriptMessages` se i messaggi originali sono già stati sostituiti dal summary.
    func extractAndStore(
        from conversation: KBAIConversation,
        familyId: String,
        modelContext: ModelContext,
        transcriptMessages: [KBAIMessage]? = nil
    ) async {
        guard AISettings.shared.isEnabled else {
            KBLog.ai.kbDebug("FamilyMemoryService: AI disabled, skip extract")
            return
        }
        guard !familyId.isEmpty else { return }

        let source = transcriptMessages ?? conversation.sortedMessages
        let transcript = buildTranscript(from: source)
        guard !transcript.isEmpty else {
            KBLog.ai.kbDebug("FamilyMemoryService: empty transcript, skip extract")
            return
        }

        KBLog.ai.kbInfo("FamilyMemoryService: extract start familyId=\(familyId) convId=\(conversation.id)")

        do {
            let response = try await AIService.shared.sendMessage(
                messages: [KBAIMessage(role: .user, content: transcript)],
                systemPrompt: Self.extractionSystemPrompt
            )

            let parsed = parseExtractedFacts(response.reply)
            guard !parsed.isEmpty else {
                KBLog.ai.kbDebug("FamilyMemoryService: no facts parsed")
                return
            }

            let existing = try fetchAllFacts(for: familyId, modelContext: modelContext)
            let existingKeys = Set(existing.map { dedupeKey(for: $0.content) })

            var toInsert: [(MemoryFactCategory, String)] = []
            for (category, content) in parsed {
                let key = dedupeKey(for: content)
                guard !key.isEmpty, !existingKeys.contains(key) else { continue }
                var duplicate = false
                for item in toInsert where dedupeKey(for: item.1) == key {
                    duplicate = true
                    break
                }
                guard !duplicate else { continue }
                toInsert.append((category, content))
            }

            guard !toInsert.isEmpty else {
                KBLog.ai.kbDebug("FamilyMemoryService: all facts deduped")
                return
            }

            try trimOldestIfNeeded(
                familyId: familyId,
                modelContext: modelContext,
                additionalCount: toInsert.count
            )

            var insertedFacts: [KBMemoryFact] = []
            for (category, content) in toInsert {
                let fact = KBMemoryFact(
                    familyId: familyId,
                    content: content,
                    category: category,
                    sourceConversationId: conversation.id
                )
                modelContext.insert(fact)
                insertedFacts.append(fact)
            }
            try modelContext.save()

            syncFactsToFirestore(facts: insertedFacts, familyId: familyId)

            KBLog.ai.kbInfo("FamilyMemoryService: stored \(insertedFacts.count) new facts familyId=\(familyId)")
        } catch {
            KBLog.ai.kbError("FamilyMemoryService: extract failed \(error.localizedDescription)")
        }
    }

    // MARK: - Firestore

    /// Consente un nuovo pull Firestore dopo logout o cambio account.
    func clearFirestoreLoadCache() {
        firestoreLoadedFamilyIds.removeAll()
    }

    /// Scarica i fatti remoti e inserisce in SwiftData solo quelli con `id` non ancora presenti.
    func loadFactsFromFirestore(familyId: String, modelContext: ModelContext) async {
        guard !familyId.isEmpty else { return }
        if firestoreLoadedFamilyIds.contains(familyId) { return }
        firestoreLoadedFamilyIds.insert(familyId)

        KBLog.ai.kbInfo("FamilyMemoryService: Firestore load start familyId=\(familyId)")

        do {
            let remote = try await memoryFactRemoteStore.fetchAll(familyId: familyId)
            let localIds = Set(try fetchAllFacts(for: familyId, modelContext: modelContext).map(\.id))

            var inserted = 0
            for dto in remote {
                guard !localIds.contains(dto.id) else { continue }
                let category = MemoryFactCategory(rawValue: dto.categoryRaw) ?? .altro
                let fact = KBMemoryFact(
                    id: dto.id,
                    familyId: dto.familyId,
                    content: dto.content,
                    category: category,
                    sourceConversationId: dto.sourceConversationId,
                    createdAt: dto.createdAt ?? Date(),
                    updatedAt: dto.updatedAt ?? dto.createdAt ?? Date()
                )
                modelContext.insert(fact)
                inserted += 1
            }

            if inserted > 0 {
                try trimOldestIfNeeded(
                    familyId: familyId,
                    modelContext: modelContext,
                    additionalCount: 0
                )
                try modelContext.save()
            }

            KBLog.ai.kbInfo(
                "FamilyMemoryService: Firestore load OK familyId=\(familyId) inserted=\(inserted) remote=\(remote.count)"
            )
        } catch {
            firestoreLoadedFamilyIds.remove(familyId)
            KBLog.ai.kbError(
                "FamilyMemoryService: Firestore load failed familyId=\(familyId) \(error.localizedDescription)"
            )
        }
    }

    private func syncFactsToFirestore(facts: [KBMemoryFact], familyId: String) {
        guard !facts.isEmpty, !familyId.isEmpty else { return }
        let dtos = facts.map { RemoteMemoryFactDTO(from: $0) }
        Task.detached(priority: .utility) {
            let store = MemoryFactRemoteStore()
            for dto in dtos {
                do {
                    try await store.upsert(dto: dto)
                } catch {
                    KBLog.ai.kbError(
                        "FamilyMemoryService: Firestore sync failed factId=\(dto.id) \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    // MARK: - Fetch

    func fetchFacts(for familyId: String, modelContext: ModelContext) -> [KBMemoryFact] {
        guard !familyId.isEmpty else { return [] }
        do {
            let fid = familyId
            var descriptor = FetchDescriptor<KBMemoryFact>(
                predicate: #Predicate { $0.familyId == fid },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            descriptor.fetchLimit = Self.maxFactsPerFamily
            return try modelContext.fetch(descriptor)
        } catch {
            KBLog.ai.kbError("FamilyMemoryService: fetch failed \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Transcript

    private func buildTranscript(from messages: [KBAIMessage]) -> String {
        let dialog = messages.filter {
            !$0.isSummary && ($0.role == .user || $0.role == .assistant)
        }
        let last = dialog.suffix(20)
        guard !last.isEmpty else { return "" }

        return last.map { msg in
            let label = msg.role == .user ? "Utente" : "Assistente"
            return "\(label): \(msg.content)"
        }.joined(separator: "\n\n")
    }

    // MARK: - Parsing

    private func parseExtractedFacts(_ raw: String) -> [(MemoryFactCategory, String)] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased() == "NESSUN_FATTO" { return [] }

        var out: [(MemoryFactCategory, String)] = []
        for line in trimmed.components(separatedBy: .newlines) {
            let row = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !row.isEmpty else { continue }
            guard let parsed = parseFactLine(row) else { continue }
            out.append(parsed)
            if out.count >= 8 { break }
        }
        return out
    }

    private func parseFactLine(_ line: String) -> (MemoryFactCategory, String)? {
        guard line.first == "[", let close = line.firstIndex(of: "]") else { return nil }
        let categoryPart = line[line.index(after: line.startIndex)..<close]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let contentStart = line.index(after: close)
        let content = line[contentStart...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        guard let category = MemoryFactCategory(rawValue: categoryPart) else { return nil }
        return (category, content)
    }

    // MARK: - Dedup & limits

    private func dedupeKey(for content: String) -> String {
        content
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(Self.dedupePrefixWordCount)
            .joined(separator: " ")
    }

    private func fetchAllFacts(for familyId: String, modelContext: ModelContext) throws -> [KBMemoryFact] {
        let fid = familyId
        let descriptor = FetchDescriptor<KBMemoryFact>(
            predicate: #Predicate { $0.familyId == fid },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func trimOldestIfNeeded(
        familyId: String,
        modelContext: ModelContext,
        additionalCount: Int
    ) throws {
        let existing = try fetchAllFacts(for: familyId, modelContext: modelContext)
        let overflow = existing.count + additionalCount - Self.maxFactsPerFamily
        guard overflow > 0 else { return }
        for fact in existing.prefix(overflow) {
            modelContext.delete(fact)
        }
        KBLog.ai.kbDebug("FamilyMemoryService: trimmed \(overflow) oldest facts")
    }
}
