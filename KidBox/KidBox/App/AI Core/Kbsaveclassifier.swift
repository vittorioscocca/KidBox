//
//  KBSaveClassifier.swift
//  KidBox • KBShare  ← aggiungi ENTRAMBI i target in Xcode → Target Membership
//
//  Classificazione intelligente del contenuto condiviso:
//
//  1. iOS 18.1+ con Apple Intelligence → FoundationModels on-device LLM (attivo)
//  2. iOS 18.1+ senza Apple Intelligence → euristica italiana potenziata (fallback)
//  3. iOS < 18.1 → euristica italiana potenziata
//
//  Requisiti Xcode:
//  - Aggiungi "FoundationModels" framework al target (KidBox + KidBoxShareExtension)
//  - Il device deve avere Apple Intelligence abilitata (iPhone 15 Pro+ / iPad M1+, iOS 18.1+)
//

import Foundation
import FoundationModels

// MARK: - Destinazioni

public enum KBShareDestination: String, CaseIterable, Identifiable, Sendable {
    case chat, document, todo, grocery, event, note
    public var id: Self { self }
}

// MARK: - Azione concreta (con payload)

public enum KBSaveAction: Identifiable, Sendable {
    case todo(title: String)
    case event(title: String, date: Date?)
    case grocery(lines: [String])
    case note(title: String, body: String)
    case document(mediaURL: String, fileName: String)
    
    public var id: String {
        switch self {
        case .todo:     return "todo"
        case .event:    return "event"
        case .grocery:  return "grocery"
        case .note:     return "note"
        case .document: return "document"
        }
    }
}

// MARK: - Risultato classificazione

public struct KBClassificationResult: Sendable {
    public let actions: [KBSaveAction]
    public let detectedDate: Date?
    public let isAIClassified: Bool
}

// MARK: - Classifier

