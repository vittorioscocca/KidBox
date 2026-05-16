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
        listId: String? = nil
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

    static var promptSection: String {
        """
        AZIONI ESEGUIBILI (obbligatorio quando modifichi dati nell'app):
        Se confermi di aver aggiunto o modificato lista spesa, to-do, nota, calendario o promemoria salute, \
        includi SEMPRE alla fine del messaggio (l'app lo nasconde all'utente) un blocco JSON:

        \(PlanningAIActionMarkers.start)
        [{"type":"grocery_add","items":["latte","pane"]}]
        \(PlanningAIActionMarkers.end)

        Tipi supportati (date in ISO8601 UTC):
        - grocery_add: {"type":"grocery_add","items":["..."],"category":"..."}
        - todo_add: {"type":"todo_add","title":"...","notes":"...","dueAt":"2026-05-17T09:00:00Z","childId":"...","listId":"..."}
        - event_add: {"type":"event_add","title":"...","startAt":"...","endAt":"...","isAllDay":false,"notes":"..."}
        - note_add: {"type":"note_add","title":"...","body":"..."}
        - health_reminder: {"type":"health_reminder","title":"...","dueAt":"..."}

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
    private let pendingGroceryNames: Set<String>

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
