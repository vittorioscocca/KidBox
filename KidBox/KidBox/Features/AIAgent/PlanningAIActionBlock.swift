//
//  PlanningAIActionBlock.swift
//  KidBox
//
//  Structured actions embedded in assistant replies and executed locally.
//

import Foundation
import SwiftData
import FirebaseAuth

enum PlanningAIActionMarkers {
    static let start = "<<<KIDBOX_ACTIONS>>>"
    static let end = "<<<END_KIDBOX_ACTIONS>>>"
}

struct PlanningAIProcessedReply {
    let displayText: String
    let actions: [PlanningExecutableAction]
}

struct PlanningExecutableAction: Decodable {
    let type: String
    let items: [String]?
    let title: String?
    let body: String?
    let notes: String?
    let category: String?
    let dueAt: String?
    let startAt: String?
    let endAt: String?
    let isAllDay: Bool?
    let childId: String?
    let listId: String?
    /// `request_add`: nomi dei familiari a cui chiedere (vuoto = tutti).
    let askMembers: [String]?
    /// `request_add`: chiedere anche fuori dall'app, con un link.
    let askOutside: Bool?
    let outsideLabel: String?
    let includeInvite: Bool?

    init(
        type: String,
        items: [String]? = nil,
        title: String? = nil,
        body: String? = nil,
        notes: String? = nil,
        category: String? = nil,
        dueAt: String? = nil,
        startAt: String? = nil,
        endAt: String? = nil,
        isAllDay: Bool? = nil,
        childId: String? = nil,
        listId: String? = nil,
        askMembers: [String]? = nil,
        askOutside: Bool? = nil,
        outsideLabel: String? = nil,
        includeInvite: Bool? = nil
    ) {
        self.type = type
        self.items = items
        self.title = title
        self.body = body
        self.notes = notes
        self.category = category
        self.dueAt = dueAt
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.childId = childId
        self.listId = listId
        self.askMembers = askMembers
        self.askOutside = askOutside
        self.outsideLabel = outsideLabel
        self.includeInvite = includeInvite
    }
}

enum PlanningAIActionBlock {
    static func process(_ text: String) -> PlanningAIProcessedReply {
        guard let startRange = text.range(of: PlanningAIActionMarkers.start),
              let endRange = text.range(of: PlanningAIActionMarkers.end, range: startRange.upperBound..<text.endIndex)
        else {
            return PlanningAIProcessedReply(displayText: text, actions: [])
        }

        let jsonSlice = text[startRange.upperBound..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        var display = text
        display.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        display = display.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonSlice.data(using: .utf8),
              let actions = try? JSONDecoder().decode([PlanningExecutableAction].self, from: data)
        else {
            KBLog.ai.kbError("PlanningAIActionBlock: invalid JSON block")
            return PlanningAIProcessedReply(displayText: display, actions: [])
        }

        return PlanningAIProcessedReply(displayText: display, actions: actions)
    }

    /// Fuso e prossimi giorni, davanti alle azioni. Senza, il modello scriveva
    /// l'ora italiana con la «Z» (un evento delle 16:30 finiva alle 18:30) e
    /// sbagliava il giorno della settimana. Stesso testo su Android e web.
    static func dateHeader(now: Date = Date()) -> String {
        let tz = TimeZone.current
        let seconds = tz.secondsFromGMT(for: now)
        let offset = String(format: "%@%02d:%02d", seconds >= 0 ? "+" : "-", abs(seconds) / 3600, (abs(seconds) % 3600) / 60)
        let it = Locale(identifier: "it_IT")
        let todayFmt = DateFormatter()
        todayFmt.locale = it
        todayFmt.dateFormat = "EEEE d MMMM yyyy"
        let dayFmt = DateFormatter()
        dayFmt.locale = it
        dayFmt.dateFormat = "EEEE d/M"
        let next = (1...7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: now) }.map(dayFmt.string(from:))
        return """
        DATE E ORE: l'utente è nel fuso \(tz.identifier) (ora UTC\(offset)). Scrivi ogni data con questo offset, \
        es. "2026-10-03T16:30:00\(offset)" per le 16:30 locali: MAI la Z.
        Oggi è \(todayFmt.string(from: now)). Prossimi giorni: \(next.joined(separator: ", ")).
        """
    }

