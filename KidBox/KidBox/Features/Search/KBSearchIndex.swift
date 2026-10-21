//
//  KBSearchIndex.swift
//  KidBox
//
//  La ricerca in Home: tutta sul telefono, sui dati del quaderno
//  dell'assistente (`AgentMemorySnapshot`), quindi con le stesse esclusioni —
//  niente password, niente voci «solo per me» degli altri, niente testo dei
//  documenti d'identità. Cerca nei titoli e nel testo letto dei documenti;
//  una voce trovata si apre con la destinazione dei link dell'assistente
//  (`AgentLinks.destination(of:)`). Stessa logica su Android (`SearchIndex.kt`).
//

import Foundation

@MainActor
struct KBSearchIndex {

    struct Entry: Identifiable {
        let id: String
        let kind: AgentLinks.Kind
        let item: AgentLinks.Item
        let title: String
        let subtitle: String
        let date: Date
        /// Testo oltre al titolo (note, testo letto…), per l'estratto.
        let text: String
        fileprivate let foldedTitle: String
        fileprivate let foldedText: String
    }

    struct Hit: Identifiable {
        let entry: Entry
        /// Riga di testo intorno alla parola trovata, se non è nel titolo.
        let snippet: String?
        fileprivate let inTitle: Bool
        var id: String { entry.id }
    }

    struct Section: Identifiable {
        let kind: AgentLinks.Kind
        let hits: [Hit]
        var id: String { kind.rawValue }
    }

    /// Ordine delle sezioni nei risultati.
    static let order: [AgentLinks.Kind] = [
        .document, .expense, .note, .event, .todo, .visit, .exam, .treatment,
        .ticket, .home, .vehicle, .pet, .trip, .grocery,
    ]
    static let perSection = 8
    static let perSingleSection = 50

    let snapshot: AgentMemorySnapshot
    private let entries: [Entry]

    init(snapshot s: AgentMemorySnapshot) {
        snapshot = s
        let dateFmt = DateFormatter()
        dateFmt.locale = kbDeviceLocale()
        dateFmt.dateStyle = .medium
        let day = { (d: Date) in dateFmt.string(from: d) }
        let euro = NumberFormatter()
        euro.numberStyle = .currency
        euro.currencyCode = "EUR"
        euro.locale = kbDeviceLocale()

        var out: [Entry] = []
        func add(_ id: String, _ kind: AgentLinks.Kind, _ item: AgentLinks.Item, _ title: String,
                 _ subtitle: String, _ date: Date, _ text: [String?] = []) {
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            let body = text.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
            // La riga sotto il titolo (persona, data, importo) si cerca anche lei:
            // «Marco visita», «84,20», «ottobre».
            out.append(Entry(id: "\(kind.rawValue):\(id)", kind: kind, item: item, title: clean, subtitle: subtitle, date: date, text: body,
                             foldedTitle: AgentRelevance.fold(clean), foldedText: AgentRelevance.fold(subtitle + "\n" + body)))
        }

        for e in s.expenses {
            add(e.id, .expense, .expense(e), e.title, "\(euro.string(from: NSNumber(value: e.amount)) ?? "") · \(day(e.date))", e.date, [e.notes])
        }
        for d in s.documents {
            // Il testo dei documenti d'identità non entra mai, come nel quaderno.
            let isIdentity = d.notes?.hasPrefix(KBWalletDocumentKind.notesPrefix) == true
            let text = isIdentity ? nil : d.extractedText.map(HealthAiDocumentText.sanitizeExtractedText)
            add(d.id, .document, .document(d), d.title, day(d.createdAt), d.createdAt, [text])
        }
        for n in s.notes {
            add(n.id, .note, .note(n), n.title.isEmpty ? String(localized: "(senza titolo)") : n.title, day(n.updatedAt), n.updatedAt,
                [NoteHtmlSanitizer.plainText(from: n.body)])
        }
        for e in s.events {
            add(e.id, .event, .event(e), e.title, day(e.startDate), e.startDate, [e.location, e.notes])
        }
        for t in s.todos where t.listId != nil {
            add(t.id, .todo, .todo(t), t.title, t.dueAt.map(day) ?? (t.isDone ? String(localized: "Fatto") : ""), t.dueAt ?? t.createdAt, [t.notes])
        }
        for g in s.pendingGrocery {
            add(g.id, .grocery, .grocery, g.name, g.category ?? "", g.createdAt)
        }
        for v in s.visits {
            let who = s.personName(v.childId) ?? ""
            add(v.id, .visit, .visit(v), v.reason.isEmpty ? String(localized: "Visita") : v.reason,
                [who, day(v.date)].filter { !$0.isEmpty }.joined(separator: " · "), v.date,
                [v.doctorName, v.diagnosis, v.recommendations, v.notes])
        }
        for e in s.exams {
            let when = e.resultDate ?? e.deadline ?? e.createdAt
            add(e.id, .exam, .exam(e), e.name, [s.personName(e.childId) ?? "", day(when)].filter { !$0.isEmpty }.joined(separator: " · "), when, [e.notes])
        }
        for t in s.treatments {
            let who = t.petId.isEmpty ? s.personName(t.childId) : s.pets.first { $0.id == t.petId }?.name
            add(t.id, .treatment, .treatment(t), t.drugName, [who ?? "", day(t.startDate)].filter { !$0.isEmpty }.joined(separator: " · "), t.startDate)
        }
        for t in s.walletTickets {
            add(t.id, .ticket, .ticket(t), t.title, t.eventDate.map(day) ?? "", t.eventDate ?? .distantPast, [t.location, t.arrivalLocation])
        }
        for h in s.homeItems { add(h.id, .home, .homeItem(h), h.name, "", h.createdAt, [h.notes]) }
        for p in s.housePayments { add(p.id, .home, .housePayment(p), p.name, "", p.createdAt) }
        for v in s.vehicles { add(v.id, .vehicle, .vehicle(v), v.name, "", v.createdAt) }
        for p in s.pets { add(p.id, .pet, .pet(p), p.name, "", p.createdAt) }
        for t in s.trips { add(t.id, .trip, .trip(t), t.name, "\(day(t.startDate)) – \(day(t.endDate))", t.startDate) }
        entries = out
    }

