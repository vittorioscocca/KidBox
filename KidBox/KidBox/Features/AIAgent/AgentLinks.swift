//
//  AgentLinks.swift
//  KidBox
//
//  Link dell'assistente alle voci dell'app: «trovami la bolletta della luce»
//  → risposta con [Bolletta luce](apri:spese) → un tocco apre la spesa.
//
//  Il modello non vede gli id (costerebbero token a ogni domanda e li
//  inventerebbe): scrive il titolo come compare nella scheda e il tipo, con la
//  data se più voci si chiamano uguale. La voce si cerca nello snapshot del
//  quaderno al momento del tocco; se non c'è più si apre la sezione.
//  Stesso formato e stesse regole su Android (`AgentLinks.kt`).
//

import Foundation

@MainActor
enum AgentLinks {

    static let scheme = "kidbox-agent"

    /// La regola del prompt, nelle regole stabili dell'assistente. Stesso testo su Android.
    static let promptRule = """
    - Quando parli di una voce precisa delle schede (una spesa, un documento, una nota, un evento, un to-do, una visita…) \
    o l'utente cerca qualcosa («trovami…», «dov'è…», «la bolletta di…»), mettila come link, così si apre con un tocco: \
    [titolo esatto come nella scheda](apri:TIPO), oppure [titolo](apri:TIPO/AAAA-MM-GG) con la data della voce se più voci \
    hanno lo stesso titolo. TIPO: spese, documento, nota, evento, todo, listaspesa, visita, esame, cura, biglietto, casa, \
    veicolo, animale, viaggio. Solo voci che ci sono nelle schede, mai altri indirizzi; non dire «clicca qui»: il link è il titolo.
    """

    enum Kind: String, CaseIterable {
        case expense = "spese"
        case document = "documento"
        case note = "nota"
        case event = "evento"
        case todo = "todo"
        case grocery = "listaspesa"
        case visit = "visita"
        case exam = "esame"
        case treatment = "cura"
        case ticket = "biglietto"
        case home = "casa"
        case vehicle = "veicolo"
        case pet = "animale"
        case trip = "viaggio"

        /// Varianti che il modello scrive anche se la regola ne dà una sola.
        init?(loose raw: String) {
            let key = AgentRelevance.fold(raw).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
            switch key {
            case "spesa", "spese", "expense": self = .expense
            case "documenti", "doc": self = .document
            case "note": self = .note
            case "eventi", "calendario": self = .event
            case "todos", "promemoria": self = .todo
            case "lista", "grocery": self = .grocery
            case "visite": self = .visit
            case "esami": self = .exam
            case "cure", "terapia": self = .treatment
            case "wallet", "biglietti": self = .ticket
            case "veicoli", "auto": self = .vehicle
            case "animali": self = .pet
            case "viaggi": self = .trip
            default:
                guard let k = Kind(rawValue: key) else { return nil }
                self = k
            }
        }
    }

    struct Link: Equatable {
        let kind: Kind
        let title: String
        let day: String?
    }

    // MARK: Testo

    private static let pattern = try! NSRegularExpression(
        pattern: #"\[([^\]\n]+)\]\(\s*apri:([A-Za-zÀ-ÿ\- ]+?)(?:/(\d{4}-\d{2}-\d{2}))?\s*\)"#
    )

