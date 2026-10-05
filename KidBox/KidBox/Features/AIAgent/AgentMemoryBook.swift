//
//  AgentMemoryBook.swift
//  KidBox
//
//  La memoria dell'assistente unico: una scheda markdown per ogni sezione
//  dell'app, costruita sul dispositivo dai dati locali a ogni domanda.
//  Disegno, budget e regole in `internal/assistente-unico.md`; Android
//  (`AgentMemoryBook.kt`) e web (`memoryBook.js`) costruiscono le stesse schede.
//
//  Le schede di salute riusano `HealthContextBuilder` (lo stesso della chat
//  Salute, scopo `.agentMemory`): referti, Apple Salute e formati non si
//  riscrivono qui.
//

import Foundation
import SwiftData
import FirebaseAuth

// MARK: - Focus

/// Da dove si è aperto l'assistente. Arriva dai pulsanti di Salute: la
/// conversazione resta una sola, il focus cambia solo il contesto.
struct AgentFocus: Hashable {

    enum Scope: Hashable {
        case person
        case visits
        case visit(id: String)
        case exams
        case exam(id: String)
    }

    /// `childId` per un figlio, `userId` per un adulto: è la chiave dei dati sanitari.
    let personId: String
    let personName: String
    let scope: Scope
    /// Titolo della visita o dell'esame, già pronto per l'etichetta.
    let detail: String?

    init(personId: String, personName: String, scope: Scope = .person, detail: String? = nil) {
        self.personId = personId
        self.personName = personName
        self.scope = scope
        self.detail = detail
    }

    /// Etichetta sotto l'intestazione della chat.
    var label: String {
        switch scope {
        case .person:
            return String(format: NSLocalizedString("Salute di %@", comment: "Assistant focus label: health of a person"), personName)
        case .visits:
            return String(format: NSLocalizedString("Visite di %@", comment: "Assistant focus label: visits of a person"), personName)
        case .exams:
            return String(format: NSLocalizedString("Esami di %@", comment: "Assistant focus label: exams of a person"), personName)
        case .visit, .exam:
            guard let detail, !detail.isEmpty else { return personName }
            return "\(detail) · \(personName)"
        }
    }

    /// Riga del prompt: cosa stava guardando l'utente. Con gli esempi: scritta
    /// solo come «le domande senza soggetto si riferiscono a questo», Haiku
    /// rispondeva sulla famiglia intera. Stesso testo su Android e web.
    var promptLine: String {
        let what: String
        switch scope {
        case .person: what = "la salute di \(personName)"
        case .visits: what = "le visite di \(personName)"
        case .visit:  what = "la visita «\(detail ?? "")» di \(personName)"
        case .exams:  what = "gli esami di \(personName)"
        case .exam:   what = "l'esame «\(detail ?? "")» di \(personName)"
        }
        return """
        FOCUS DI QUESTA CONVERSAZIONE: l'utente ha aperto l'assistente da Salute, guardando \(what). \
        Le domande che non nominano altro («cosa devo fare?», «cosa dice il referto?», «è grave?») riguardano \(what): \
        rispondi su quello, non sul resto della famiglia. Se chiede esplicitamente d'altro, rispondi d'altro.
        """
    }

    /// Domande d'esempio a tema per la schermata vuota.
    var suggestions: [String] {
        switch scope {
        case .person:
            return [
                String(format: NSLocalizedString("Riassumimi la salute di %@", comment: "Assistant suggestion"), personName),
                NSLocalizedString("Ci sono esami, vaccini o visite da fare?", comment: "Assistant suggestion"),
                NSLocalizedString("Spiegami l'ultimo referto", comment: "Assistant suggestion"),
            ]
        case .visits:
            return [
                String(format: NSLocalizedString("Riassumimi le ultime visite di %@", comment: "Assistant suggestion"), personName),
                NSLocalizedString("Ci sono controlli da prenotare?", comment: "Assistant suggestion"),
            ]
        case .visit:
            return [
                NSLocalizedString("Spiegami questa visita", comment: "Assistant suggestion"),
                NSLocalizedString("Cosa dice il referto?", comment: "Assistant suggestion"),
                NSLocalizedString("Cosa devo fare adesso?", comment: "Assistant suggestion"),
            ]
        case .exams:
            return [
                String(format: NSLocalizedString("Ci sono valori fuori norma negli esami di %@?", comment: "Assistant suggestion"), personName),
                NSLocalizedString("Quali esami sono ancora da fare?", comment: "Assistant suggestion"),
            ]
        case .exam:
            return [
                NSLocalizedString("Cosa significano questi valori?", comment: "Assistant suggestion"),
                NSLocalizedString("È tutto nella norma?", comment: "Assistant suggestion"),
            ]
        }
    }
}

// MARK: - Snapshot

/// Tutti i dati della famiglia attiva che l'assistente può vedere, letti una
/// volta per domanda. Le voci «solo per me» degli altri membri sono già fuori.
@MainActor
struct AgentMemorySnapshot {
    let familyId: String
    let familyName: String
    let uid: String?
    let members: [KBFamilyMember]
    let children: [KBChild]
    let profiles: [String: KBPediatricProfile]
    let events: [KBCalendarEvent]
    let todos: [KBTodoItem]
    let todoListNames: [String: String]
    let routines: [KBRoutine]
    let todayRoutineChecks: Set<String>
    let treatments: [KBTreatment]
    let visits: [KBMedicalVisit]
    let exams: [KBMedicalExam]
    let vaccines: [KBVaccine]
    let notes: [KBNote]
    let expenses: [KBExpense]
    let expenseCategoryNames: [String: String]
    let grocery: [KBGroceryItem]
    let chat: [KBChatMessage]
    let documents: [KBDocument]
    let documentCategoryNames: [String: String]
    let walletTickets: [KBWalletTicket]
    let loyaltyCards: [KBLoyaltyCard]
    let pets: [KBPet]
    let petEvents: [KBPetEvent]
    let homeItems: [KBHomeItem]
    let housePayments: [KBHousePayment]
    let vehicles: [KBVehicle]
    let vehicleEvents: [KBVehicleEvent]
    let trips: [KBTrip]
    let tripLegs: [KBTripLeg]
    let tripDays: [KBTripDayPlan]
    let memoryFacts: [String]

    static func load(familyId: String, familyName: String, modelContext: ModelContext) -> AgentMemorySnapshot {
        let uid = Auth.auth().currentUser?.uid
        let fid = familyId
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
            (try? modelContext.fetch(descriptor)) ?? []
        }

