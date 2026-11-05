//
//  OnDeviceAssistant.swift
//  KidBox
//
//  Il modello di Apple Intelligence al posto di Claude: senza rete per tutti, e
//  sempre per il Free che ha finito i 5 messaggi. Con la rete Pro e Max, e il
//  Free col bonus ancora da usare, restano su Claude. Solo i documenti del Free
//  partono comunque dal telefono (`shouldReadDocumentOnDevice`).
//
//  Il modello ha 4.096 token in tutto, risposta compresa, e il quaderno di
//  Claude ne vale decine di migliaia: qui entra solo quello che riguarda la
//  domanda. Risponde e basta: niente azioni, che su Claude partono senza
//  conferma, e niente link alle voci.
//

import Foundation
import FoundationModels

enum OnDeviceAI {

    /// Il prototipo è acceso e questo telefono ha il modello pronto.
    static var isAvailable: Bool {
        guard OnDeviceDocumentAnalyzer.isEnabled else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Chi passa dal telefono invece che da Claude.
    static func prefersDevice(modelReady: Bool, bonusFinished: Bool, online: Bool) -> Bool {
        modelReady && (bonusFinished || !online)
    }

    /// I documenti del Free passano sempre prima dal telefono: con 5 messaggi a
    /// vita leggere le bollette li brucerebbe. Se vuole, la scheda rilegge con Claude.
    static func prefersDeviceForDocument(modelReady: Bool, freePlan: Bool, online: Bool) -> Bool {
        modelReady && (freePlan || !online)
    }

    @MainActor
    static func shouldReadDocumentOnDevice() async -> Bool {
        guard isAvailable else { return false }
        return prefersDeviceForDocument(
            modelReady: true,
            freePlan: KBSubscriptionManager.shared.currentPlan == .free,
            online: await DocumentLocalCache.hasNetworkRoute()
        )
    }

    @MainActor
    static func shouldUseDevice() async -> Bool {
        guard isAvailable else { return false }
        return prefersDevice(
            modelReady: true,
            bonusFinished: KBSubscriptionManager.shared.aiAccessBlocked,
            online: await DocumentLocalCache.hasNetworkRoute()
        )
    }
}

enum OnDeviceAssistant {

    struct Turn {
        let isUser: Bool
        let text: String
    }

    enum Failure: LocalizedError {
        case cannotAnswer

        var errorDescription: String? {
            String(localized: "Il telefono non riesce a rispondere a questa domanda.")
        }
    }

    /// Bastano per circa due terzi del modello: resta posto alla risposta.
    private static let contextBudgets = [5000, 2500]
    private static let cardLimit = 1800
    private static let maxReplyTokens = 600
    private static let historyTurns = 4
    private static let turnLimit = 400
    private static let questionLimit = 1000
    /// Sempre dentro: chi è la famiglia e cosa c'è oggi.
    private static let baseCards = ["famiglia.md", "oggi.md"]
    /// Dopo le schede che parlano della domanda, se resta posto.
    private static let dailyCards = ["calendario.md", "todo.md", "spesa.md"]

    static func reply(
        question: String,
        history: [Turn],
        book: AgentMemoryBook,
        focus: AgentFocus?
    ) async throws -> String {
        let prompt = conversation(question: question, history: history)
        for (attempt, budget) in contextBudgets.enumerated() {
            // Ogni sessione ricorda i suoi turni: un tentativo nuovo ne vuole una nuova.
            let model = LanguageModelSession(instructions: instructions())
            let cards = context(book: book, focus: focus, question: question, budget: budget)
            do {
                let response = try await model.respond(
                    to: "\(cards)\n\n\(prompt)",
                    options: GenerationOptions(temperature: 0.3, maximumResponseTokens: maxReplyTokens)
                )
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw Failure.cannotAnswer }
                return text
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                KBLog.ai.kbInfo("Assistente sul telefono: contesto troppo lungo, tentativo=\(attempt)")
            } catch is Failure {
                throw Failure.cannotAnswer
            } catch {
                // Filtri di Apple, lingua non capita, modello occupato.
                KBLog.ai.kbInfo("Assistente sul telefono: \(error.localizedDescription)")
                throw Failure.cannotAnswer
            }
        }
        throw Failure.cannotAnswer
    }

