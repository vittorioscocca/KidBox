//
//  DocumentIntelligenceExecutor.swift
//  KidBox
//
//  Esegue le azioni proposte da DocumentIntelligenceService dopo conferma utente.
//

import Foundation
import SwiftData
import FirebaseAuth

@MainActor
final class DocumentIntelligenceExecutor {

    private let modelContext: ModelContext
    private let familyId: String
    private let uid: String
    private let documentId: String
    private let childIds: Set<String>
    private let vehicleIds: Set<String>

    init(
        modelContext: ModelContext,
        familyId: String,
        documentId: String,
        children: [DocumentIntelligenceService.ChildRef],
        vehicles: [DocumentIntelligenceService.VehicleRef]
    ) {
        self.modelContext = modelContext
        self.familyId = familyId
        self.uid = Auth.auth().currentUser?.uid ?? "local"
        self.documentId = documentId
        self.childIds = Set(children.map { $0.id })
        self.vehicleIds = Set(vehicles.map { $0.id })
    }

    /// Esegue le azioni selezionate, ritorna un riepilogo testuale (o nil).
    func execute(_ actions: [DocIntelAction]) async -> String? {
        guard !actions.isEmpty else { return nil }
        var lines: [String] = []

        for action in actions {
            switch action.type {
            case "expense_add":     if let l = addExpense(action) { lines.append(l) }
            case "event_add":       if let l = addEvent(action) { lines.append(l) }
            case "todo_add":        if let l = addTodo(action) { lines.append(l) }
            case "note_add":        if let l = addNote(action) { lines.append(l) }
            case "vehicle_event":   if let l = addVehicleEvent(action) { lines.append(l) }
            case "medical_visit":   if let l = addMedicalVisit(action) { lines.append(l) }
            case "vaccine_add":     if let l = addVaccine(action) { lines.append(l) }
            case "rename_document": if let l = renameDocument(action) { lines.append(l) }
            case "health_reminder":
                if let l = await addHealthReminder(action) { lines.append(l) }
            default:
                KBLog.ai.kbDebug("DocIntelExecutor: tipo sconosciuto \(action.type)")
            }
        }

        guard !lines.isEmpty else { return nil }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        return lines.joined(separator: "\n")
    }

    // MARK: - Destinazioni

    private func addExpense(_ a: DocIntelAction) -> String? {
        guard let title = clean(a.title), let amount = a.amount, amount > 0 else { return nil }
        let expense = KBExpense(
            familyId: familyId,
            title: title,
            amount: amount,
            date: parseDate(a.date) ?? Date(),
            notes: a.notes,
            attachedDocumentId: documentId,
            createdByUid: uid
        )
        modelContext.insert(expense)
        SyncCenter.shared.enqueueExpenseUpsert(expenseId: expense.id, familyId: familyId, modelContext: modelContext)
        return "Spesa: \"\(title)\" — \(String(format: "%.2f €", amount))."
    }

    private func addEvent(_ a: DocIntelAction) -> String? {
        guard let title = clean(a.title), let start = parseDate(a.date) else { return nil }
        let event = KBCalendarEvent(
            familyId: familyId,
            childId: resolvedChild(a.childId),
            title: title,
            notes: a.notes,
            startDate: start,
            endDate: parseDate(a.endDate) ?? start.addingTimeInterval(3600),
            isAllDay: a.isAllDay ?? false,
            createdAt: Date(),
            updatedAt: Date(),
            updatedBy: uid,
            createdBy: uid
        )
        event.syncState = .pendingUpsert
        modelContext.insert(event)
        SyncCenter.shared.enqueueCalendarUpsert(eventId: event.id, familyId: familyId, modelContext: modelContext)
        return "Evento: \"\(title)\"."
    }

    private func addTodo(_ a: DocIntelAction) -> String? {
        guard let title = clean(a.title) else { return nil }
        let todo = KBTodoItem(
            familyId: familyId,
            childId: resolvedChild(a.childId) ?? familyId,
            title: title,
            listId: nil,
            notes: a.notes,
            dueAt: parseDate(a.date),
            isDone: false,
            updatedBy: uid,
            createdAt: Date(),
            updatedAt: Date(),
            isDeleted: false
        )
        todo.createdBy = uid
        todo.priorityRaw = 0
        todo.syncState = .pendingUpsert
        modelContext.insert(todo)
        SyncCenter.shared.enqueueTodoUpsert(todoId: todo.id, familyId: familyId, modelContext: modelContext)
        return "Promemoria: \"\(title)\"."
    }

