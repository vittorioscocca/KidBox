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
    case chat, document, todo, grocery, event, note, encryptedMedia, wallet
    public var id: Self { self }
}

// MARK: - Azione concreta (con payload)

public enum KBSaveAction: Identifiable, Sendable {
    case todo(title: String)
    case event(title: String, date: Date?)
    case grocery(lines: [String])
    case note(title: String, body: String)
    case document(mediaURL: String, fileName: String)
    /// Invia foto o video nella sezione "Foto e video" crittografati (FamilyPhotosView).
    /// `sourceURL` è l'URL locale o remoto del media; `isVideo` distingue foto da video.
    case encryptedMedia(sourceURL: String, fileName: String, isVideo: Bool)
    /// Mostra in Mappe un indirizzo riconosciuto nel messaggio.
    case map(address: String)
    
    public var id: String {
        switch self {
        case .todo:             return "todo"
        case .event:            return "event"
        case .grocery:          return "grocery"
        case .note:             return "note"
        case .document:         return "document"
        case .encryptedMedia:   return "encryptedMedia"
        case .map:              return "map"
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
        switch mimeHint {
        case .image:
            // Foto → va sia in chat che in Foto e video crittografati
            let fileName = URL(string: mediaURL)?.lastPathComponent ?? "foto.jpg"
            return KBClassificationResult(
                actions: [
                    .encryptedMedia(sourceURL: mediaURL, fileName: fileName, isVideo: false),
                    .document(mediaURL: mediaURL, fileName: fileName)
                ],
                detectedDate: nil, isAIClassified: false)
            
        case .video:
            // Video → va sia in chat che in Foto e video crittografati
            let fileName = URL(string: mediaURL)?.lastPathComponent ?? "video.mp4"
            return KBClassificationResult(
                actions: [
                    .encryptedMedia(sourceURL: mediaURL, fileName: fileName, isVideo: true),
                    .document(mediaURL: mediaURL, fileName: fileName)
                ],
                detectedDate: nil, isAIClassified: false)
            
        case .generic(let name):
            return KBClassificationResult(
                actions: [.document(mediaURL: mediaURL, fileName: name)],
                detectedDate: nil, isAIClassified: false)
        }
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
        Sei un assistente per un'app di famiglia. Il testo può essere in italiano, \
        inglese, francese o spagnolo. Analizza il testo e restituisci SOLO JSON \
        valido, senza markdown, senza spiegazioni.
        
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
    
    // Le altre tre lingue dell'app. Le parole italiane si cercano come
    // sottostringa (storico); queste a parola intera, perché le parole corte di
    // una lingua cadono dentro quelle di un'altra («pan» sta in «pantaloni»).
    private static let groceryWords: [String] = [
        // en
        "shopping", "groceries", "supermarket", "store", "buy", "milk", "bread", "eggs", "pasta", "rice",
        "flour", "butter", "oil", "salt", "sugar", "coffee", "meat", "chicken", "fish", "ham", "cheese",
        "vegetables", "fruit", "potatoes", "tomatoes", "salad", "carrots", "onions", "garlic", "yogurt",
        "juice", "water", "wine", "beer", "cookies", "cereal", "honey", "jam", "detergent", "shampoo",
        "soap", "toilet paper", "napkins",
        // fr
        "courses", "supermarché", "magasin", "acheter", "achète", "lait", "pain", "oeufs", "œufs", "pâtes",
        "riz", "farine", "beurre", "huile", "sel", "sucre", "café", "viande", "poulet", "poisson", "jambon",
        "fromage", "légumes", "fruits", "pommes de terre", "tomates", "salade", "carottes", "oignons", "ail",
        "yaourt", "jus", "eau", "vin", "bière", "biscuits", "céréales", "miel", "confiture", "lessive",
        "shampooing", "savon", "papier toilette", "serviettes",
        // es
        "compra", "supermercado", "tienda", "comprar", "leche", "pan", "huevos", "arroz", "harina",
        "mantequilla", "aceite", "sal", "azúcar", "carne", "pollo", "pescado", "jamón", "queso", "verdura",
        "fruta", "patatas", "ensalada", "zanahorias", "cebollas", "ajo", "yogur", "zumo", "agua", "vino",
        "cerveza", "galletas", "cereales", "mermelada", "detergente", "champú", "jabón", "papel higiénico",
        "servilletas"
    ]
    
    private static let eventWords: [String] = [
        // en
        "appointment", "visit", "meeting", "lesson", "class", "practice", "match", "game", "show", "concert",
        "cinema", "theater", "theatre", "birthday", "anniversary", "party", "ceremony", "wedding", "holiday",
        "trip", "flight", "booking", "reservation", "deadline", "due", "tomorrow", "tonight", "today",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "week", "month", "next",
        "o'clock", "january", "february", "march", "april", "may", "june", "july", "august", "september",
        "october", "november", "december",
        // fr
        "rendez-vous", "visite", "réunion", "rencontre", "cours", "entraînement", "spectacle", "cinéma",
        "théâtre", "anniversaire", "fête", "cérémonie", "mariage", "vacances", "voyage", "vol", "réservation",
        "échéance", "demain", "ce soir", "aujourd'hui", "lundi", "mardi", "mercredi", "jeudi", "vendredi",
        "samedi", "dimanche", "semaine", "mois", "prochain", "prochaine", "janvier", "février", "mars",
        "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre",
        // es
        "cita", "visita", "reunión", "encuentro", "clase", "entrenamiento", "partido", "espectáculo",
        "concierto", "cine", "teatro", "cumpleaños", "aniversario", "fiesta", "ceremonia", "boda",
        "vacaciones", "viaje", "vuelo", "reserva", "plazo", "mañana", "esta noche", "hoy", "lunes", "martes",
        "miércoles", "jueves", "viernes", "sábado", "domingo", "semana", "mes", "próximo", "próxima",
        "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
        "noviembre", "diciembre"
    ]
    
    private static let todoWords: [String] = [
        // en
        "i need to", "we need to", "have to", "must", "should", "remember", "don't forget", "call", "write",
        "send", "book", "pay", "pick up", "bring", "drop off", "fix", "prepare", "to do", "todo", "task",
        "reminder", "urgent", "important", "priority",
        // fr
        "je dois", "on doit", "il faut", "rappelle-toi", "n'oublie pas", "appelle", "appeler", "écris",
        "envoie", "envoyer", "réserve", "réserver", "paie", "payer", "récupère", "récupérer", "apporte",
        "apporter", "répare", "prépare", "à faire", "rappel", "priorité",
        // es
        "tengo que", "debo", "debemos", "hay que", "recuerda", "no olvides", "llama", "llamar", "escribe",
        "envía", "enviar", "reservar", "paga", "pagar", "recoge", "recoger", "trae", "traer", "arregla",
        "prepara", "por hacer", "recordatorio", "urgente", "importante", "prioridad"
    ]
    
    private static let noteWords: [String] = [
        // en
        "note", "info", "information", "link", "article", "read", "see", "interesting", "keep", "address",
        "number", "code", "password", "pin", "recipe", "ingredients", "steps", "instructions",
        // fr
        "lien", "lis", "voir", "intéressant", "garde", "adresse", "numéro", "mot de passe", "recette",
        "ingrédients",
        // es
        "nota", "apunte", "información", "enlace", "artículo", "lee", "ver", "interesante", "guarda",
        "dirección", "número", "código", "contraseña", "receta", "ingredientes", "instrucciones"
    ]
    
    /// Italiano a sottostringa (storico), le altre lingue a parola intera.
    private func hits(_ lower: String, italian: [String], others: [String]) -> Int {
        let fromItalian = italian.filter { lower.contains($0) }.count
        let fromOthers = others.filter { word in
            guard !italian.contains(word) else { return false }
            let pattern = "(?<!\\p{L})" + NSRegularExpression.escapedPattern(for: word) + "(?!\\p{L})"
            return lower.range(of: pattern, options: .regularExpression) != nil
        }.count
        return fromItalian + fromOthers
    }
    
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
        var groceryScore = hits(lower, italian: groceryKeywords, others: Self.groceryWords)
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
        var eventScore = hits(lower, italian: eventKeywords, others: Self.eventWords)
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
        var todoScore = hits(lower, italian: todoKeywords, others: Self.todoWords)
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
        let noteScore = hits(lower, italian: noteKeywords, others: Self.noteWords)
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