    /// Prima la famiglia, poi la persona del focus, le schede che parlano della
    /// domanda e quelle di ogni giorno, finché c'è budget.
    static func context(book: AgentMemoryBook, focus: AgentFocus?, question: String, budget: Int) -> String {
        let terms = AgentRelevance.terms(from: question)
        let files = book.files.filter { $0.name != AgentMemoryBook.tailFile }
        let focusName = focus.map { AgentMemoryBookBuilder.healthFileName(for: $0.personName) }

        let matching = files
            .map { file in (file, score(file, terms: terms)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0.name)
        var names = baseCards + [focusName].compactMap { $0 } + matching + dailyCards
        var seen = Set<String>()
        names = names.filter { seen.insert($0).inserted }

        var left = budget
        var out: [String] = []
        for name in names {
            guard left > 0, let file = files.first(where: { $0.name == name }) else { continue }
            let body = clipped(file.body, terms: terms, limit: min(cardLimit, left))
            guard !body.isEmpty else { continue }
            out.append("[\(file.title)]\n\(body)")
            left -= body.count
        }
        return out.joined(separator: "\n\n")
    }

    private static func score(_ file: AgentMemoryFile, terms: Set<String>) -> Int {
        let title = AgentRelevance.fold(file.title)
        let body = AgentRelevance.fold(file.body)
        return terms.reduce(0) { acc, term in
            if title.contains(term) { return acc + 3 }
            return body.contains(term) ? acc + 1 : acc
        }
    }

    /// Prima le righe che parlano della domanda, poi quelle in cima alla scheda;
    /// si rileggono nell'ordine in cui stanno.
    static func clipped(_ body: String, terms: Set<String>, limit: Int) -> String {
        guard body.count > limit else { return body }
        let lines = body.components(separatedBy: .newlines)
        let relevant = lines.indices.filter { index in
            let line = AgentRelevance.fold(lines[index])
            return terms.contains(where: line.contains)
        }
        var left = limit
        var kept = Set<Int>()
        for index in relevant + Array(lines.indices) where !kept.contains(index) {
            let cost = lines[index].count + 1
            guard cost <= left else { continue }
            kept.insert(index)
            left -= cost
        }
        return kept.sorted().map { lines[$0] }.joined(separator: "\n")
    }

    private static func conversation(question: String, history: [Turn]) -> String {
        let turns = history.suffix(historyTurns).map { turn in
            "\(turn.isUser ? "User" : "You"): \(String(turn.text.prefix(turnLimit)))"
        }
        return (turns + ["User: \(String(question.prefix(questionLimit)))"]).joined(separator: "\n")
    }

    private static func instructions() -> String {
        let language: String
        switch kbDeviceLocale().language.languageCode?.identifier {
        case "en": language = "English"
        case "fr": language = "French"
        case "es": language = "Spanish"
        default:   language = "Italian"
        }
        let today = Date().formatted(.iso8601.year().month().day())
        return """
        You answer questions about a family using only their notes. Today is \(today).
        Start directly with the answer: no greeting, no family name, no closing remark.
        Copy names, values, dates and amounts exactly as they are in the notes. An asterisk marks a value outside its range.
        If the answer is not in the notes, say only that it is not among the data on this phone.
        Health: state what the notes say in simple words, then suggest asking the doctor. Give no new diagnosis.
        You can only read: if the user asks to add, change or delete something, say that you cannot do it from here. Do not mention sections of the app.
        Reply in \(language), in at most three sentences.
        """
    }
}