public actor KBSaveClassifier {
    
    public static let shared = KBSaveClassifier()
    private init() {}
    
    // MARK: - Public API
    
    public func classify(text: String) async -> KBClassificationResult {
        if #available(iOS 18.1, *) {
            if let result = try? await classifyWithFoundationModels(text: text) {
                return result
            }
        }
        return classifyWithHeuristics(text: text)
    }
    
    public nonisolated func classify(mediaURL: String, mimeHint: KBMediaHint) -> KBClassificationResult {
        let action: KBSaveAction
        switch mimeHint {
        case .image:             action = .document(mediaURL: mediaURL, fileName: "foto.jpg")
        case .video:             action = .document(mediaURL: mediaURL, fileName: "video.mp4")
        case .generic(let name): action = .document(mediaURL: mediaURL, fileName: name)
        }
        return KBClassificationResult(actions: [action], detectedDate: nil, isAIClassified: false)
    }
    
    // MARK: - 1. Foundation Models (iOS 18.1+)
    
    @available(iOS 18.1, *)
    private func classifyWithFoundationModels(text: String) async throws -> KBClassificationResult {
        let session = LanguageModelSession()
        let response = try await session.respond(to: buildPrompt(text))
        return try parseAIResponse(response.content, originalText: text)
    }
    
    // MARK: - Prompt
    
    private func buildPrompt(_ text: String) -> String {
        """
        Sei un assistente per un'app di famiglia italiana. Analizza il testo e \
        restituisci SOLO JSON valido, senza markdown, senza spiegazioni.
        
        Schema esatto:
        {
          "destinations": ["todo"|"event"|"grocery"|"note"],
          "detectedDate": "<ISO8601 oppure null>"
        }
        
        Regole (ordina per rilevanza, la più pertinente prima):
        - "todo"    → compito, attività, cosa da fare, promemoria, \
                      "devo", "dobbiamo", "ricordati", "non dimenticare"
        - "event"   → contiene data o ora, appuntamento, riunione, scadenza, \
                      "domani", "venerdì", "prossima settimana"
        - "grocery" → lista spesa, prodotti alimentari, ingredienti, \
                      "comprare", "al super", latte, pane, uova, ecc.
        - "note"    → tutto il resto: appunti, link, riflessioni, info
        
        Per "event" estrai la data in ISO8601 se presente, altrimenti null.
        
        Testo:
        \(text.prefix(800))
        """
    }
    
    // MARK: - JSON Parser
    
    private func parseAIResponse(_ json: String, originalText: String) throws -> KBClassificationResult {
        let clean = json
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = clean.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawDests = obj["destinations"] as? [String]
        else { throw ClassifierError.invalidJSON }
        
        let lines = originalText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var detectedDate: Date? = nil
        if let ds = obj["detectedDate"] as? String, ds != "null" {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                               .withColonSeparatorInTime, .withTimeZone]
            detectedDate = f.date(from: ds)
        }
        
        let actions: [KBSaveAction] = rawDests.compactMap { raw in
            switch raw {
            case "todo":    return .todo(title: lines.first ?? originalText)
            case "event":   return .event(title: originalText, date: detectedDate)
            case "grocery": return .grocery(lines: lines)
            case "note":    return .note(
                title: lines.first ?? originalText,
                body: lines.count > 1
                ? lines.dropFirst().joined(separator: "\n")
                : originalText)
            default:        return nil
            }
        }
        
        guard !actions.isEmpty else { throw ClassifierError.emptyResult }
        return KBClassificationResult(actions: actions, detectedDate: detectedDate, isAIClassified: true)
    }
    
    // MARK: - 2. Euristica italiana potenziata
    //
    // Usa array di (KBSaveAction, Int) invece di Dictionary
    // per evitare la conformance Hashable su KBSaveAction.
    
    private func classifyWithHeuristics(text: String) -> KBClassificationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let lines = trimmed
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let detectedDate = extractDate(from: trimmed)
        
        // Array di (azione, punteggio) — nessun requisito Hashable
        var scored: [(action: KBSaveAction, score: Int)] = []
        
        // ── GROCERY ──────────────────────────────────────────────────────
        let groceryKeywords = [
            "spesa", "supermercato", "super", "mercato", "negozio",
            "comprare", "compra", "acquistare", "prendere", "prendi",
            "latte", "pane", "uova", "uovo", "pasta", "riso", "farina",
            "burro", "olio", "sale", "zucchero", "caffè", "caffe",
            "carne", "pollo", "pesce", "prosciutto", "formaggio", "mozzarella",
            "verdura", "frutta", "patate", "pomodori", "insalata", "carote",
            "cipolle", "aglio", "zucchine", "melanzane", "peperoni",
            "yogurt", "succo", "acqua", "bibite", "vino", "birra",
            "biscotti", "crackers", "cereali", "miele", "marmellata",
            "detersivo", "shampoo", "sapone", "carta igienica", "tovaglioli"
        ]
        var groceryScore = groceryKeywords.filter { lower.contains($0) }.count
        if lines.count >= 2 { groceryScore += 3 }                              // lista multiriga
        if lines.count >= 2 && lines.allSatisfy({ $0.count < 30 }) { groceryScore += 2 } // righe brevi
        if groceryScore >= 2 {
            scored.append((.grocery(lines: lines), groceryScore))
        }
        
        // ── EVENT ─────────────────────────────────────────────────────────
        let eventKeywords = [
            "appuntamento", "visita", "riunione", "meeting", "incontro",
            "colloquio", "conferenza", "corso", "lezione", "allenamento",
            "partita", "spettacolo", "concerto", "cinema", "teatro",
            "compleanno", "anniversario", "festa", "cerimonia", "matrimonio",
            "vacanza", "viaggio", "volo", "prenotazione",
            "scadenza", "consegna", "deadline",
            "domani", "dopodomani", "stanotte", "stasera", "stamattina",
            "lunedì", "martedì", "mercoledì", "giovedì", "venerdì",
            "sabato", "domenica", "settimana", "mese", "prossimo", "prossima",
            "alle ore", "alle h", " ore ", " h ",
            "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
            "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"
        ]
        var eventScore = eventKeywords.filter { lower.contains($0) }.count
        if detectedDate != nil { eventScore += 4 }                             // NSDataDetector ha trovato una data
        if eventScore >= 2 {
            scored.append((.event(title: trimmed, date: detectedDate), eventScore))
        }
        
        // ── TODO ──────────────────────────────────────────────────────────
        // Un todo è quasi sempre breve e su riga singola.
        // Testo multiriga o lungo è quasi sempre una nota → penalizza fortemente.
        let todoKeywords = [
            "devo", "dobbiamo", "dovrei", "dovremmo", "bisogna",
            "ricordati", "ricordatevi", "ricorda", "non dimenticare",
            "non dimenticarti", "fai", "fate", "chiama", "chiamare",
            "scrivi", "scrivere", "manda", "mandare", "invia", "inviare",
            "prenota", "prenotare", "paga", "pagare", "ritira", "ritirare",
            "porta", "portare", "passa", "passare", "vai", "andate",
            "sistema", "sistemare", "aggiusta", "aggiustare", "prepara",
            "fare", "da fare", "to do", "todo", "task",
            "promemoria", "reminder", "nota bene", "nb:", "n.b.",
            "urgente", "importante", "priorità"
        ]
        var todoScore = todoKeywords.filter { lower.contains($0) }.count
        if trimmed.count < 80 && lines.count == 1 { todoScore += 2 }  // breve e diretto → boost
        if lines.count >= 3 { todoScore -= 3 }                        // 3+ righe → quasi mai un todo
        if lines.count >= 5 { todoScore -= 5 }                        // 5+ righe → mai un todo
        if trimmed.count > 200 { todoScore -= 3 }                     // testo lungo → penalizza
        if todoScore >= 1 {
            scored.append((.todo(title: lines.first ?? trimmed), todoScore + 1))
        }
        
        // ── NOTE ──────────────────────────────────────────────────────────
        let noteKeywords = [
            "nota", "appunto", "info", "informazione", "link", "url",
            "http", "https", "www", "articolo", "leggi", "vedi",
            "interessante", "salva", "tieni", "conserva",
            "indirizzo", "numero", "codice", "password", "pin",
            "ricetta", "ingredienti", "procedimento", "istruzioni"
        ]
        let noteScore = noteKeywords.filter { lower.contains($0) }.count
        let noteBody = lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : trimmed
        // Le note hanno sempre punteggio minimo 1 (catch-all)
        scored.append((.note(title: lines.first ?? trimmed, body: noteBody), max(noteScore + 1, 1)))
        
        // Ordina per punteggio decrescente
        let sorted = scored
            .sorted { $0.score > $1.score }
            .map { $0.action }
        
        return KBClassificationResult(
            actions: sorted,
            detectedDate: detectedDate,
            isAIClassified: false
        )
    }
    
    // MARK: - Date detection
    
    private func extractDate(from text: String) -> Date? {
        let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        )
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.date
    }
}

// MARK: - Media Hint

public enum KBMediaHint: Sendable {
    case image
    case video
    case generic(fileName: String)
}

// MARK: - Errors

private enum ClassifierError: Error {
    case modelUnavailable
    case invalidJSON
    case emptyResult
}
