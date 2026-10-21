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
    hanno lo stesso titolo; per visite, esami e cure metti sempre la data. TIPO: spese, documento, nota, evento, todo, listaspesa, visita, esame, cura, biglietto, casa, \
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

    /// Ordine in cui si cerca negli altri tipi quando quello indicato non ha
    /// la voce: il modello a volte scrive `visita` per il referto di una
    /// gastroscopia o `documento` per una visita. La lista della spesa no:
    /// «trovata» lo è sempre.
    private static let fallbackOrder: [Kind] = [
        .document, .visit, .exam, .treatment, .expense, .note, .event, .todo,
        .ticket, .home, .vehicle, .pet, .trip,
    ]

    @MainActor
    static func destination(for link: Link, in s: AgentMemorySnapshot) -> Destination {
        let first = destination(kind: link.kind, link, in: s)
        if first.found { return first }
        for kind in fallbackOrder where kind != link.kind {
            let other = destination(kind: kind, link, in: s)
            if other.found { return other }
        }
        return first
    }

    /// Una voce dell'app, già trovata: la usa anche la ricerca in Home
    /// (`KBSearchIndex`), che sa quale voce ha toccato l'utente.
    enum Item {
        case expense(KBExpense), document(KBDocument), note(KBNote), event(KBCalendarEvent)
        case todo(KBTodoItem), grocery, visit(KBMedicalVisit), exam(KBMedicalExam), treatment(KBTreatment)
        case ticket(KBWalletTicket), homeItem(KBHomeItem), housePayment(KBHousePayment)
        case vehicle(KBVehicle), pet(KBPet), trip(KBTrip)
    }

    @MainActor
    private static func destination(kind: Kind, _ link: Link, in s: AgentMemorySnapshot) -> Destination {
        if let item = find(kind: kind, link, in: s) { return destination(of: item, in: s) }
        return Destination(routes: section(kind, familyId: s.familyId), found: false)
    }

    @MainActor
    private static func find(kind: Kind, _ link: Link, in s: AgentMemorySnapshot) -> Item? {
        switch kind {
        case .expense:
            return best(s.expenses, link, title: \.title, date: { $0.date }).map(Item.expense)
        case .document:
            return best(s.documents, link, title: \.title, date: { $0.createdAt }).map(Item.document)
        case .note:
            return best(s.notes, link, title: \.title, date: { $0.updatedAt }).map(Item.note)
        case .event:
            return best(s.events, link, title: \.title, date: { $0.startDate }).map(Item.event)
        case .todo:
            return best(s.todos.filter { $0.listId != nil }, link, title: \.title, date: { $0.dueAt ?? $0.createdAt }).map(Item.todo)
        case .grocery:
            return .grocery
        case .visit:
            // Una visita nel quaderno non ha titolo: è «VISITA n — data» con
            // motivo, medico, diagnosi e referti. Si confronta con tutto quello,
            // e la data da sola basta.
            return best(s.visits, link, texts: { [$0.reason, $0.doctorName ?? "", $0.diagnosis ?? ""] + attachmentTitles("visit:\($0.id)", s) },
                        date: { $0.date }, dayIsIdentity: true).map(Item.visit)
        case .exam:
            return best(s.exams, link, texts: { [$0.name] + attachmentTitles(ExamAttachmentTag.make($0.id), s) },
                        date: { $0.resultDate ?? $0.deadline ?? $0.createdAt }, dayIsIdentity: true).map(Item.exam)
        case .treatment:
            return best(s.treatments, link, texts: { [$0.drugName] + attachmentTitles("treatment:\($0.id)", s) }, date: { $0.startDate }).map(Item.treatment)
        case .ticket:
            return best(s.walletTickets, link, title: \.title, date: { $0.eventDate ?? .distantPast }).map(Item.ticket)
        case .home:
            return best(s.homeItems, link, title: \.name, date: { $0.createdAt }).map(Item.homeItem)
                ?? best(s.housePayments, link, title: \.name, date: { $0.createdAt }).map(Item.housePayment)
        case .vehicle:
            return best(s.vehicles, link, title: \.name, date: { $0.createdAt }).map(Item.vehicle)
        case .pet:
            return best(s.pets, link, title: \.name, date: { $0.createdAt }).map(Item.pet)
        case .trip:
            return best(s.trips, link, title: \.name, date: { $0.startDate }).map(Item.trip)
        }
    }

    /// La sezione, quando la voce non c'è più.
    static func section(_ kind: Kind, familyId fid: String) -> [Route] {
        switch kind {
        case .expense: return [.expensesHome(familyId: fid, highlightExpenseId: nil)]
        case .document: return [.documentsHome]
        case .note: return [.notesHome(familyId: fid)]
        case .event: return [.calendar(familyId: fid)]
        case .todo: return [.todo]
        case .grocery: return [.shoppingList(familyId: fid)]
        case .visit, .exam, .treatment: return [.pediatricChildSelector(familyId: fid)]
        case .ticket: return [.walletHome(familyId: fid)]
        case .home: return [.homeItemsHome(familyId: fid)]
        case .vehicle: return [.vehiclesHome(familyId: fid)]
        case .pet: return [.petsHome(familyId: fid)]
        case .trip: return [.travelList(familyId: fid)]
        }
    }

    /// Le schermate di una voce: la sezione e il dettaglio, sopra chi la apre.
    @MainActor
    static func destination(of item: Item, in s: AgentMemorySnapshot) -> Destination {
        let fid = s.familyId
        let routes: [Route]
        switch item {
        case .expense(let e):
            routes = [.expensesHome(familyId: fid, highlightExpenseId: nil), .expenseDetail(familyId: fid, expenseId: e.id)]
        case .document(let d):
            return documentDestination(d, in: s)
        case .note(let n):
            routes = [.notesHome(familyId: fid), .noteDetail(familyId: fid, noteId: n.id)]
        case .event(let e):
            routes = [.calendar(familyId: fid, highlightEventId: e.id)]
        case .todo(let t):
            guard let listId = t.listId else { return Destination(routes: [.todo], found: true) }
            routes = [.todo, .todoList(familyId: fid, childId: t.childId, listId: listId)]
        case .grocery:
            routes = [.shoppingList(familyId: fid)]
        case .visit(let v):
            routes = healthRoutes(fid, v.childId, list: .pediatricVisits(familyId: fid, childId: v.childId))
                + [.pediatricVisitDetail(familyId: fid, childId: v.childId, visitId: v.id)]
        case .exam(let e):
            routes = healthRoutes(fid, e.childId, list: .pediatricExams(familyId: fid, childId: e.childId))
                + [.examDetail(familyId: fid, childId: e.childId, examId: e.id)]
        case .treatment(let t):
            routes = t.petId.isEmpty
                ? healthRoutes(fid, t.childId, list: .pediatricTreatments(familyId: fid, childId: t.childId))
                    + [.pediatricTreatmentDetail(familyId: fid, childId: t.childId, treatmentId: t.id)]
                : [.petsHome(familyId: fid), .petDetail(familyId: fid, petId: t.petId)]
        case .ticket(let t):
            routes = [.walletHome(familyId: fid), .walletTicketDetail(familyId: fid, ticketId: t.id)]
        case .homeItem(let h):
            routes = [.homeItemsHome(familyId: fid), .homeItemDetail(familyId: fid, itemId: h.id)]
        case .housePayment(let p):
            routes = [.homeItemsHome(familyId: fid), .housePaymentDetail(familyId: fid, paymentId: p.id)]
        case .vehicle(let v):
            routes = [.vehiclesHome(familyId: fid), .vehicleDetail(familyId: fid, vehicleId: v.id)]
        case .pet(let p):
            routes = [.petsHome(familyId: fid), .petDetail(familyId: fid, petId: p.id)]
        case .trip(let t):
            routes = [.travelList(familyId: fid), .travelTripDetail(familyId: fid, tripId: t.id)]
        }
        return Destination(routes: routes, found: true)
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

    /// Parole che non distinguono una voce dall'altra: «Referto gastroscopia»
    /// deve trovare la visita «Gastroscopia».
    private static let stopwords: Set<String> = [
        "del", "della", "dello", "dei", "degli", "delle", "per", "con", "dal", "alla", "allo",
        "referto", "referti", "visita", "visite", "esame", "esami", "documento", "allegato",
        "risultato", "risultati", "cura", "terapia", "spesa", "nota",
    ]

    private static func words(_ text: String) -> Set<String> {
        let parts: [Substring] = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return Set(parts.filter { $0.count > 2 }.map(String.init)).subtracting(stopwords)
    }

    /// Titoli dei documenti allegati a una voce (tag `visit:<id>`…).
    private static func attachmentTitles(_ tag: String, _ s: AgentMemorySnapshot) -> [String] {
        s.documents.filter { $0.notes == tag }.map(\.title)
    }

    static func best<T>(_ items: [T], _ link: Link, title: (T) -> String, date: (T) -> Date) -> T? {
        best(items, link, texts: { [title($0)] }, date: date)
    }

    /// La voce più simile al titolo: uguale, poi contenuta, poi più di metà
    /// delle parole in comune. Il primo testo è il nome della voce, gli altri
    /// (diagnosi, referti allegati) contano meno. Con `dayIsIdentity` il giorno
    /// indicato basta anche senza parole in comune. A parità vince il giorno
    /// indicato, poi la più recente.
    static func best<T>(_ items: [T], _ link: Link, texts: (T) -> [String], date: (T) -> Date, dayIsIdentity: Bool = false) -> T? {
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
            var score = 0
            for (index, raw) in texts(item).enumerated() {
                let t = AgentRelevance.fold(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { continue }
                let primary = index == 0
                var textScore = 0
                if t == wanted {
                    textScore = primary ? 1000 : 400
                } else if t.contains(wanted) || (!words(t).isEmpty && wanted.contains(t)) {
                    textScore = primary ? 500 : 300
                } else {
                    let common = words(t).intersection(wantedWords).count
                    // Più di metà delle parole chieste: una parola sola in comune
                    // («Bolletta gas» per «Bolletta luce») non è la voce cercata.
                    if common > 0, common * 2 > wantedWords.count { textScore = 100 * common }
                }
                score = max(score, textScore)
            }
            let d = date(item)
            if dayIsIdentity, let day, Calendar.current.isDate(d, inSameDayAs: day) { score += 50 }
            guard score > 0 else { continue }
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
