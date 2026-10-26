//
//  DocumentIntelligenceExecutor.swift
//  KidBox
//
//  Esegue le azioni proposte da DocumentIntelligenceService dopo conferma utente.
//
//  Due ingressi:
//  - import in Documenti: il file è già un `KBDocument` (`documentId`) e resta lì;
//  - «+» dell'assistente: c'è solo il file (`sourceFile`). Si allega alla prima
//    scheda creata che accetta allegati (pagamento di Casa, visita, esame, cura);
//    se non ce n'è nessuna finisce in Documenti, così il file non va mai perso.
//

import Foundation
import SwiftData
import FirebaseAuth

@MainActor
final class DocumentIntelligenceExecutor {

    private let modelContext: ModelContext
    private let familyId: String
    private let uid: String
    /// Il documento a cui puntano spese e rinomina: quello importato, oppure
    /// l'allegato creato dal file sorgente.
    private var documentId: String?
    private let sourceFile: URL?
    /// Figli: per i vaccini (calendario vaccinale pediatrico).
    private let childIds: Set<String>
    /// Figli e adulti: visite, esami e cure.
    private let personIds: Set<String>
    private let vehicleIds: Set<String>
    /// Prima scheda creata che accetta l'allegato (tipo azione, id, persona).
    private var attachTarget: (type: String, id: String, personId: String)?

    init(
        modelContext: ModelContext,
        familyId: String,
        documentId: String?,
        sourceFile: URL? = nil,
        children: [DocumentIntelligenceService.ChildRef],
        vehicles: [DocumentIntelligenceService.VehicleRef]
    ) {
        self.modelContext = modelContext
        self.familyId = familyId
        self.uid = KBUid.current ?? "local"
        self.documentId = documentId
        self.sourceFile = sourceFile
        self.childIds = Set(children.filter { !$0.isAdult }.map { $0.id })
        self.personIds = Set(children.map { $0.id })
        self.vehicleIds = Set(vehicles.map { $0.id })
    }

    /// Ordine di esecuzione: prima le schede che prendono l'allegato (la più
    /// importante per prima), poi il resto, che può puntare all'allegato.
    private static let priority = [
        "house_payment", "medical_visit", "exam_add", "treatment_add", "vaccine_add",
    ]