    static var promptSection: String {
        """
        \(dateHeader())

        AZIONI ESEGUIBILI (obbligatorio quando modifichi dati nell'app):
        Se confermi di aver aggiunto o modificato lista spesa, to-do, nota, calendario o promemoria salute, \
        includi SEMPRE alla fine del messaggio (l'app lo nasconde all'utente) un blocco JSON:

        \(PlanningAIActionMarkers.start)
        [{"type":"grocery_add","items":["latte","pane"]}]
        \(PlanningAIActionMarkers.end)

        Tipi supportati (date in ISO8601 con l'offset del fuso, vedi DATE E ORE):
        - grocery_add: {"type":"grocery_add","items":["..."],"category":"..."}
        - todo_add: {"type":"todo_add","title":"...","notes":"...","dueAt":"2026-05-17T09:00:00Z","childId":"...","listId":"..."}
        - event_add: {"type":"event_add","title":"...","startAt":"...","endAt":"...","isAllDay":false,"notes":"..."}
        - note_add: {"type":"note_add","title":"...","body":"..."}
        - health_reminder: {"type":"health_reminder","title":"...","dueAt":"..."}
        - request_add: {"type":"request_add","title":"...","dueAt":"...","notes":"...","askMembers":["Luca"],"askOutside":false,"outsideLabel":"Nonna"}

        RICHIESTE (request_add, non todo_add): quando l'utente cerca QUALCUNO che faccia una cosa \
        («serve qualcuno per…», «chiedi a Luca se può…», «chi può prendere Marco?»). I familiari ricevono una notifica \
        con «Ci penso io» / «Non posso» e il primo che accetta si prende il to-do. \
        askMembers: i nomi dei familiari che l'utente ha indicato, come li ha scritti; omettilo per chiedere a tutti. \
        askOutside true SOLO se l'utente nomina qualcuno che non è in famiglia (nonni, babysitter…), con outsideLabel = come lo chiama: \
        l'app prepara un link da mandargli. dueAt con l'ora esatta: se l'utente dice solo «mattina», «pomeriggio» o «sera», \
        chiedi l'ora e NON includere il blocco finché non la sai. A chi è fuori dall'app NON arriva nessuna notifica: \
        di' che l'app prepara un link da mandargli. Non dire chi è libero o occupato: l'app non lo sa.

        NON dire "ho aggiunto" o "fatto" senza il blocco quando l'utente chiede un'aggiunta concreta.

        Questo vale in ogni chat KidBox (pianificazione, salute, visite, esami): \
        lista spesa, to-do, note, calendario e promemoria salute.
        """
    }
}

@MainActor
final class PlanningActionExecutor {
    private let modelContext: ModelContext
    private let familyId: String
    private let uid: String
    private let children: [KBChild]
    /// Nomi già in lista. È `var` e non `let` perché cresce mentre si aggiunge:
    /// vedi `addGroceryItems`.
    private var pendingGroceryNames: Set<String>