    /// `[titolo](apri:tipo/data)` → link `kidbox-agent://open?...` con il titolo
    /// dentro, che il markdown sa disegnare. Un tipo sconosciuto lascia solo il titolo.
    static func prepare(_ text: String) -> String {
        guard text.contains("apri:") else { return text }
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let title = ns.substring(with: m.range(at: 1))
            let rawKind = ns.substring(with: m.range(at: 2))
            let day = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : nil
            if let kind = Kind(loose: rawKind), let url = url(Link(kind: kind, title: title, day: day)) {
                out += "[\(title)](\(url.absoluteString))"
            } else {
                out += title
            }
            cursor = m.range.location + m.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    static func url(_ link: Link) -> URL? {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "open"
        // Tutto codificato tranne lettere e cifre: una parentesi nel titolo
        // («Libri (scuola)») chiuderebbe il link markdown a metà.
        let enc = { (v: String) in v.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? v }
        c.percentEncodedQueryItems = [URLQueryItem(name: "k", value: link.kind.rawValue), URLQueryItem(name: "t", value: enc(link.title))]
            + (link.day.map { [URLQueryItem(name: "d", value: $0)] } ?? [])
        return c.url
    }

    static func parse(_ url: URL) -> Link? {
        guard url.scheme == scheme, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let q = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        guard let kind = q["k"].flatMap(Kind.init(rawValue:)), let title = q["t"], !title.isEmpty else { return nil }
        return Link(kind: kind, title: title, day: q["d"].flatMap { $0.isEmpty ? nil : $0 })
    }

    // MARK: Ricerca della voce

    /// Dove porta il link: le schermate da impilare sopra l'assistente, così
    /// «Indietro» ci torna. `documentId` va consegnato alla cartella, che apre
    /// il documento quando compare. `found` falso = aperta la sezione.
    struct Destination {
        var routes: [Route]
        var documentId: String? = nil
        var found: Bool
    }

    @MainActor
    static func destination(for link: Link, in s: AgentMemorySnapshot) -> Destination {
        let fid = s.familyId
        switch link.kind {
        case .expense:
            if let e = best(s.expenses, link, title: \.title, date: { $0.date }) {
                return Destination(routes: [.expensesHome(familyId: fid, highlightExpenseId: nil), .expenseDetail(familyId: fid, expenseId: e.id)], found: true)
            }
            return Destination(routes: [.expensesHome(familyId: fid, highlightExpenseId: nil)], found: false)
        case .document:
            if let d = best(s.documents, link, title: \.title, date: { $0.createdAt }) {
                return documentDestination(d, in: s)
            }
            return Destination(routes: [.documentsHome], found: false)
        case .note:
            if let n = best(s.notes, link, title: \.title, date: { $0.updatedAt }) {
                return Destination(routes: [.notesHome(familyId: fid), .noteDetail(familyId: fid, noteId: n.id)], found: true)
            }
            return Destination(routes: [.notesHome(familyId: fid)], found: false)
        case .event:
            let e = best(s.events, link, title: \.title, date: { $0.startDate })
            return Destination(routes: [.calendar(familyId: fid, highlightEventId: e?.id)], found: e != nil)
        case .todo:
            if let t = best(s.todos, link, title: \.title, date: { $0.dueAt ?? $0.createdAt }), let listId = t.listId {
                return Destination(routes: [.todo, .todoList(familyId: fid, childId: t.childId, listId: listId)], found: true)
            }
            return Destination(routes: [.todo], found: false)
        case .grocery:
            return Destination(routes: [.shoppingList(familyId: fid)], found: true)
        case .visit:
            if let v = best(s.visits, link, title: { $0.reason.isEmpty ? ($0.doctorName ?? "") : $0.reason }, date: { $0.date }) {
                return Destination(routes: healthRoutes(fid, v.childId, list: .pediatricVisits(familyId: fid, childId: v.childId))
                    + [.pediatricVisitDetail(familyId: fid, childId: v.childId, visitId: v.id)], found: true)
            }
            return Destination(routes: [.pediatricChildSelector(familyId: fid)], found: false)
        case .exam:
            if let e = best(s.exams, link, title: \.name, date: { $0.deadline ?? $0.createdAt }) {
                return Destination(routes: healthRoutes(fid, e.childId, list: .pediatricExams(familyId: fid, childId: e.childId))
                    + [.examDetail(familyId: fid, childId: e.childId, examId: e.id)], found: true)
            }
            return Destination(routes: [.pediatricChildSelector(familyId: fid)], found: false)
        case .treatment:
            if let t = best(s.treatments, link, title: \.drugName, date: { $0.startDate }) {
                if !t.petId.isEmpty {
                    return Destination(routes: [.petsHome(familyId: fid), .petDetail(familyId: fid, petId: t.petId)], found: true)
                }
                return Destination(routes: healthRoutes(fid, t.childId, list: .pediatricTreatments(familyId: fid, childId: t.childId))
                    + [.pediatricTreatmentDetail(familyId: fid, childId: t.childId, treatmentId: t.id)], found: true)
            }
            return Destination(routes: [.pediatricChildSelector(familyId: fid)], found: false)
        case .ticket:
            if let t = best(s.walletTickets, link, title: \.title, date: { $0.eventDate ?? .distantPast }) {
                return Destination(routes: [.walletHome(familyId: fid), .walletTicketDetail(familyId: fid, ticketId: t.id)], found: true)
            }
            return Destination(routes: [.walletHome(familyId: fid)], found: false)
        case .home:
            if let h = best(s.homeItems, link, title: \.name, date: { $0.createdAt }) {
                return Destination(routes: [.homeItemsHome(familyId: fid), .homeItemDetail(familyId: fid, itemId: h.id)], found: true)
            }
            if let p = best(s.housePayments, link, title: \.name, date: { $0.createdAt }) {
                return Destination(routes: [.homeItemsHome(familyId: fid), .housePaymentDetail(familyId: fid, paymentId: p.id)], found: true)
            }
            return Destination(routes: [.homeItemsHome(familyId: fid)], found: false)
        case .vehicle:
            if let v = best(s.vehicles, link, title: \.name, date: { $0.createdAt }) {
                return Destination(routes: [.vehiclesHome(familyId: fid), .vehicleDetail(familyId: fid, vehicleId: v.id)], found: true)
            }
            return Destination(routes: [.vehiclesHome(familyId: fid)], found: false)
        case .pet:
            if let p = best(s.pets, link, title: \.name, date: { $0.createdAt }) {
                return Destination(routes: [.petsHome(familyId: fid), .petDetail(familyId: fid, petId: p.id)], found: true)
            }
            return Destination(routes: [.petsHome(familyId: fid)], found: false)
        case .trip:
            if let t = best(s.trips, link, title: \.name, date: { $0.startDate }) {
                return Destination(routes: [.travelList(familyId: fid), .travelTripDetail(familyId: fid, tripId: t.id)], found: true)
            }
            return Destination(routes: [.travelList(familyId: fid)], found: false)
        }
    }

    /// Un allegato si apre dove vive (la visita, l'oggetto di casa…), un
    /// documento d'identità nel Wallet, gli altri nella loro cartella.
    @MainActor
    private static func documentDestination(_ d: KBDocument, in s: AgentMemorySnapshot) -> Destination {
        let fid = s.familyId
        if let tag = d.notes, tag.hasPrefix(KBWalletDocumentKind.notesPrefix) {
            return Destination(routes: [.walletHome(familyId: fid), .walletDocumentDetail(familyId: fid, documentId: d.id)], found: true)
        }
        if let tag = d.notes, let colon = tag.firstIndex(of: ":") {
            let id = String(tag[tag.index(after: colon)...])
            switch String(tag[..<colon]) {
            case "visit":
                if let v = s.visits.first(where: { $0.id == id }) {
                    return Destination(routes: healthRoutes(fid, v.childId, list: .pediatricVisits(familyId: fid, childId: v.childId))
                        + [.pediatricVisitDetail(familyId: fid, childId: v.childId, visitId: v.id)], found: true)
                }
            case "exam":
                if let e = s.exams.first(where: { $0.id == id }) {
                    return Destination(routes: healthRoutes(fid, e.childId, list: .pediatricExams(familyId: fid, childId: e.childId))
                        + [.examDetail(familyId: fid, childId: e.childId, examId: e.id)], found: true)
                }
            case "treatment":
                if let t = s.treatments.first(where: { $0.id == id }), t.petId.isEmpty {
                    return Destination(routes: healthRoutes(fid, t.childId, list: .pediatricTreatments(familyId: fid, childId: t.childId))
                        + [.pediatricTreatmentDetail(familyId: fid, childId: t.childId, treatmentId: t.id)], found: true)
                }
            case "homeItem":
                return Destination(routes: [.homeItemsHome(familyId: fid), .homeItemDetail(familyId: fid, itemId: id)], found: true)
            case "housePayment":
                return Destination(routes: [.homeItemsHome(familyId: fid), .housePaymentDetail(familyId: fid, paymentId: id)], found: true)
            case "vehicle":
                return Destination(routes: [.vehiclesHome(familyId: fid), .vehicleDetail(familyId: fid, vehicleId: id)], found: true)
            case "vehicleEvent":
                if let ev = s.vehicleEvents.first(where: { $0.id == id }) {
                    return Destination(routes: [.vehiclesHome(familyId: fid), .vehicleDetail(familyId: fid, vehicleId: ev.vehicleId)], found: true)
                }
            case "pet":
                return Destination(routes: [.petsHome(familyId: fid), .petDetail(familyId: fid, petId: id)], found: true)
            case "expense":
                return Destination(routes: [.expensesHome(familyId: fid, highlightExpenseId: nil), .expenseDetail(familyId: fid, expenseId: id)], found: true)
            default:
                break
            }
        }
        // La cartella e quelle che la contengono, come `openDocumentFromPush`.
        var routes: [Route] = [.documentsHome]
        var chain: [(id: String, title: String)] = []
        var current = d.categoryId
        var guardCount = 0
        while let catId = current, guardCount < 12, let title = s.documentCategoryNames[catId] {
            chain.insert((catId, title), at: 0)
            current = s.documentCategoryParents[catId] ?? nil
            guardCount += 1
        }
        routes += chain.map { .documentsCategory(familyId: fid, categoryId: $0.id, title: $0.title) }
        return Destination(routes: routes, documentId: d.id, found: true)
    }

    /// Salute di una persona: la sua home e la lista, sotto il dettaglio.
    private static func healthRoutes(_ fid: String, _ childId: String, list: Route) -> [Route] {
        [.pediatricHome(familyId: fid, childId: childId), list]
    }

    private static func words(_ text: String) -> Set<String> {
        let parts: [Substring] = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return Set(parts.filter { $0.count > 2 }.map(String.init))
    }

    /// La voce più simile al titolo: uguale, poi contenuta, poi parole in
    /// comune; a parità vince il giorno indicato, poi la più recente.
    static func best<T>(_ items: [T], _ link: Link, title: (T) -> String, date: (T) -> Date) -> T? {
        let wanted = AgentRelevance.fold(link.title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        let wantedWords = words(wanted)
        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.dateFormat = "yyyy-MM-dd"
        let day = link.day.flatMap { dayFmt.date(from: $0) }

        var bestItem: T?
        var bestScore = 0
        var bestDistance = TimeInterval.infinity
        for item in items {
            let t = AgentRelevance.fold(title(item)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            var score = 0
            if t == wanted {
                score = 1000
            } else if t.contains(wanted) || wanted.contains(t) {
                score = 500
            } else {
                let common = words(t).intersection(wantedWords).count
                // Più di metà delle parole chieste: una parola sola in comune
                // («Bolletta gas» per «Bolletta luce») non è la voce cercata.
                guard common > 0, common * 2 > wantedWords.count else { continue }
                score = 100 * common
            }
            let d = date(item)
            let distance = day.map { abs(d.timeIntervalSince($0)) } ?? -d.timeIntervalSince1970
            if score > bestScore || (score == bestScore && distance < bestDistance) {
                bestItem = item
                bestScore = score
                bestDistance = distance
            }
        }
        return bestItem
    }
}