    /// Esegue le azioni selezionate, ritorna un riepilogo testuale (o nil).
    func execute(_ actions: [DocIntelAction]) async -> String? {
        guard !actions.isEmpty else { return nil }
        var lines: [String] = []

        let primary = actions
            .filter { Self.priority.contains($0.type) }
            .sorted { Self.priority.firstIndex(of: $0.type)! < Self.priority.firstIndex(of: $1.type)! }
        let rest = actions.filter { !Self.priority.contains($0.type) }

        for action in primary {
            switch action.type {
            case "house_payment":   if let l = addHousePayment(action) { lines.append(l) }
            case "medical_visit":   if let l = addMedicalVisit(action) { lines.append(l) }
            case "exam_add":        if let l = addExam(action) { lines.append(l) }
            case "treatment_add":   if let l = addTreatment(action) { lines.append(l) }
            case "vaccine_add":     if let l = addVaccine(action) { lines.append(l) }
            default: break
            }
        }

        if sourceFile != nil {
            try? modelContext.save()
            if let l = await attachSourceFile() { lines.append(l) }
        }

        for action in rest {
            switch action.type {
            case "expense_add":     if let l = addExpense(action) { lines.append(l) }
            case "event_add":       if let l = addEvent(action) { lines.append(l) }
            case "todo_add":        if let l = addTodo(action) { lines.append(l) }
            case "note_add":        if let l = addNote(action) { lines.append(l) }
            case "vehicle_event":   if let l = addVehicleEvent(action) { lines.append(l) }
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
        guard let personId = resolvedPerson(a.childId) else { return nil }
        let date = parseDate(a.date) ?? Date()
        let visit = KBMedicalVisit(
            familyId: familyId,
            childId: personId,
            date: date,
            doctorName: clean(a.doctorName),
            reason: clean(a.title) ?? String(localized: "Visita"),
            diagnosis: clean(a.diagnosis),
            recommendations: clean(a.recommendations),
            notes: clean(a.notes),
            visitStatus: date <= Date() ? .completed : .booked,
            updatedBy: uid,
            createdBy: uid
        )
        visit.syncState = .pendingUpsert
        modelContext.insert(visit)
        SyncCenter.shared.enqueueVisitUpsert(visitId: visit.id, familyId: familyId, modelContext: modelContext)
        setAttachTarget("medical_visit", visit.id, personId)
        if let doctor = clean(a.doctorName) {
            return String(format: String(localized: "Visita registrata (%@)."), doctor)
        }
        return String(localized: "Visita registrata.")
    }

    private func addExam(_ a: DocIntelAction) -> String? {
        guard let personId = resolvedPerson(a.childId), let name = clean(a.title) else { return nil }
        let date = parseDate(a.date)
        let result = clean(a.resultText)
        let exam = KBMedicalExam(
            familyId: familyId,
            childId: personId,
            name: name,
            deadline: result == nil ? date : nil,
            notes: clean(a.notes),
            location: clean(a.location),
            status: result == nil ? .pending : .resultIn,
            resultText: result,
            resultDate: result == nil ? nil : (date ?? Date()),
            updatedBy: uid,
            createdBy: uid
        )
        modelContext.insert(exam)
        SyncCenter.shared.enqueueMedicalExamUpsert(examId: exam.id, familyId: familyId, modelContext: modelContext)
        setAttachTarget("exam_add", exam.id, personId)
        return String(format: String(localized: "Esame: \"%@\"."), name)
    }

    private func addTreatment(_ a: DocIntelAction) -> String? {
        guard let personId = resolvedPerson(a.childId), let drug = clean(a.title) else { return nil }
        let start = Calendar.current.startOfDay(for: parseDate(a.date) ?? Date())
        let isLongTerm = a.isLongTerm ?? false
        let days = max(1, a.durationDays ?? 7)
        let frequency = min(max(1, a.dailyFrequency ?? 1), 6)
        let treatment = KBTreatment(
            familyId: familyId,
            childId: personId,
            drugName: drug,
            activeIngredient: clean(a.activeIngredient),
            dosageValue: a.dosageValue ?? 0,
            dosageUnit: clean(a.dosageUnit) ?? "ml",
            isLongTerm: isLongTerm,
            durationDays: days,
            startDate: start,
            endDate: isLongTerm ? nil : Calendar.current.date(byAdding: .day, value: days - 1, to: start),
            dailyFrequency: frequency,
            scheduleTimes: Self.defaultTimes(frequency),
            isActive: true,
            notes: clean(a.notes),
            reminderEnabled: false,
            updatedBy: uid,
            createdBy: uid
        )
        modelContext.insert(treatment)
        SyncCenter.shared.enqueueTreatmentUpsert(treatmentId: treatment.id, familyId: familyId, modelContext: modelContext)
        setAttachTarget("treatment_add", treatment.id, personId)
        return String(format: String(localized: "Cura: \"%@\"."), drug)
    }

    /// Stessi orari proposti dal modulo della cura per 1…6 somministrazioni.
    private static func defaultTimes(_ frequency: Int) -> [String] {
        switch frequency {
        case 1: return ["08:00"]
        case 2: return ["08:00", "20:00"]
        case 3: return ["08:00", "14:00", "20:00"]
        case 4: return ["08:00", "12:00", "16:00", "20:00"]
        case 5: return ["07:00", "10:00", "13:00", "16:00", "19:00"]
        default: return ["06:00", "09:00", "12:00", "15:00", "18:00", "21:00"]
        }
    }

    private func addHousePayment(_ a: DocIntelAction) -> String? {
        guard let name = clean(a.title) else { return nil }
        let type = KidBoxHousePaymentType(rawValue: clean(a.paymentType)?.lowercased() ?? "") ?? .bolletta
        let payment = KBHousePayment(
            familyId: familyId,
            name: name,
            typeRaw: type.rawValue,
            subtypeRaw: clean(a.subtype),
            importo: (a.amount ?? 0) > 0 ? a.amount : nil,
            dataScadenza: parseDate(a.date),
            fornitore: clean(a.provider),
            note: clean(a.notes),
            reminderOn: true,
            createdBy: uid,
            updatedBy: uid
        )
        modelContext.insert(payment)
        try? modelContext.save()
        SyncCenter.shared.enqueueHousePaymentUpsert(paymentId: payment.id, familyId: familyId, modelContext: modelContext)
        // La spesa nasce dal pagamento, come dal modulo di Casa: niente doppioni.
        HousePaymentExpenseLink.sync(payment: payment, familyId: familyId, modelContext: modelContext)
        Task { await HousePaymentReminderService.shared.scheduleNext(for: payment) }
        setAttachTarget("house_payment", payment.id, "")
        if let amount = payment.importo {
            return String(format: String(localized: "Casa: \"%@\" — %@."), name, String(format: "%.2f €", amount))
        }
        return String(format: String(localized: "Casa: \"%@\"."), name)
    }

    // MARK: - Allegato

    private func setAttachTarget(_ type: String, _ id: String, _ personId: String) {
        guard attachTarget == nil else { return }
        attachTarget = (type, id, personId)
    }

    /// Carica il file sorgente come allegato della scheda principale, o in
    /// Documenti se nessuna scheda lo prende. Aggiorna `documentId`.
    private func attachSourceFile() async -> String? {
        guard let url = sourceFile else { return nil }
        var doc: KBDocument?
        switch attachTarget?.type {
        case "house_payment":
            doc = await HomeAttachmentService.shared.uploadHousePayment(
                url: url, paymentId: attachTarget!.id, familyId: familyId, modelContext: modelContext)
        case "medical_visit":
            doc = await VisitAttachmentService.shared.upload(
                url: url, visitId: attachTarget!.id, familyId: familyId,
                childId: attachTarget!.personId, modelContext: modelContext)
        case "exam_add":
            doc = await ExamAttachmentService.shared.upload(
                url: url, examId: attachTarget!.id, familyId: familyId,
                childId: attachTarget!.personId, modelContext: modelContext)
        case "treatment_add":
            doc = await TreatmentAttachmentService.shared.upload(
                url: url, treatmentId: attachTarget!.id, familyId: familyId,
                childId: attachTarget!.personId, modelContext: modelContext)
        default:
            break
        }
        if let doc {
            documentId = doc.id
            return String(localized: "File allegato.")
        }
        // Nessuna scheda lo prende (o l'allegato non è riuscito): in Documenti.
        let folderVM = DocumentFolderViewModel(familyId: familyId, folderId: nil)
        folderVM.bind(modelContext: modelContext)
        let before = Set(((try? modelContext.fetch(FetchDescriptor<KBDocument>())) ?? []).map(\.id))
        _ = await folderVM.uploadSingleFileFromURL(url)
        let fid = familyId
        let created = ((try? modelContext.fetch(
            FetchDescriptor<KBDocument>(predicate: #Predicate { $0.familyId == fid && !$0.isDeleted })
        )) ?? []).first { !before.contains($0.id) }
        guard let created else { return nil }
        documentId = created.id
        return String(localized: "File salvato in Documenti.")
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
        guard let newName = clean(a.renameTo), let did = documentId else { return nil }
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

    /// Figlio o adulto: le schede di Salute valgono per tutti.
    private func resolvedPerson(_ id: String?) -> String? {
        guard let id, personIds.contains(id) else { return nil }
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