    /// Tutte le parole della ricerca, nel titolo o nel testo: prima le voci
    /// col titolo che corrisponde, poi le più recenti. `kinds` vuoto = tutte
    /// le sezioni; con una sezione scelta e niente scritto si vedono le sue
    /// voci più recenti.
    func search(_ query: String, kinds: Set<AgentLinks.Kind> = []) -> [Section] {
        let words = AgentRelevance.fold(query)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let typed = !words.isEmpty && words.joined().count >= 2
        guard typed || !kinds.isEmpty else { return [] }

        var hits: [Hit] = []
        for e in entries where kinds.isEmpty || kinds.contains(e.kind) {
            guard typed else {
                hits.append(Hit(entry: e, snippet: nil, inTitle: true))
                continue
            }
            let inTitle = words.allSatisfy { e.foldedTitle.contains($0) }
            guard inTitle || words.allSatisfy({ e.foldedTitle.contains($0) || e.foldedText.contains($0) }) else { continue }
            hits.append(Hit(entry: e, snippet: inTitle ? nil : Self.snippet(e.text, words: words), inTitle: inTitle))
        }
        // Con una sola sezione scelta si vede di più: è una lista, non un riepilogo.
        let limit = kinds.count == 1 ? Self.perSingleSection : Self.perSection
        let grouped = Dictionary(grouping: hits, by: \.entry.kind)
        return Self.order.compactMap { kind in
            guard let list = grouped[kind], !list.isEmpty else { return nil }
            let sorted = list.sorted {
                $0.inTitle != $1.inTitle ? $0.inTitle : $0.entry.date > $1.entry.date
            }
            return Section(kind: kind, hits: Array(sorted.prefix(limit)))
        }
    }

    /// Una riga intorno alla prima parola trovata nel testo.
    private static func snippet(_ text: String, words: [String]) -> String? {
        for w in words {
            guard let r = text.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            let start = text.index(r.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(r.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
            let line = text[start..<end].replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            return (start > text.startIndex ? "…" : "") + line + (end < text.endIndex ? "…" : "")
        }
        return nil
    }
}

extension AgentLinks.Kind {
    /// Titolo della sezione nei risultati della ricerca.
    var searchTitle: String {
        switch self {
        case .expense: return String(localized: "Spese")
        case .document: return String(localized: "Documenti")
        case .note: return String(localized: "Note")
        case .event: return String(localized: "Calendario")
        case .todo: return String(localized: "To-do")
        case .grocery: return String(localized: "Lista della spesa")
        case .visit: return String(localized: "Visite")
        case .exam: return String(localized: "Esami")
        case .treatment: return String(localized: "Cure")
        case .ticket: return String(localized: "Wallet")
        case .home: return String(localized: "Casa")
        case .vehicle: return String(localized: "Veicoli")
        case .pet: return String(localized: "Animali")
        case .trip: return String(localized: "Viaggi")
        }
    }

    var searchIcon: String {
        switch self {
        case .expense: return "eurosign.circle"
        case .document: return "doc.text"
        case .note: return "note.text"
        case .event: return "calendar"
        case .todo: return "checklist"
        case .grocery: return "cart"
        case .visit: return "stethoscope"
        case .exam: return "testtube.2"
        case .treatment: return "pills"
        case .ticket: return "wallet.pass"
        case .home: return "house"
        case .vehicle: return "car"
        case .pet: return "pawprint"
        case .trip: return "airplane"
        }
    }
}