        let members = fetch(FetchDescriptor<KBFamilyMember>(predicate: #Predicate { $0.familyId == fid }))
            .filter { !$0.isDeleted }
        let children = fetch(FetchDescriptor<KBChild>())
            .filter { $0.familyId == fid }
            .sorted { ($0.birthDate ?? .distantFuture) < ($1.birthDate ?? .distantFuture) }
        let profiles = Dictionary(
            fetch(FetchDescriptor<KBPediatricProfile>(predicate: #Predicate { $0.familyId == fid }))
                .map { ($0.childId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let todayKey = Date().kbDayKey()
        let routineChecks = fetch(FetchDescriptor<KBRoutineCheck>(predicate: #Predicate { $0.familyId == fid }))
            .filter { !$0.isDeleted && $0.dayKey == todayKey }
        let todoLists = fetch(FetchDescriptor<KBTodoList>(predicate: #Predicate { $0.familyId == fid }))
            .filter { !$0.isDeleted }
        let expenseCategories = fetch(FetchDescriptor<KBExpenseCategory>(predicate: #Predicate { $0.familyId == fid }))
            .filter { !$0.isDeleted }
        let documentCategories = fetch(FetchDescriptor<KBDocumentCategory>(predicate: #Predicate { $0.familyId == fid }))
            .filter { !$0.isDeleted }
        let facts = FamilyMemoryService.shared.fetchFacts(for: familyId, modelContext: modelContext).map(\.content)

        return AgentMemorySnapshot(
            familyId: familyId,
            familyName: familyName,
            uid: uid,
            members: members,
            children: children,
            profiles: profiles,
            events: fetch(FetchDescriptor<KBCalendarEvent>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted && $0.isVisible(to: uid) },
            todos: fetch(FetchDescriptor<KBTodoItem>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted && $0.isVisible(to: uid) },
            todoListNames: Dictionary(todoLists.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }),
            routines: fetch(FetchDescriptor<KBRoutine>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted && $0.isActive },
            todayRoutineChecks: Set(routineChecks.map(\.routineId)),
            treatments: fetch(FetchDescriptor<KBTreatment>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted },
            visits: fetch(FetchDescriptor<KBMedicalVisit>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted },
            exams: fetch(FetchDescriptor<KBMedicalExam>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted },
            vaccines: fetch(FetchDescriptor<KBVaccine>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted },
            notes: fetch(FetchDescriptor<KBNote>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted && $0.isVisible(to: uid) }
                .sorted { $0.updatedAt > $1.updatedAt },
            expenses: fetch(FetchDescriptor<KBExpense>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted }
                .sorted { $0.date > $1.date },
            expenseCategoryNames: Dictionary(expenseCategories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }),
            grocery: fetch(FetchDescriptor<KBGroceryItem>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted },
            chat: fetch(FetchDescriptor<KBChatMessage>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted && !$0.isDeletedForEveryone }
                .sorted { $0.createdAt < $1.createdAt },
            documents: fetch(FetchDescriptor<KBDocument>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted && $0.isVisibleToCurrentUser(currentUid: uid) }
                .sorted { $0.updatedAt > $1.updatedAt },
            documentCategoryNames: Dictionary(documentCategories.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first }),
            walletTickets: fetch(FetchDescriptor<KBWalletTicket>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted && $0.isVisible(to: uid) },
            loyaltyCards: fetch(FetchDescriptor<KBLoyaltyCard>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted && $0.isVisible(to: uid) },
            pets: fetch(FetchDescriptor<KBPet>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted },
            petEvents: fetch(FetchDescriptor<KBPetEvent>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted },
            homeItems: fetch(FetchDescriptor<KBHomeItem>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted },
            housePayments: fetch(FetchDescriptor<KBHousePayment>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted },
            vehicles: fetch(FetchDescriptor<KBVehicle>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted },
            vehicleEvents: fetch(FetchDescriptor<KBVehicleEvent>(predicate: #Predicate { $0.familyId == fid }))
                .filter { !$0.isDeleted },
            trips: fetch(FetchDescriptor<KBTrip>(predicate: #Predicate { $0.familyId == fid })),
            tripLegs: fetch(FetchDescriptor<KBTripLeg>(predicate: #Predicate { $0.familyId == fid })),
            tripDays: fetch(FetchDescriptor<KBTripDayPlan>(predicate: #Predicate { $0.familyId == fid })),
            memoryFacts: facts
        )
    }

    // MARK: Derived

    /// Nome di chi ha un uid: membro della famiglia.
    func memberName(_ uid: String?) -> String? {
        guard let uid, !uid.isEmpty else { return nil }
        return members.first { $0.userId == uid }?.displayName
    }

    /// Nome di una persona per i dati sanitari (figlio o adulto).
    func personName(_ personId: String) -> String? {
        children.first { $0.id == personId }?.name ?? memberName(personId)
    }

    var openTodos: [KBTodoItem] { todos.filter { !$0.isDone } }
    var pendingGrocery: [KBGroceryItem] { grocery.filter { !$0.isPurchased } }
    /// Cure delle persone (quelle degli animali hanno `petId` e stanno in Animali).
    var personTreatments: [KBTreatment] { treatments.filter { $0.petId.isEmpty } }
    var activeTreatments: [KBTreatment] { personTreatments.filter { Self.isCurrent($0) } }

    /// Una cura è in corso se attiva e non finita: il flag `isActive` resta acceso
    /// anche dopo la data di fine. Stessa regola di Android (`isCurrentlyActive`) e web.
    static func isCurrent(_ t: KBTreatment, now: Date = Date()) -> Bool {
        t.isActive && (t.isLongTerm || t.endDate.map { $0 >= now } ?? true)
    }
    var visitsWithNextDate: [KBMedicalVisit] { visits.filter { $0.nextVisitDate != nil } }
}

// MARK: - Book

struct AgentMemoryFile {
    let name: String
    let title: String
    /// Una riga per l'indice.
    let summary: String
    let body: String
}

/// Un documento con testo letto che entra nel quaderno, in una scheda o nell'altra.
struct AgentTextDocument {
    let doc: KBDocument
    /// Lunghezza del testo ripulito, intero.
    let fullLength: Int
    /// Persona a cui si riferisce (allegati sanitari e documenti di un figlio).
    let personId: String?
    /// Dove sta: «visita di Marco del 12 marzo», «cartella Casa»…
    let place: String
}

struct AgentMemoryBook {
    let files: [AgentMemoryFile]

    /// Schede che cambiano fra una domanda e l'altra (un to-do spuntato, un
    /// articolo aggiunto, un messaggio in chat, il tempo che passa). Stanno in
    /// fondo, nel secondo blocco del prompt, così il resto del quaderno resta
    /// nella cache di Anthropic. Stesso elenco su Android e web.
    static let volatileFiles: Set<String> = ["oggi.md", "calendario.md", "todo.md", "spesa.md", "chat.md"]

    private func card(_ f: AgentMemoryFile) -> String {
        "<scheda file=\"\(f.name)\" titolo=\"\(f.title)\">\n\(f.body)\n</scheda>"
    }

    /// Indice e schede stabili. L'indice non porta i conteggi delle schede che
    /// cambiano: un numero diverso farebbe uscire tutto dalla cache.
    var stableRendered: String {
        var index = ["<indice>"]
        index += files.map { f in
            Self.volatileFiles.contains(f.name)
                ? "- \(f.name) — \(f.title): in fondo, aggiornata a ogni domanda"
                : "- \(f.name) — \(f.title): \(f.summary)"
        }
        index.append("</indice>")
        let cards = files.filter { !Self.volatileFiles.contains($0.name) }.map(card)
        return ([index.joined(separator: "\n")] + cards).joined(separator: "\n\n")
    }

    /// Le schede che cambiano, nell'ordine del quaderno.
    var volatileRendered: String {
        files.filter { Self.volatileFiles.contains($0.name) }.map(card).joined(separator: "\n\n")
    }
}

// MARK: - Builder

/// Costruisce le schede da uno snapshot. `docAllowance` nil = testi interi;
/// altrimenti caratteri concessi a ogni documento (0 = solo il titolo).
@MainActor
struct AgentMemoryBookBuilder {

    let snapshot: AgentMemorySnapshot
    let now: Date

    init(snapshot: AgentMemorySnapshot, now: Date = Date()) {
        self.snapshot = snapshot
        self.now = now
    }

    private var s: AgentMemorySnapshot { snapshot }

    // Finestre e tetti: abbastanza per «chiedere tutto» senza che una famiglia
    // con anni di dati gonfi il prompt. I testi letti dei documenti hanno il
    // loro budget (vedi `AgentContextFitter`).
    private static let calendarPastDays = 7
    private static let calendarFutureDays = 60
    private static let calendarMaxOccurrences = 150
    private static let noteBodyMaxChars = 1_500
    private static let notesTotalMaxChars = 20_000
    private static let expenseDetailDays = 90
    private static let chatMaxMessages = 30
    private static let documentIndexMax = 300

    // MARK: Text documents

    /// Tutti i documenti con testo letto che il quaderno può includere, con il
    /// posto dove compaiono. Gli identificativi del Wallet non ci sono mai: il
    /// loro testo contiene numeri e codici che l'assistente non deve vedere.
    func textDocuments() -> [AgentTextDocument] {
        s.documents.compactMap { doc in
            guard doc.extractionStatus == .completed, doc.hasExtractedText else { return nil }
            let home = home(of: doc)
            if case .wallet = home { return nil }
            let length = HealthAiDocumentText.sanitizeExtractedText(doc.extractedText ?? "").count
            guard length > 0 else { return nil }
            return AgentTextDocument(doc: doc, fullLength: length, personId: personId(of: doc, home: home), place: placeLabel(doc, home: home))
        }
    }

    // MARK: Build

    func build(docAllowance: [String: Int]?) -> AgentMemoryBook {
        var files: [AgentMemoryFile] = []
        files.append(familyFile())
        if let f = memoryFile() { files.append(f) }
        files.append(todayFile())
        files.append(calendarFile())
        files.append(todoFile())
        files.append(groceryFile())
        if let f = notesFile() { files.append(f) }
        if let f = expensesFile() { files.append(f) }
        files.append(contentsOf: healthFiles(docAllowance: docAllowance))
        files.append(documentsFile(docAllowance: docAllowance))
        if let f = walletFile() { files.append(f) }
        if let f = homeFile(docAllowance: docAllowance) { files.append(f) }
        if let f = vehiclesFile(docAllowance: docAllowance) { files.append(f) }
        if let f = petsFile(docAllowance: docAllowance) { files.append(f) }
        if let f = tripsFile() { files.append(f) }
        if let f = chatFile() { files.append(f) }
        return AgentMemoryBook(files: files)
    }

    // MARK: famiglia.md

    private func familyFile() -> AgentMemoryFile {
        var lines = ["# Famiglia \(s.familyName)"]
        if let me = s.memberName(s.uid) { lines.append("Sta scrivendo: \(me)") }
        let adults = s.members.compactMap { m -> String? in
            guard let name = m.displayName, !name.isEmpty else { return nil }
            return m.role == "admin" ? "\(name) (amministratore)" : name
        }
        if !adults.isEmpty {
            lines.append("\n## Adulti")
            lines += adults.map { "- \($0)" }
        }
        if !s.children.isEmpty {
            lines.append("\n## Figli")
            for c in s.children {
                var line = "- \(c.name)"
                if let bd = c.birthDate {
                    line += ", \(c.ageDescription) (nato/a il \(fmtDate(bd)))"
                    // Prossimo compleanno già calcolato: lasciato al modello, lo
                    // sbagliava («compie 1 anno» a una bambina di tre).
                    if let next = nextBirthday(bd) {
                        let turning = Calendar.current.component(.year, from: next) - Calendar.current.component(.year, from: bd)
                        line += " — prossimo compleanno: \(fmtWeekday(next)), compie \(turning) anni"
                    }
                }
                lines.append(line)
            }
        }
        if !s.pets.isEmpty {
            lines.append("\n## Animali")
            lines += s.pets.map { "- \($0.name) (\($0.species))" }
        }
        let summary = "\(adults.count) adulti, \(s.children.count) figli, \(s.pets.count) animali"
        return AgentMemoryFile(name: "famiglia.md", title: "Famiglia", summary: summary, body: lines.joined(separator: "\n"))
    }

    private func nextBirthday(_ birth: Date) -> Date? {
        let cal = Calendar.current
        let parts = cal.dateComponents([.month, .day], from: birth)
        return cal.nextDate(after: cal.startOfDay(for: now).addingTimeInterval(-1), matching: parts, matchingPolicy: .nextTimePreservingSmallerComponents)
    }

    // MARK: ricordi.md

    private func memoryFile() -> AgentMemoryFile? {
        guard !s.memoryFacts.isEmpty else { return nil }
        var lines = ["# Ricordi", "Fatti emersi dalle conversazioni passate. Usali per personalizzare senza citarli se non serve."]
        lines += s.memoryFacts.map { "- \($0)" }
        return AgentMemoryFile(name: "ricordi.md", title: "Ricordi", summary: "\(s.memoryFacts.count) fatti", body: lines.joined(separator: "\n"))
    }

    // MARK: oggi.md

    private func todayFile() -> AgentMemoryFile {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? now
        let today = occurrences(in: DateInterval(start: startOfDay, end: endOfDay))

        var lines = ["# Oggi, \(fmtWeekday(now))"]
        if today.isEmpty {
            lines.append("Nessun evento in calendario.")
        } else {
            lines.append("## Eventi")
            lines += today.map { "- \(eventLine($0))" }
        }
        let urgent = s.openTodos.filter { $0.priorityRaw == 1 || ($0.dueAt.map { $0 <= endOfDay } ?? false) }
        if !urgent.isEmpty {
            lines.append("## To-do urgenti o in scadenza")
            lines += urgent.prefix(20).map { "- \(todoLine($0))" }
        }
        let unchecked = s.routines.filter { !s.todayRoutineChecks.contains($0.id) }
        if !unchecked.isEmpty {
            lines.append("## Routine non ancora fatte")
            lines += unchecked.map { "- \($0.title) (\(s.personName($0.childId) ?? "—"))" }
        }
        let doses = s.activeTreatments.flatMap { t in
            t.scheduleTimes.map { "- ore \($0): \(t.drugName) \(fmtNumber(t.dosageValue)) \(t.dosageUnit) (\(s.personName(t.childId) ?? "—"))" }
        }
        if !doses.isEmpty {
            lines.append("## Dosi di farmaci")
            lines += doses.sorted()
        }
        let summary = "\(today.count) eventi, \(urgent.count) to-do urgenti, \(doses.count) dosi"
        return AgentMemoryFile(name: "oggi.md", title: "Oggi", summary: summary, body: lines.joined(separator: "\n"))
    }

    // MARK: calendario.md

    private func calendarFile() -> AgentMemoryFile {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -Self.calendarPastDays, to: cal.startOfDay(for: now)) ?? now
        let end = cal.date(byAdding: .day, value: Self.calendarFutureDays, to: now) ?? now
        let all = occurrences(in: DateInterval(start: start, end: end))
        let shown = Array(all.prefix(Self.calendarMaxOccurrences))

        var lines = ["# Calendario", "Dal \(fmtDate(start)) al \(fmtDate(end)). Gli eventi ricorrenti compaiono in ogni ripetizione."]
        if shown.isEmpty {
            lines.append("Nessun evento in questo periodo.")
        }
        var currentDay = ""
        for occ in shown {
            let day = fmtWeekday(occ.startDate)
            if day != currentDay {
                lines.append("\n## \(day)")
                currentDay = day
            }
            lines.append("- \(eventLine(occ))")
        }
        if all.count > shown.count {
            lines.append("\n(Altre \(all.count - shown.count) ripetizioni oltre il limite non elencate.)")
        }
        let upcoming = all.filter { $0.startDate >= now }.count
        return AgentMemoryFile(name: "calendario.md", title: "Calendario", summary: "\(upcoming) eventi nei prossimi \(Self.calendarFutureDays) giorni, ricorrenze comprese", body: lines.joined(separator: "\n"))
    }

    private func occurrences(in window: DateInterval) -> [KBEventOccurrence] {
        s.events
            .flatMap { $0.occurrences(in: window) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func eventLine(_ occ: KBEventOccurrence) -> String {
        let e = occ.event
        var line = e.isAllDay ? "tutto il giorno" : "\(fmtTime(occ.startDate))–\(fmtTime(occ.endDate))"
        line += " \(e.title)"
        if let child = e.childId.flatMap({ s.personName($0) }) { line += " (\(child))" }
        line += " [\(e.category.label)]"
        if let loc = e.location, !loc.isEmpty { line += " @ \(loc)" }
        if e.recurrence != .none { line += " — \(e.recurrence.label)" }
        if let notes = e.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            line += " — note: \(clip(notes, 120))"
        }
        return line
    }

    // MARK: todo.md

    private func todoFile() -> AgentMemoryFile {
        let open = s.openTodos
        let overdue = open.filter { ($0.dueAt.map { $0 < now } ?? false) }.sorted { ($0.dueAt ?? now) < ($1.dueAt ?? now) }
        let dated = open.filter { ($0.dueAt.map { $0 >= now } ?? false) }.sorted { ($0.dueAt ?? now) < ($1.dueAt ?? now) }
        let undated = open.filter { $0.dueAt == nil }.sorted { ($0.priorityRaw ?? 0) > ($1.priorityRaw ?? 0) }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let done = s.todos.filter { $0.isDone && ($0.doneAt.map { $0 >= weekAgo } ?? false) }
            .sorted { ($0.doneAt ?? now) > ($1.doneAt ?? now) }

        var lines = ["# To-do"]
        if open.isEmpty { lines.append("Nessun to-do aperto.") }
        if !overdue.isEmpty {
            lines.append("\n## Scaduti (\(overdue.count))")
            lines += overdue.prefix(40).map { "- \(todoLine($0))" }
        }
        if !dated.isEmpty {
            lines.append("\n## Con scadenza (\(dated.count))")
            lines += dated.prefix(60).map { "- \(todoLine($0))" }
        }
        if !undated.isEmpty {
            lines.append("\n## Senza data (\(undated.count))")
            lines += undated.prefix(60).map { "- \(todoLine($0))" }
        }
        if !done.isEmpty {
            lines.append("\n## Fatti negli ultimi 7 giorni")
            lines += done.prefix(20).map { t in
                var line = "- \(t.title)"
                if let by = s.memberName(t.doneBy) { line += " — fatto da \(by)" }
                if let at = t.doneAt { line += " il \(fmtDate(at))" }
                return line
            }
        }
        return AgentMemoryFile(name: "todo.md", title: "To-do", summary: "\(open.count) aperti, \(overdue.count) scaduti", body: lines.joined(separator: "\n"))
    }

    private func todoLine(_ t: KBTodoItem) -> String {
        var line = t.title
        if t.priorityRaw == 1 { line += " [URGENTE]" }
        if let due = t.dueAt { line += " — scadenza \(t.hasDueTime ? fmtDateTime(due) : fmtDate(due))" }
        if let who = s.memberName(t.assignedTo) {
            line += " → \(who)"
        } else if let ext = t.assignedExternalName, !ext.isEmpty {
            line += " → \(ext) (fuori dall'app)"
        }
        if let list = t.listId.flatMap({ s.todoListNames[$0] }) { line += " · lista \(list)" }
        if let notes = t.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            line += " — \(clip(notes, 120))"
        }
        return line
    }

    // MARK: spesa.md

    private func groceryFile() -> AgentMemoryFile {
        let pending = s.pendingGrocery
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let bought = s.grocery.filter { $0.isPurchased && ($0.purchasedAt.map { $0 >= weekAgo } ?? false) }

        var lines = ["# Lista della spesa"]
        if pending.isEmpty {
            lines.append("Niente da comprare.")
        } else {
            lines.append("\n## Da comprare (\(pending.count))")
            let grouped = Dictionary(grouping: pending) { $0.category?.isEmpty == false ? $0.category! : "Altro" }
            for (category, items) in grouped.sorted(by: { $0.key < $1.key }) {
                let names = items.map { item -> String in
                    var name = item.name
                    if let q = item.quantity, q > 1 { name += " ×\(q)" }
                    if let by = s.memberName(item.createdBy) { name += " (da \(by))" }
                    return name
                }
                lines.append("- [\(category)] \(names.joined(separator: ", "))")
            }
        }
        if !bought.isEmpty {
            lines.append("\n## Comprati negli ultimi 7 giorni")
            lines.append(bought.prefix(30).map(\.name).joined(separator: ", "))
        }
        return AgentMemoryFile(name: "spesa.md", title: "Lista della spesa", summary: "\(pending.count) articoli da comprare", body: lines.joined(separator: "\n"))
    }

    // MARK: note.md

    private func notesFile() -> AgentMemoryFile? {
        guard !s.notes.isEmpty else { return nil }
        var lines = ["# Note"]
        var used = 0
        var titlesOnly: [String] = []
        for n in s.notes {
            let title = n.title.isEmpty ? "(senza titolo)" : n.title
            let body = NoteHtmlSanitizer.plainText(from: n.body).trimmingCharacters(in: .whitespacesAndNewlines)
            let author = s.memberName(n.updatedBy) ?? (n.updatedByName.isEmpty ? nil : n.updatedByName)
            guard used < Self.notesTotalMaxChars else {
                titlesOnly.append(title)
                continue
            }
            let clipped = clip(body, Self.noteBodyMaxChars)
            used += clipped.count
            lines.append("\n## \(title)")
            lines.append("Aggiornata il \(fmtDate(n.updatedAt))\(author.map { " da \($0)" } ?? "")")
            if !clipped.isEmpty { lines.append(clipped) }
        }
        if !titlesOnly.isEmpty {
            lines.append("\n## Altre note (solo titolo)")
            lines += titlesOnly.map { "- \($0)" }
        }
        return AgentMemoryFile(name: "note.md", title: "Note", summary: "\(s.notes.count) note", body: lines.joined(separator: "\n"))
    }

    // MARK: spese.md

    private func expensesFile() -> AgentMemoryFile? {
        guard !s.expenses.isEmpty else { return nil }
        let cal = Calendar.current
        let detailCutoff = cal.date(byAdding: .day, value: -Self.expenseDetailDays, to: now) ?? now
        let yearCutoff = cal.date(byAdding: .month, value: -12, to: now) ?? now
        let category = { (e: KBExpense) in e.categoryId.flatMap { s.expenseCategoryNames[$0] } ?? "Altro" }

        var lines = ["# Spese"]
        let recent = s.expenses.filter { $0.date >= detailCutoff }
        lines.append("\n## Voci degli ultimi \(Self.expenseDetailDays) giorni (\(recent.count))")
        for e in recent.prefix(80) {
            var line = "- \(fmtDate(e.date)) — \(e.title): \(fmtEuro(e.amount)) [\(category(e))]"
            if let who = s.memberName(e.createdByUid) { line += " — \(who)" }
            if let notes = e.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty { line += " (\(clip(notes, 80)))" }
            lines.append(line)
        }

        let lastYear = s.expenses.filter { $0.date >= yearCutoff }
        let monthFmt = DateFormatter()
        monthFmt.locale = kbDeviceLocale()
        monthFmt.dateFormat = "MMMM yyyy"
        let byMonth = Dictionary(grouping: lastYear) { cal.dateComponents([.year, .month], from: $0.date) }
        if !byMonth.isEmpty {
            lines.append("\n## Totale per mese (ultimi 12 mesi)")
            for (comps, items) in byMonth.sorted(by: { ($0.key.year ?? 0, $0.key.month ?? 0) > ($1.key.year ?? 0, $1.key.month ?? 0) }) {
                guard let date = cal.date(from: comps) else { continue }
                lines.append("- \(monthFmt.string(from: date)): \(fmtEuro(items.reduce(0) { $0 + $1.amount })) (\(items.count) voci)")
            }
        }
        let thisYear = cal.component(.year, from: now)
        let yearItems = s.expenses.filter { cal.component(.year, from: $0.date) == thisYear }
        let byCategory = Dictionary(grouping: yearItems, by: category)
        if !byCategory.isEmpty {
            lines.append("\n## Totale per categoria nel \(thisYear)")
            for (name, items) in byCategory.sorted(by: { $0.value.reduce(0) { $0 + $1.amount } > $1.value.reduce(0) { $0 + $1.amount } }) {
                lines.append("- \(name): \(fmtEuro(items.reduce(0) { $0 + $1.amount }))")
            }
        }
        let total = recent.reduce(0) { $0 + $1.amount }
        return AgentMemoryFile(name: "spese.md", title: "Spese", summary: "\(recent.count) voci negli ultimi \(Self.expenseDetailDays) giorni, \(fmtEuro(total))", body: lines.joined(separator: "\n"))
    }

    // MARK: salute-<nome>.md

    private struct HealthPerson {
        let id: String
        let name: String
        let child: KBChild?
    }

    /// Figli sempre (anche senza dati: il profilo serve), adulti solo se hanno
    /// qualcosa di sanitario registrato.
    private var healthPersons: [HealthPerson] {
        var out = s.children.map { HealthPerson(id: $0.id, name: $0.name, child: $0) }
        for m in s.members {
            guard let name = m.displayName, !name.isEmpty else { continue }
            let id = m.userId
            let hasData = s.visits.contains { $0.childId == id }
                || s.exams.contains { $0.childId == id }
                || s.personTreatments.contains { $0.childId == id }
                || s.vaccines.contains { $0.childId == id }
            if hasData { out.append(HealthPerson(id: id, name: name, child: nil)) }
        }
        return out
    }

    /// Nome della scheda salute di una persona (`salute-marco.md`).
    static func healthFileName(for name: String) -> String {
        "salute-\(slug(name)).md"
    }

    private func healthFiles(docAllowance: [String: Int]?) -> [AgentMemoryFile] {
        let docsByTag = Dictionary(grouping: s.documents.filter { $0.notes != nil }) { $0.notes ?? "" }
        var usedNames = Set<String>()
        return healthPersons.map { person in
            var fileName = Self.healthFileName(for: person.name)
            if usedNames.contains(fileName) { fileName = "salute-\(Self.slug(person.name))-\(usedNames.count + 1).md" }
            usedNames.insert(fileName)

            let exams = s.exams.filter { $0.childId == person.id }
            let visits = s.visits.filter { $0.childId == person.id }
            let treatments = s.personTreatments.filter { $0.childId == person.id }
            let vaccines = s.vaccines.filter { $0.childId == person.id }
            let active = treatments.filter { AgentMemorySnapshot.isCurrent($0, now: now) }

            var lines = ["# Salute di \(person.name)"]
            lines += profileLines(person)
            lines += pastTreatmentLines(treatments.filter { !AgentMemorySnapshot.isCurrent($0, now: now) })
            lines.append(HealthContextBuilder.buildSystemPrompt(
                subjectName: person.name,
                subjectId: person.id,
                exams: exams,
                visits: visits,
                treatments: active,
                vaccines: vaccines,
                documentsByExamId: Dictionary(exams.map { ($0.id, docsByTag[ExamAttachmentTag.make($0.id)] ?? []) }, uniquingKeysWith: { a, _ in a }),
                documentsByVisitId: Dictionary(visits.map { ($0.id, docsByTag["visit:\($0.id)"] ?? []) }, uniquingKeysWith: { a, _ in a }),
                documentsByTreatmentId: Dictionary(active.map { ($0.id, docsByTag["treatment:\($0.id)"] ?? []) }, uniquingKeysWith: { a, _ in a }),
                // Senza budget il referto va intero (la «massima accuratezza»
                // della chat Salute); col budget decide `docAllowance`.
                refertoMaxChars: docAllowance == nil ? nil : HealthAiDocumentText.standardRefertoMaxChars,
                refertoMaxCharsByDocId: docAllowance,
                healthSnapshot: KBHealthLinkStore.load(childId: person.id),
                subjectBirthDate: person.child?.birthDate,
                visitsForWearableContext: visits,
                purpose: .agentMemory
            ))
            let referti = s.documents.filter { doc in
                guard doc.extractionStatus == .completed, doc.hasExtractedText, let tag = doc.notes else { return false }
                return exams.contains { tag == ExamAttachmentTag.make($0.id) }
                    || visits.contains { tag == "visit:\($0.id)" }
                    || active.contains { tag == "treatment:\($0.id)" }
            }.count
            let summary = "\(active.count) cure attive, \(visits.count) visite, \(exams.count) esami, \(vaccines.count) vaccini, \(referti) referti letti"
            return AgentMemoryFile(name: fileName, title: "Salute di \(person.name)", summary: summary, body: lines.joined(separator: "\n"))
        }
    }

    private func profileLines(_ person: HealthPerson) -> [String] {
        var lines = ["\n--- PROFILO PERSONALE ---"]
        if let child = person.child {
            if let bd = child.birthDate { lines.append("Data di nascita: \(fmtDate(bd)) (\(child.ageDescription))") }
            if let w = child.weightKg { lines.append("Peso: \(fmtNumber(w, decimals: 1)) kg") }
            if let h = child.heightCm { lines.append("Altezza: \(fmtNumber(h)) cm") }
        } else {
            lines.append("Adulto della famiglia")
        }
        if let p = s.profiles[person.id] {
            if let v = p.bloodGroup, !v.isEmpty { lines.append("Gruppo sanguigno: \(v)") }
            if let v = p.allergies, !v.isEmpty { lines.append("Allergie: \(v)") }
            if let v = p.medicalNotes, !v.isEmpty { lines.append("Note mediche: \(v)") }
            if let v = p.doctorName, !v.isEmpty { lines.append("\(person.child == nil ? "Medico" : "Pediatra"): \(v)") }
            if let v = p.doctorPhone, !v.isEmpty { lines.append("Telefono del medico: \(v)") }
            if let v = p.doctorEmail, !v.isEmpty { lines.append("Email del medico: \(v)") }
            if let v = p.doctorAddress, !v.isEmpty { lines.append("Studio: \(v)") }
            for line in p.doctorOfficeHours.groupedOfficeHourDisplayLines { lines.append("Orario \(line)") }
        }
        return lines
    }

    private func pastTreatmentLines(_ past: [KBTreatment]) -> [String] {
        let twoYears = Calendar.current.date(byAdding: .year, value: -2, to: now) ?? now
        let recent = past.filter { $0.startDate >= twoYears }.sorted { $0.startDate > $1.startDate }
        guard !recent.isEmpty else { return [] }
        var lines = ["\n--- CURE CONCLUSE (ultimi 2 anni) ---"]
        for t in recent.prefix(20) {
            var line = "• \(t.drugName) \(fmtNumber(t.dosageValue)) \(t.dosageUnit) — dal \(fmtDate(t.startDate))"
            if let end = t.endDate { line += " al \(fmtDate(end))" }
            if let n = t.notes, !n.isEmpty { line += " — \(clip(n, 80))" }
            lines.append(line)
        }
        return lines
    }

    // MARK: documenti.md

    private enum DocHome {
        case health(personId: String, label: String)
        case home(label: String)
        case vehicle(label: String)
        case pet(label: String)
        case expense(label: String)
        case wallet(kind: String)
        case general
    }

    private func home(of doc: KBDocument) -> DocHome {
        guard let tag = doc.notes, let colon = tag.firstIndex(of: ":") else { return .general }
        if tag.hasPrefix(KBWalletDocumentKind.notesPrefix) {
            return .wallet(kind: doc.walletDocumentKind?.displayName ?? "Documento")
        }
        let prefix = String(tag[..<colon])
        let id = String(tag[tag.index(after: colon)...])
        switch prefix {
        case "visit":
            guard let v = s.visits.first(where: { $0.id == id }) else { return .general }
            return .health(personId: v.childId, label: "visita del \(fmtDate(v.date))\(v.reason.isEmpty ? "" : " (\(v.reason))")")
        case "exam":
            guard let e = s.exams.first(where: { $0.id == id }) else { return .general }
            return .health(personId: e.childId, label: "esame \(e.name)")
        case "treatment":
            guard let t = s.treatments.first(where: { $0.id == id }), t.petId.isEmpty else { return .general }
            return .health(personId: t.childId, label: "cura \(t.drugName)")
        case "homeItem":
            return .home(label: s.homeItems.first { $0.id == id }?.name ?? "oggetto di casa")
        case "housePayment":
            return .home(label: s.housePayments.first { $0.id == id }?.name ?? "scadenza di casa")
        case "vehicle":
            return .vehicle(label: s.vehicles.first { $0.id == id }?.name ?? "veicolo")
        case "vehicleEvent":
            return .vehicle(label: s.vehicleEvents.first { $0.id == id }?.title ?? "intervento")
        case "pet":
            return .pet(label: s.pets.first { $0.id == id }?.name ?? "animale")
        case "petEvent":
            return .pet(label: s.petEvents.first { $0.id == id }?.title ?? "evento veterinario")
        case "expense":
            return .expense(label: s.expenses.first { $0.id == id }?.title ?? "spesa")
        default:
            return .general
        }
    }

    private func personId(of doc: KBDocument, home: DocHome) -> String? {
        if case .health(let personId, _) = home { return personId }
        return doc.childId
    }

    private func placeLabel(_ doc: KBDocument, home: DocHome) -> String {
        switch home {
        case .health(let personId, let label): return "Salute di \(s.personName(personId) ?? "—"), \(label)"
        case .home(let label): return "Casa, \(label)"
        case .vehicle(let label): return "Veicoli, \(label)"
        case .pet(let label): return "Animali, \(label)"
        case .expense(let label): return "ricevuta della spesa «\(label)»"
        case .wallet(let kind): return "Wallet, \(kind)"
        case .general:
            let folder = doc.categoryId.flatMap { s.documentCategoryNames[$0] }
            return folder.map { "cartella \($0)" } ?? "Documenti"
        }
    }

    private func documentsFile(docAllowance: [String: Int]?) -> AgentMemoryFile {
        let docs = s.documents
        var lines = ["# Documenti", "\n## Elenco (\(docs.count), i più recenti prima)"]
        for doc in docs.prefix(Self.documentIndexMax) {
            let home = home(of: doc)
            var line = "- \(doc.title) — \(placeLabel(doc, home: home))"
            if let person = doc.childId.flatMap({ s.personName($0) }), case .general = home { line += ", di \(person)" }
            line += " · \(fmtDate(doc.createdAt)) · \(fileKind(doc))"
            if case .wallet = home {
                // Il testo dei documenti d'identità non entra mai.
            } else if doc.extractionStatus == .completed && doc.hasExtractedText {
                line += " · testo letto"
            } else if doc.extractionStatus == .pending || doc.extractionStatus == .processing {
                line += " · lettura in corso"
            }
            lines.append(line)
        }
        if docs.count > Self.documentIndexMax {
            lines.append("(Altri \(docs.count - Self.documentIndexMax) documenti più vecchi non elencati.)")
        }

        // Testo dei documenti che non hanno una scheda propria: gli allegati di
        // salute, casa, veicoli e animali compaiono nelle loro schede.
        let general = textDocuments().filter { item in
            switch home(of: item.doc) {
            case .general, .expense: return true
            default: return false
            }
        }
        var clipped = 0
        var omitted = 0
        if !general.isEmpty {
            lines.append("\n## Testo letto dei documenti")
            for item in general {
                let text = documentText(item.doc, allowance: docAllowance)
                switch text.state {
                case .full: break
                case .clipped: clipped += 1
                case .omitted: omitted += 1
                }
                lines.append("\n### \(item.doc.title) (\(item.place), \(fmtDate(item.doc.createdAt)))")
                lines.append(text.body)
            }
        }
        var summary = "\(docs.count) documenti"
        let read = docs.filter { $0.extractionStatus == .completed && $0.hasExtractedText }.count
        if read > 0 { summary += ", \(read) con testo letto" }
        if clipped + omitted > 0 { summary += " (qui: \(clipped) testi accorciati e \(omitted) non inclusi per spazio)" }
        return AgentMemoryFile(name: "documenti.md", title: "Documenti", summary: summary, body: lines.joined(separator: "\n"))
    }

    private func fileKind(_ doc: KBDocument) -> String {
        if doc.isPDFDocument { return "PDF" }
        if doc.isImageDocument { return "immagine" }
        let ext = (doc.fileName as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "file" : ext
    }

    private enum TextState { case full, clipped, omitted }

    private func documentText(_ doc: KBDocument, allowance: [String: Int]?) -> (body: String, state: TextState) {
        let clean = HealthAiDocumentText.sanitizeExtractedText(doc.extractedText ?? "")
        guard let maxChars = allowance?[doc.id] else { return (clean, .full) }
        if maxChars <= 0 { return ("(testo letto non incluso per spazio)", .omitted) }
        guard clean.count > maxChars else { return (clean, .full) }
        return (String(clean.prefix(maxChars)) + "\n[… testo accorciato: \(maxChars) caratteri su \(clean.count)]", .clipped)
    }

    private func attachmentLines(_ tag: String, allowance: [String: Int]?, indent: String = "  ") -> [String] {
        s.documents
            .filter { $0.notes == tag && $0.extractionStatus == .completed && $0.hasExtractedText }
            .flatMap { doc -> [String] in
                let text = documentText(doc, allowance: allowance).body
                return ["\(indent)Allegato «\(doc.title)» — testo letto:"]
                    + text.split(separator: "\n", omittingEmptySubsequences: true).map { "\(indent)  \($0)" }
            }
    }

    // MARK: wallet.md

    private func walletFile() -> AgentMemoryFile? {
        let identity = s.documents.filter { $0.notes?.hasPrefix(KBWalletDocumentKind.notesPrefix) == true }
        guard !s.walletTickets.isEmpty || !identity.isEmpty || !s.loyaltyCards.isEmpty else { return nil }
        var lines = ["# Wallet"]
        if !s.walletTickets.isEmpty {
            lines.append("\n## Biglietti e prenotazioni")
            for t in s.walletTickets.sorted(by: { ($0.eventDate ?? .distantFuture) < ($1.eventDate ?? .distantFuture) }).prefix(30) {
                var line = "- \(t.title) [\(t.kindRaw)]"
                if let d = t.eventDate { line += " — \(fmtDateTime(d))" }
                if let end = t.eventEndDate { line += " → \(fmtDateTime(end))" }
                if let from = t.location, !from.isEmpty { line += " — da/luogo: \(from)" }
                if let to = t.arrivalLocation, !to.isEmpty { line += " — a: \(to)" }
                if let seat = t.seat, !seat.isEmpty { line += " — posto \(seat)" }
                if let holder = t.holderName, !holder.isEmpty { line += " — intestato a \(holder)" }
                if let emitter = t.emitter, !emitter.isEmpty { line += " — \(emitter)" }
                if let code = t.bookingCode, !code.isEmpty { line += " — prenotazione \(code)" }
                if let price = t.price, !price.isEmpty { line += " — \(price)" }
                lines.append(line)
            }
        }
        if !identity.isEmpty {
            lines.append("\n## Documenti d'identità (numeri e codici esclusi di proposito)")
            for doc in identity {
                guard let meta = doc.walletMetadata else { continue }
                var line = "- \(meta.kind.displayName)"
                if let holder = meta.holderName, !holder.isEmpty { line += " di \(holder)" }
                if let exp = meta.effectiveExpiryDate {
                    line += " — scade il \(fmtDate(exp))"
                    if exp < now { line += " ⚠️ SCADUTO" }
                }
                if !meta.patenteCategories.isEmpty {
                    line += " — categorie \(meta.patenteCategories.map(\.code).joined(separator: ", "))"
                }
                lines.append(line)
            }
        }
        if !s.loyaltyCards.isEmpty {
            lines.append("\n## Carte fedeltà")
            lines.append(s.loyaltyCards.map(\.brandName).sorted().joined(separator: ", "))
        }
        let summary = "\(s.walletTickets.count) biglietti, \(identity.count) documenti d'identità, \(s.loyaltyCards.count) carte fedeltà"
        return AgentMemoryFile(name: "wallet.md", title: "Wallet", summary: summary, body: lines.joined(separator: "\n"))
    }

    // MARK: casa.md

    private func homeFile(docAllowance: [String: Int]?) -> AgentMemoryFile? {
        guard !s.homeItems.isEmpty || !s.housePayments.isEmpty else { return nil }
        var lines = ["# Casa"]
        if !s.homeItems.isEmpty {
            lines.append("\n## Oggetti, impianti e contratti (\(s.homeItems.count))")
            for h in s.homeItems.sorted(by: { $0.name < $1.name }).prefix(40) {
                var line = "- \(h.name) [\(Self.homeItemCategoryLabel(h.categoryRaw))]"
                let bm = [h.brand, h.model].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
                if !bm.isEmpty { line += " — \(bm)" }
                if let pd = h.purchaseDate { line += " — acquisto \(fmtDate(pd))" }
                if let w = h.warrantyExpiryDate {
                    line += " — garanzia fino al \(fmtDate(w))"
                    if w < now { line += " (scaduta)" }
                }
                if let next = h.nextServiceDate { line += " — prossima manutenzione \(fmtDate(next))" }
                if let m = h.servicePeriodMonths { line += " — ogni \(m) mesi" }
                if let n = h.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { line += " — note: \(clip(n, 120))" }
                lines.append(line)
                lines += attachmentLines("homeItem:\(h.id)", allowance: docAllowance)
            }
        }
        if !s.housePayments.isEmpty {
            lines.append("\n## Scadenze e pagamenti (\(s.housePayments.count))")
            for p in s.housePayments.sorted(by: { $0.name < $1.name }).prefix(40) {
                var line = "- \(p.name) — \(Self.housePaymentTypeLabel(p.typeRaw))"
                if let st = p.subtypeRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !st.isEmpty { line += " (\(st))" }
                if let imp = p.importo { line += " — \(KidBoxDecimalFormat.string(from: imp)) €" }
                if let g = p.giornoDiScadenzaMensile { line += " — ogni mese il giorno \(g)" }
                if let ds = p.dataScadenza { line += " — scadenza di riferimento \(fmtDate(ds))" }
                if let dc = p.dataScadenzaContratto { line += " — contratto fino al \(fmtDate(dc))" }
                if let f = p.fornitore?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty { line += " — gestore \(f)" }
                if let next = p.earliestDisplayDeadline(from: now) { line += " — prossima scadenza \(fmtDate(next))" }
                if let n = p.note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { line += " — note: \(clip(n, 120))" }
                lines.append(line)
                lines += attachmentLines("housePayment:\(p.id)", allowance: docAllowance)
            }
        }
        return AgentMemoryFile(name: "casa.md", title: "Casa", summary: "\(s.homeItems.count) oggetti, \(s.housePayments.count) scadenze e pagamenti", body: lines.joined(separator: "\n"))
    }

    private static func homeItemCategoryLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "appliance": return "elettrodomestico"
        case "system": return "impianto"
        case "contract": return "contratto"
        case "other": return "altro"
        default: return raw
        }
    }

    private static func housePaymentTypeLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "mutuo", "affitto", "bolletta", "tassa", "altro": return raw.lowercased()
        default: return raw
        }
    }

    // MARK: veicoli.md

    private func vehiclesFile(docAllowance: [String: Int]?) -> AgentMemoryFile? {
        guard !s.vehicles.isEmpty else { return nil }
        var lines = ["# Veicoli"]
        let twoYears = Calendar.current.date(byAdding: .year, value: -2, to: now) ?? now
        for v in s.vehicles.sorted(by: { $0.name < $1.name }) {
            lines.append("\n## \(v.name)")
            var facts: [String] = []
            if let p = v.licensePlate, !p.isEmpty { facts.append("targa \(p)") }
            let bm = [v.brand, v.model].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
            if !bm.isEmpty { facts.append(bm) }
            if let y = v.year { facts.append("anno \(y)") }
            if let km = v.currentKm { facts.append("\(km) km") }
            if !facts.isEmpty { lines.append(facts.joined(separator: " · ")) }
            for (label, date) in [("Assicurazione", v.insuranceExpiryDate), ("Revisione", v.revisionExpiryDate), ("Bollo", v.taxExpiryDate), ("Tagliando", v.nextServiceDate)] {
                guard let date else { continue }
                lines.append("- \(label): \(fmtDate(date))\(date < now ? " ⚠️ PASSATA" : "")")
            }
            if let last = v.lastServiceDate { lines.append("- Ultimo tagliando: \(fmtDate(last))") }
            if let n = v.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { lines.append("Note: \(clip(n, 200))") }
            lines += attachmentLines("vehicle:\(v.id)", allowance: docAllowance)
            let events = s.vehicleEvents.filter { $0.vehicleId == v.id && $0.date >= twoYears }.sorted { $0.date > $1.date }
            if !events.isEmpty {
                lines.append("Interventi (ultimi 2 anni):")
                for ev in events.prefix(30) {
                    var line = "- \(fmtDate(ev.date)) \(ev.title) — \(KidBoxVehicleEventType.localized(ev.eventTypeRaw))"
                    if let km = ev.km { line += " — \(km) km" }
                    if let c = ev.cost { line += " — \(KidBoxDecimalFormat.string(from: c)) €" }
                    if let g = ev.garageName?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty { line += " — \(g)" }
                    if let n = ev.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { line += " — \(clip(n, 100))" }
                    lines.append(line)
                    lines += attachmentLines("vehicleEvent:\(ev.id)", allowance: docAllowance)
                }
            }
        }
        return AgentMemoryFile(name: "veicoli.md", title: "Veicoli", summary: "\(s.vehicles.count) veicoli, \(s.vehicleEvents.count) interventi", body: lines.joined(separator: "\n"))
    }

    // MARK: animali.md

    private func petsFile(docAllowance: [String: Int]?) -> AgentMemoryFile? {
        guard !s.pets.isEmpty else { return nil }
        var lines = ["# Animali"]
        for p in s.pets.sorted(by: { $0.name < $1.name }) {
            lines.append("\n## \(p.name)")
            var facts = [p.species]
            if let b = p.breed, !b.isEmpty { facts.append(b) }
            if let bd = p.birthDate { facts.append("nato/a il \(fmtDate(bd))") }
            if let c = p.color, !c.isEmpty { facts.append(c) }
            if let chip = p.chipCode, !chip.isEmpty { facts.append("microchip \(chip)") }
            lines.append(facts.joined(separator: " · "))
            if let n = p.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { lines.append("Note: \(clip(n, 200))") }
            lines += attachmentLines("pet:\(p.id)", allowance: docAllowance)
            let cures = s.treatments.filter { $0.petId == p.id && AgentMemorySnapshot.isCurrent($0, now: now) }
            if !cures.isEmpty {
                lines.append("Cure in corso: " + cures.map { "\($0.drugName) \(fmtNumber($0.dosageValue)) \($0.dosageUnit)" }.joined(separator: ", "))
            }
            let events = s.petEvents.filter { $0.petId == p.id }.sorted { $0.date > $1.date }
            if !events.isEmpty {
                lines.append("Eventi:")
                for ev in events.prefix(30) {
                    var line = "- \(fmtDate(ev.date)) \(ev.title) — \(ev.eventTypeRaw)"
                    if let next = ev.nextDueDate { line += " — prossimo \(fmtDate(next))" }
                    if let vet = ev.vetName, !vet.isEmpty { line += " — \(vet)" }
                    if let c = ev.cost { line += " — \(KidBoxDecimalFormat.string(from: c)) €" }
                    if let n = ev.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { line += " — \(clip(n, 100))" }
                    lines.append(line)
                    lines += attachmentLines("petEvent:\(ev.id)", allowance: docAllowance)
                }
            }
        }
        return AgentMemoryFile(name: "animali.md", title: "Animali", summary: "\(s.pets.count) animali, \(s.petEvents.count) eventi", body: lines.joined(separator: "\n"))
    }

    // MARK: viaggi.md

    private func tripsFile() -> AgentMemoryFile? {
        guard !s.trips.isEmpty else { return nil }
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -60, to: now) ?? now
        let relevant = s.trips.filter { $0.endDate >= recentCutoff }.sorted { $0.startDate < $1.startDate }
        let older = s.trips.filter { $0.endDate < recentCutoff }.sorted { $0.startDate > $1.startDate }
        var lines = ["# Viaggi"]
        for trip in relevant.prefix(8) {
            lines.append("\n## \(trip.name)")
            var head = "Dal \(fmtDate(trip.startDate)) al \(fmtDate(trip.endDate)) — stato: \(trip.statusRaw)"
            if trip.budgetTotal > 0 { head += " — budget \(fmtNumber(trip.budgetTotal)) \(trip.currency)" }
            lines.append(head)
            let legs = s.tripLegs.filter { $0.tripId == trip.id }.sorted { $0.order < $1.order }
            for leg in legs {
                var line = "- Tappa: \(leg.fromLocation) → \(leg.toLocation) (\(leg.transportMode.label))"
                if let dep = leg.departureAt { line += " partenza \(fmtDateTime(dep))" }
                lines.append(line)
            }
            let days = s.tripDays.filter { $0.tripId == trip.id }.sorted { $0.dateString < $1.dateString }
            for day in days.prefix(21) {
                var line = "- \(day.dateString) a \(day.location)"
                let plan = [day.morningPlan, day.afternoonPlan, day.eveningPlan].filter { !$0.isEmpty }.map { clip($0, 120) }
                if !plan.isEmpty { line += ": " + plan.joined(separator: " / ") }
                if let acc = day.accommodationName, !acc.isEmpty { line += " — alloggio \(acc)" }
                lines.append(line)
            }
        }
        if !older.isEmpty {
            lines.append("\n## Viaggi passati")
            lines += older.prefix(20).map { "- \($0.name): \(fmtDate($0.startDate)) – \(fmtDate($0.endDate))" }
        }
        return AgentMemoryFile(name: "viaggi.md", title: "Viaggi", summary: "\(relevant.count) in corso o in programma, \(older.count) passati", body: lines.joined(separator: "\n"))
    }

    // MARK: chat.md

    private func chatFile() -> AgentMemoryFile? {
        let texts = s.chat.compactMap { m -> String? in
            let body: String?
            switch m.type {
            case .text: body = m.text
            case .audio: body = m.transcriptText.map { "(vocale) \($0)" }
            default: body = nil
            }
            guard let body = body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return nil }
            return "- [\(fmtDateTime(m.createdAt))] \(m.senderName): \(clip(body, 300))"
        }
        guard !texts.isEmpty else { return nil }
        let last = Array(texts.suffix(Self.chatMaxMessages))
        let body = (["# Chat di famiglia", "Ultimi \(last.count) messaggi di testo, dal più vecchio."] + last).joined(separator: "\n")
        return AgentMemoryFile(name: "chat.md", title: "Chat di famiglia", summary: "ultimi \(last.count) messaggi", body: body)
    }

    // MARK: Formatting

    static func slug(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
        let mapped = folded.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let collapsed = mapped.split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "persona" : collapsed
    }

    private func clip(_ text: String, _ max: Int) -> String {
        text.count > max ? String(text.prefix(max)) + "…" : text
    }

    private func fmtDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(kbDeviceLocale()))
    }

    private func fmtDateTime(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(kbDeviceLocale()))
    }

    private func fmtTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(kbDeviceLocale()))
    }

    private func fmtWeekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(kbDeviceLocale()))
    }

    private func fmtNumber(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(0...decimals)).locale(kbDeviceLocale()))
    }

    private func fmtEuro(_ value: Double) -> String {
        "€ " + value.formatted(.number.precision(.fractionLength(2)).locale(kbDeviceLocale()))
    }
}

// MARK: - Prompt

@MainActor
enum AgentPrompt {

    /// Ruolo e regole dell'assistente unico. Stesso testo su Android e web.
    static func rules(familyName: String, now: Date = Date()) -> String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return """
        Sei l'assistente di KidBox della famiglia \(familyName). KidBox è l'app in cui la famiglia tiene \
        calendario, to-do, lista della spesa, note, spese, documenti, salute, wallet, casa, veicoli, \
        animali e viaggi.
        Qui sotto c'è la tua memoria: una scheda per ogni sezione dell'app, aggiornata adesso, con un indice in cima.

        COME RISPONDI
        - Usa i dati delle schede; quando aiuta, di' da dove li prendi («dal referto del 12 marzo…», «nella scheda Casa…»).
        - Se un dato non c'è, dillo chiaramente: non inventare date, importi, nomi, valori o documenti.
        - Se l'indice o una scheda dice che un testo è accorciato o non incluso e la domanda riguarda proprio quello, \
        dillo e suggerisci di ripetere la domanda con la massima accuratezza.
        - Salute: linguaggio semplice, adatto a un genitore. Puoi spiegare referti, valori, cure, vaccini e visite; \
        non fare diagnosi e non cambiare terapie: quando la questione è clinica, dopo aver risposto ricorda di sentire il medico.
        - Pianificazione: aiuta a trovare spazi liberi e a non dimenticare scadenze; quando proponi un evento o un to-do \
        indica titolo, data/ora e chi se ne occupa.
        - Le password non sono nella tua memoria: se te le chiedono, rimanda alla sezione Password dell'app.
        - Date: oggi è \(promptDay(now)), domani è \(promptDay(tomorrow)). Prima di dire «domani», «dopodomani» o un giorno \
        della settimana controlla la data scritta nelle schede: non contare a memoria.
        - Rispondi in \(MealPlanPromptBuilder.responseLanguageName()), con tono caldo e pratico, senza preamboli.
        """
    }

    /// «venerdì 2 ottobre»: le regole sono in italiano, la data anche.
    private static func promptDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date)
    }

    /// Il prompt in due blocchi, ognuno con la sua cache sul server
    /// (`systemPromptStable` + `systemPrompt`): regole e schede stabili, poi
    /// focus, schede che cambiano e azioni. Il focus va due volte, prima e dopo
    /// le schede che cambiano: il 02/10/2026 su Haiku, solo in fondo «cosa devo
    /// fare adesso?» aperto da una visita tornava una volta su due con le cose
    /// della famiglia; il 05/10/2026 in questa posizione 4 su 4, come in cima al
    /// quaderno. Prima stava in cima a tutto, e ogni cambio di focus azzerava la cache.
    static func systemPrompt(familyName: String, book: AgentMemoryBook, focus: AgentFocus?) -> AgentSystemPrompt {
        AgentSystemPrompt(
            stable: [rules(familyName: familyName), book.stableRendered].joined(separator: "\n\n"),
            volatile: [
                focus?.promptLine,
                book.volatileRendered,
                PlanningAIActionBlock.promptSection,
                focus?.promptLine,
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        )
    }
}

/// Il prompt dell'assistente nelle due parti che il server mette in cache a sé.
struct AgentSystemPrompt {
    let stable: String
    let volatile: String

    /// Caratteri come li conta il server: le due parti insieme.
    var count: Int { stable.count + volatile.count }
}

// MARK: - Fitting

/// Divide un budget di caratteri fra i testi letti dei documenti quando il
/// quaderno completo non sta in un messaggio. Ordine: allegati della visita o
/// dell'esame del focus, poi i documenti pertinenti alla domanda o alla persona
/// del focus, poi gli altri dal più recente.
enum AgentContextFitter {

    static let focusItemMaxChars = 12_000
    static let relevantMaxChars = HealthAiDocumentText.standardRefertoMaxChars
    static let otherMaxChars = 1_500
    /// Righe di contorno che un testo incluso aggiunge (titolo, nota di taglio).
    private static let perDocOverhead = 150
    private static let minUsefulChars = 300

    @MainActor
    static func allowances(
        textDocuments: [AgentTextDocument],
        question: String,
        focus: AgentFocus?,
        focusItemTags: Set<String>,
        personNames: [String: String],
        availableChars: Int
    ) -> [String: Int] {
        let terms = AgentRelevance.terms(from: question)
        let foldedQuestion = AgentRelevance.fold(question)
        let mentionedPersons = Set(personNames.compactMap { id, name in
            let folded = AgentRelevance.fold(name)
            return folded.count >= 3 && foldedQuestion.contains(folded) ? id : nil
        })

        struct Candidate {
            let item: AgentTextDocument
            let tier: Int
            let score: Int
            let cap: Int
        }
        let candidates: [Candidate] = textDocuments.map { item in
            let isFocusItem = item.doc.notes.map { focusItemTags.contains($0) } ?? false
            if isFocusItem {
                return Candidate(item: item, tier: 0, score: 0, cap: focusItemMaxChars)
            }
            var score = AgentRelevance.score(item, terms: terms)
            if let pid = item.personId {
                if mentionedPersons.contains(pid) { score += 2 }
                if pid == focus?.personId { score += 1 }
            }
            return score > 0
                ? Candidate(item: item, tier: 1, score: score, cap: relevantMaxChars)
                : Candidate(item: item, tier: 2, score: 0, cap: otherMaxChars)
        }
        let ordered = candidates.sorted {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.item.doc.updatedAt > $1.item.doc.updatedAt
        }

        var remaining = availableChars
        var out: [String: Int] = [:]
        for c in ordered {
            let room = remaining - perDocOverhead
            guard room >= minUsefulChars else {
                out[c.item.doc.id] = 0
                continue
            }
            let give = min(c.item.fullLength, c.cap, room)
            out[c.item.doc.id] = give
            remaining -= give + perDocOverhead
        }
        // Secondo giro: lo spazio che avanza va ai testi ancora accorciati, nello
        // stesso ordine, fino al testo intero. Il messaggio costa uguale.
        for c in ordered where remaining > 0 {
            let id = c.item.doc.id
            let given = out[id] ?? 0
            guard given < c.item.fullLength else { continue }
            if given == 0 {
                let room = remaining - perDocOverhead
                guard room >= minUsefulChars else { continue }
                let give = min(c.item.fullLength, room)
                out[id] = give
                remaining -= give + perDocOverhead
            } else {
                let extra = min(c.item.fullLength - given, remaining)
                out[id] = given + extra
                remaining -= extra
            }
        }
        return out
    }
}

/// Pertinenza di un documento a una domanda: parole in comune, senza accenti.
enum AgentRelevance {

    /// Parole di 4+ lettere che non dicono niente sul documento cercato.
    private static let stopwords: Set<String> = [
        "della", "delle", "degli", "dello", "dalla", "dalle", "dagli", "nella", "nelle", "negli", "nello",
        "sulla", "sulle", "sugli", "sullo", "alla", "alle", "agli", "allo", "questo", "questa", "questi",
        "queste", "quello", "quella", "quelli", "quelle", "come", "cosa", "cose", "dove", "quando", "quanto",
        "quanti", "quante", "quale", "quali", "perche", "sono", "siamo", "hanno", "abbiamo", "avete", "fare",
        "fatto", "fatta", "dire", "detto", "anche", "ancora", "sempre", "dopo", "prima", "oggi", "domani",
        "ieri", "ogni", "tutto", "tutti", "tutte", "tutta", "molto", "poco", "meno", "essere", "stato",
        "stata", "stati", "ultimo", "ultima", "ultimi", "ultime", "prossimo", "prossima", "prossimi",
        "prossime", "miei", "nostro", "nostra", "nostri", "nostre", "loro", "suoi", "dimmi", "fammi",
        "spiegami", "ricordami", "riassumi", "riassumimi", "vorrei", "posso", "puoi", "devo", "deve",
        "serve", "servono", "c'e", "documento", "documenti", "what", "when", "where", "which", "with",
        "about", "have", "does", "this", "that", "there", "their", "from", "please", "dans", "pour",
        "avec", "quel", "quelle", "sont", "cual", "como", "donde", "cuando", "para", "sobre", "tiene",
    ]

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
    }

    static func terms(from question: String) -> Set<String> {
        let words = fold(question).split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return Set(words.filter { $0.count >= 4 && !stopwords.contains($0) })
    }

    @MainActor
    static func score(_ item: AgentTextDocument, terms: Set<String>) -> Int {
        guard !terms.isEmpty else { return 0 }
        let head = fold("\(item.doc.title) \(item.doc.fileName) \(item.place)")
        let body = fold(String((item.doc.extractedText ?? "").prefix(30_000)))
        return terms.reduce(0) { acc, term in
            if head.contains(term) { return acc + 2 }
            return body.contains(term) ? acc + 1 : acc
        }
    }
}