    init(
        modelContext: ModelContext,
        familyId: String,
        uid: String,
        children: [KBChild],
        pendingGroceryNames: [String]
    ) {
        self.modelContext = modelContext
        self.familyId = familyId
        self.uid = uid
        self.children = children
        self.pendingGroceryNames = Set(pendingGroceryNames.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
    }

    func execute(_ actions: [PlanningExecutableAction]) async -> String? {
        guard !actions.isEmpty else { return nil }
        var lines: [String] = []

        for action in actions {
            switch action.type {
            case "grocery_add":
                if let count = addGroceryItems(action.items ?? [], category: action.category) {
                    lines.append("Lista spesa: \(count) articol\(count == 1 ? "o" : "i") aggiunt\(count == 1 ? "o" : "i").")
                }
            case "todo_add":
                if let title = normalized(action.title) {
                    if addTodo(title: title, notes: action.notes, dueAt: parseDate(action.dueAt), childId: action.childId, listId: action.listId) {
                        lines.append("To-do aggiunto: \"\(title)\".")
                    }
                }
            case "event_add":
                if let title = normalized(action.title), let start = parseDate(action.startAt) ?? parseDate(action.dueAt) {
                    if addEvent(title: title, start: start, end: parseDate(action.endAt), isAllDay: action.isAllDay ?? false, notes: action.notes, childId: action.childId) {
                        lines.append("Evento aggiunto: \"\(title)\".")
                    }
                }
            case "note_add":
                if let title = normalized(action.title) ?? normalized(action.body)?.components(separatedBy: "\n").first {
                    if addNote(title: title, body: action.body ?? action.title ?? title) {
                        lines.append("Nota creata: \"\(title)\".")
                    }
                }
            case "request_add":
                if let line = await addRequest(action) {
                    lines.append(line)
                }
            case "health_reminder":
                if let title = normalized(action.title) {
                    let due = parseDate(action.dueAt) ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    let target = defaultTodoTarget(childId: action.childId, listId: action.listId)
                    let result = await PlanningReminderService.schedule(
                        request: .freeText(
                            title: title,
                            dueAt: due,
                            familyId: familyId,
                            childId: target.childId,
                            listId: target.listId
                        ),
                        modelContext: modelContext
                    )
                    if case .scheduled(let description) = result {
                        lines.append(description)
                    }
                }
            default:
                KBLog.ai.kbDebug("PlanningActionExecutor: unknown type \(action.type)")
            }
        }

        if lines.isEmpty { return nil }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        return lines.joined(separator: "\n")
    }

    // MARK: - Grocery

    private func addGroceryItems(_ items: [String], category: String?) -> Int? {
        let names = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }

        let now = Date()
        var added = 0
        for name in names {
            let key = name.lowercased()
            guard !pendingGroceryNames.contains(key) else { continue }
            // Il nome entra subito fra quelli visti: senza, un elenco che
            // ripete lo stesso articolo («latte, pane, latte») lo scriveva due
            // volte, perché il confronto guardava solo la lista di partenza.
            // Vale anche fra più blocchi `grocery_add` nella stessa risposta.
            pendingGroceryNames.insert(key)
            let item = KBGroceryItem(
                familyId: familyId,
                name: name,
                category: category,
                createdAt: now,
                updatedAt: now,
                updatedBy: uid,
                createdBy: uid
            )
            item.syncState = .pendingUpsert
            modelContext.insert(item)
            SyncCenter.shared.enqueueGroceryUpsert(itemId: item.id, familyId: familyId, modelContext: modelContext)
            added += 1
        }
        return added > 0 ? added : nil
    }

    // MARK: - Richiesta di famiglia