    private func addHealthReminder(_ a: DocIntelAction) async -> String? {
        guard let title = clean(a.title) else { return nil }
        let due = parseDate(a.date) ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let result = await PlanningReminderService.schedule(
            request: .freeText(
                title: title,
                dueAt: due,
                familyId: familyId,
                childId: resolvedChild(a.childId) ?? familyId,
                listId: nil
            ),
            modelContext: modelContext
        )
        if case .scheduled(let description) = result { return description }
        return nil
    }

    private func addNote(_ a: DocIntelAction) -> String? {
        guard let title = clean(a.title) ?? clean(a.body)?.components(separatedBy: "\n").first else { return nil }
        let note = KBNote(
            familyId: familyId,
            title: title,
            body: a.body ?? a.title ?? title,
            createdBy: uid,
            createdByName: "",
            updatedBy: uid,
            updatedByName: "",
            createdAt: Date(),
            updatedAt: Date(),
            isDeleted: false
        )
        note.syncState = .pendingUpsert
        modelContext.insert(note)
        SyncCenter.shared.enqueueNoteUpsert(noteId: note.id, familyId: familyId, modelContext: modelContext)
        return "Nota: \"\(title)\"."
    }

    private func addVehicleEvent(_ a: DocIntelAction) -> String? {
        // Richiede un veicolo esistente combaciante.
        guard let vehicleId = a.vehicleId, vehicleIds.contains(vehicleId),
              let title = clean(a.title) else { return nil }
        let event = KBVehicleEvent(
            familyId: familyId,
            vehicleId: vehicleId,
            title: title,
            eventTypeRaw: clean(a.vehicleEventType) ?? "altro",
            date: parseDate(a.date) ?? Date(),
            cost: a.amount,
            notes: a.notes,
            createdBy: uid,
            updatedBy: uid
        )
        modelContext.insert(event)
        SyncCenter.shared.enqueueVehicleEventUpsert(eventId: event.id, familyId: familyId, modelContext: modelContext)
        return "Scadenza veicolo: \"\(title)\"."
    }

    private func addMedicalVisit(_ a: DocIntelAction) -> String? {
        guard let childId = resolvedChild(a.childId) else { return nil }
        let visit = KBMedicalVisit(
            familyId: familyId,
            childId: childId,
            date: parseDate(a.date) ?? Date(),
            doctorName: clean(a.doctorName),
            reason: clean(a.title) ?? "Visita",
            notes: a.notes,
            updatedBy: uid,
            createdBy: uid
        )
        visit.syncState = .pendingUpsert
        modelContext.insert(visit)
        SyncCenter.shared.enqueueVisitUpsert(visitId: visit.id, familyId: familyId, modelContext: modelContext)
        return "Visita medica registrata."
    }

    private func addVaccine(_ a: DocIntelAction) -> String? {
        guard let childId = resolvedChild(a.childId) else { return nil }
        let type = VaccineType(rawValue: a.vaccineType ?? "altro") ?? .altro
        let vaccine = KBVaccine(
            familyId: familyId,
            childId: childId,
            vaccineType: type,
            status: .administered,
            commercialName: clean(a.title),
            administeredDate: parseDate(a.date) ?? Date(),
            notes: a.notes,
            updatedBy: uid,
            createdBy: uid
        )
        vaccine.syncState = .pendingUpsert
        modelContext.insert(vaccine)
        SyncCenter.shared.enqueueVaccineUpsert(vaccineId: vaccine.id, familyId: familyId, modelContext: modelContext)
        return "Vaccino: \(type.displayName)."
    }

    private func renameDocument(_ a: DocIntelAction) -> String? {
        guard let newName = clean(a.renameTo) else { return nil }
        let did = documentId
        guard let doc = try? modelContext.fetch(
            FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == did })
        ).first else { return nil }
        guard doc.title != newName else { return nil }
        doc.title = newName
        doc.updatedAt = Date()
        doc.updatedBy = uid
        doc.syncState = .pendingUpsert
        doc.lastSyncError = nil
        SyncCenter.shared.enqueueDocumentUpsert(documentId: doc.id, familyId: familyId, modelContext: modelContext)
        return "Documento rinominato: \"\(newName)\"."
    }

    // MARK: - Helpers

    private func resolvedChild(_ id: String?) -> String? {
        guard let id, childIds.contains(id) else { return nil }
        return id
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = f.date(from: raw) { return d }
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: raw)
    }
}