    /// Crea una richiesta («Chi prende Marco giovedì?») con lo stesso servizio
    /// del foglio «Chiedi a…». I nomi detti dall'utente diventano account della
    /// famiglia; un nome che non si trova si dice nel riepilogo, e senza
    /// nessuno a cui chiedere la richiesta non parte.
    private func addRequest(_ action: PlanningExecutableAction) async -> String? {
        guard let title = normalized(action.title) else { return nil }
        let fid = familyId
        let me = uid
        let members = ((try? modelContext.fetch(FetchDescriptor<KBFamilyMember>(
            predicate: #Predicate { $0.familyId == fid && !$0.isDeleted }
        ))) ?? []).filter { $0.userId != me }

        let wanted = (action.askMembers ?? []).compactMap(normalized)
        var recipients: [KBFamilyMember] = []
        var unknown: [String] = []
        if wanted.isEmpty {
            recipients = members
        } else {
            for name in wanted {
                let key = name.lowercased()
                let match = members.first { m in
                    let full = (m.displayName ?? "").lowercased()
                    return full == key || full.split(separator: " ").first.map(String.init) == key
                }
                if let match { recipients.append(match) } else { unknown.append(name) }
            }
        }
        let askOutside = action.askOutside == true
        guard !recipients.isEmpty || askOutside else {
            return String(localized: "Richiesta non inviata: non trovo in famiglia \(unknown.joined(separator: ", ")).")
        }

        // Una lista vera: il to-do nascerà lì alla prima risposta «Ci penso io».
        // Se la famiglia non ne ha nessuna, il server ne crea una al momento.
        let target = defaultTodoTarget(childId: action.childId, listId: action.listId)
        let anyList = (try? modelContext.fetch(FetchDescriptor<KBTodoList>(
            predicate: #Predicate { $0.familyId == fid && !$0.isDeleted }
        )))?.first?.id
        let listId = target.listId ?? anyList ?? UUID().uuidString

        var draft = FamilyRequestService.Draft()
        draft.recipients = recipients.map(\.userId)
        draft.askOutside = askOutside
        draft.outsideLabel = normalized(action.outsideLabel) ?? ""
        draft.includeInvite = action.includeInvite ?? true

        let familyName = (try? modelContext.fetch(FetchDescriptor<KBFamily>(
            predicate: #Predicate { $0.id == fid }
        )))?.first?.name ?? ""
        let profileName = ((try? modelContext.fetch(FetchDescriptor<KBUserProfile>(
            predicate: #Predicate { $0.uid == me }
        )))?.first?.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let inviterName = (!profileName.isEmpty && profileName != "Utente")
            ? profileName
            : (Auth.auth().currentUser?.displayName ?? "")

        do {
            let created = try await FamilyRequestService.create(
                familyId: familyId,
                childId: target.childId,
                listId: listId,
                title: title,
                notes: normalized(action.notes),
                isUrgent: false,
                dueAt: parseDate(action.dueAt),
                dueHasTime: true,
                draft: draft,
                familyName: familyName,
                inviterName: inviterName
            )
            var who = recipients.map { ($0.displayName ?? "").split(separator: " ").first.map(String.init) ?? "" }
                .filter { !$0.isEmpty }
            if askOutside { who.append(draft.outsideLabel.isEmpty ? String(localized: "qualcuno fuori dall'app") : draft.outsideLabel) }
            var parts = [String(localized: "Richiesta inviata a \(who.joined(separator: ", ")): «\(title)».")]
            if !unknown.isEmpty {
                parts.append(String(localized: "Non trovo in famiglia: \(unknown.joined(separator: ", "))."))
            }
            if let link = created.shareLink {
                parts.append(String(localized: "Link da mandare a chi non ha l'app: \(link)"))
            }
            return parts.joined(separator: "\n")
        } catch {
            return String(localized: "Richiesta non inviata: \(error.localizedDescription)")
        }
    }

    // MARK: - Todo

    private func addTodo(title: String, notes: String?, dueAt: Date?, childId: String?, listId: String?) -> Bool {
        let target = defaultTodoTarget(childId: childId, listId: listId)
        let now = Date()
        let todo = KBTodoItem(
            familyId: familyId,
            childId: target.childId,
            title: title,
            listId: target.listId,
            notes: notes,
            dueAt: dueAt,
            isDone: false,
            updatedBy: uid,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        todo.createdBy = uid
        todo.priorityRaw = 0
        todo.syncState = .pendingUpsert
        modelContext.insert(todo)
        SyncCenter.shared.enqueueTodoUpsert(todoId: todo.id, familyId: familyId, modelContext: modelContext)
        return true
    }

    // MARK: - Event

    private func addEvent(title: String, start: Date, end: Date?, isAllDay: Bool, notes: String?, childId: String?) -> Bool {
        let now = Date()
        let endDate = end ?? start.addingTimeInterval(3600)
        let event = KBCalendarEvent(
            familyId: familyId,
            childId: childId ?? children.first?.id,
            title: title,
            notes: notes,
            startDate: start,
            endDate: endDate,
            isAllDay: isAllDay,
            createdAt: now,
            updatedAt: now,
            updatedBy: uid,
            createdBy: uid
        )
        event.syncState = .pendingUpsert
        modelContext.insert(event)
        SyncCenter.shared.enqueueCalendarUpsert(eventId: event.id, familyId: familyId, modelContext: modelContext)
        return true
    }

    // MARK: - Note

    private func addNote(title: String, body: String) -> Bool {
        let now = Date()
        let note = KBNote(
            familyId: familyId,
            title: title,
            body: body,
            createdBy: uid,
            createdByName: "",
            updatedBy: uid,
            updatedByName: "",
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        note.syncState = .pendingUpsert
        modelContext.insert(note)
        SyncCenter.shared.enqueueNoteUpsert(noteId: note.id, familyId: familyId, modelContext: modelContext)
        return true
    }

    // MARK: - Helpers

    private struct TodoTarget {
        let childId: String
        let listId: String?
    }

    private func defaultTodoTarget(childId: String?, listId: String?) -> TodoTarget {
        let resolvedChild = childId ?? children.first?.id ?? familyId
        if let listId, !listId.isEmpty {
            return TodoTarget(childId: resolvedChild, listId: listId)
        }
        let fid = familyId
        let cid = resolvedChild
        let descriptor = FetchDescriptor<KBTodoList>(
            predicate: #Predicate { $0.familyId == fid && $0.childId == cid && !$0.isDeleted }
        )
        let lists = (try? modelContext.fetch(descriptor)) ?? []
        return TodoTarget(childId: resolvedChild, listId: lists.first?.id)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return fallback.date(from: raw)
    }
}
