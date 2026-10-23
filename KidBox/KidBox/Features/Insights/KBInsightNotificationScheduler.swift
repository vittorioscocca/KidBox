//
//  KBInsightNotificationScheduler.swift
//  KidBox
//
//  Consegna degli insight come notifiche locali. A ogni giro allinea la coda
//  alle righe `KBInsight` della famiglia: programma quelle aperte, toglie
//  quelle che non servono più (anche dal Centro notifiche, se già mostrate).
//
//  Quando consegnare:
//  - all'orario ideale del motore, o fra pochi secondi se è già passato;
//  - fuori dagli orari di silenzio dell'utente (di default 21:30–8:00), tranne
//    le dosi, che sono promemoria sanitari come quelli delle cure;
//  - con il riepilogo serale, i to-do in una sola notifica alle 19:00;
//  - una volta sola per orario: `notifiedAt` ricorda la consegna decisa, e un
//    avviso già mostrato non si ripete finché il motore non sposta `fireAt`.
//
//  Il testo non contiene dettagli sanitari: la dose dice di chi è, non quale
//  farmaco. Tutto passa da `KBLocalNotificationBudget`.
//

import Foundation
import SwiftData
import UserNotifications

@MainActor
enum KBInsightNotificationScheduler {

    static let identifierPrefix = "kb-insight-"
    /// `userInfo["type"]` = `insight_<KBInsightType.rawValue>`.
    static let typePrefix = "insight_"
    /// Classe del budget, scritta in `userInfo` perché il tipo da solo non la dice.
    static let budgetClassField = "kb.insight.class"

    /// Margine minimo prima di una consegna «subito».
    private static let soonDelay: TimeInterval = 5

    static func identifier(for insightId: String) -> String { identifierPrefix + insightId }
    static func digestIdentifier(familyId: String) -> String { identifierPrefix + "digest-" + familyId }

    /// Nel riepilogo serale vanno i to-do; le dosi restano puntuali.
    static func goesInDigest(_ type: KBInsightType) -> Bool { type != .treatmentDoseMissing }

    // MARK: - Allineamento

    /// - Parameter resetFuture: le preferenze sono cambiate, quindi le consegne
    ///   già decise ma non ancora avvenute si ricalcolano con le regole nuove.
    static func sync(
        familyId: String,
        prefs: KBInsightPreferences,
        resetFuture: Bool = false,
        now: Date = Date(),
        context: ModelContext
    ) async throws {
        let fid = familyId
        let rows = try context.fetch(FetchDescriptor<KBInsight>(predicate: #Predicate { $0.familyId == fid }))
        let center = UNUserNotificationCenter.current()
        let pendingIds = Set(
            await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(identifierPrefix) }
        )

        if resetFuture {
            for row in rows where row.state.isOpen {
                if let notified = row.notifiedAt, notified > now { row.notifiedAt = nil }
            }
        }

        let digestAt = prefs.delivery == .eveningDigest ? nextDigest(after: now, prefs: prefs) : nil
        var digestRows: [KBInsight] = []
        var wanted: [KBLocalNotificationPriority: [UNNotificationRequest]] = [:]
        var wantedIds = Set<String>()
        var finishedIds: [String] = []

        for row in rows {
            let id = identifier(for: row.id)
            guard row.state.isOpen, let type = row.type else {
                finishedIds.append(id)
                continue
            }

            if let digestAt, goesInDigest(type) {
                let undelivered = row.notifiedAt.map { $0 < row.fireAt || $0 > now } ?? true
                if undelivered, row.fireAt <= digestAt {
                    digestRows.append(row)
                }
                continue
            }

            let deliverAt: Date
            if let notified = row.notifiedAt, notified >= row.fireAt {
                // Consegna già decisa per questo orario: mostrata o ancora in coda.
                guard notified > now else { continue }
                deliverAt = notified
                wantedIds.insert(id)
                if pendingIds.contains(id) { continue }
            } else {
                deliverAt = deliveryDate(for: row.fireAt, type: type, now: now, prefs: prefs)
                wantedIds.insert(id)
            }

            guard let content = content(for: row, type: type, context: context) else {
                wantedIds.remove(id)
                continue
            }
            let budgetClass: KBLocalNotificationPriority = row.priority == .high ? .deadline : .background
            wanted[budgetClass, default: []].append(request(id: id, content: content, at: deliverAt, budgetClass: budgetClass))
            row.notifiedAt = deliverAt
        }

        if let digestAt, !digestRows.isEmpty {
            let id = digestIdentifier(familyId: familyId)
            wantedIds.insert(id)
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.userInfo = ["type": typePrefix + "digest", "familyId": familyId]
            KBNotificationLocalization.setText(
                on: content,
                titleKey: "Riepilogo della sera",
                bodyKey: "To-do che nessuno ha preso: %@",
                bodyArgs: [.text(String(digestRows.count))]
            )
            wanted[.background, default: []].append(request(id: id, content: content, at: digestAt, budgetClass: .background))
            for row in digestRows { row.notifiedAt = digestAt }
        }

        let stale = pendingIds.subtracting(wantedIds)
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }
        if !finishedIds.isEmpty {
            // Risolto o scartato: anche il banner già mostrato non serve più.
            center.removeDeliveredNotifications(withIdentifiers: finishedIds)
        }
        for (budgetClass, requests) in wanted {
            await KBLocalNotificationBudget.shared.add(requests, priority: budgetClass)
        }
        if context.hasChanges { try context.save() }

        let added = wanted.values.reduce(0) { $0 + $1.count }
        if added > 0 || !stale.isEmpty {
            KBLog.ai.kbInfo("InsightScheduler: added=\(added) removed=\(stale.count) digest=\(digestRows.count)")
        }
    }

    private static func request(
        id: String,
        content: UNMutableNotificationContent,
        at date: Date,
        budgetClass: KBLocalNotificationPriority
    ) -> UNNotificationRequest {
        var info = content.userInfo
        info[budgetClassField] = budgetClass.rawValue
        content.userInfo = info
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
    }

    /// Toglie tutto: insight spenti, piano Free, logout.
    static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    // MARK: - Orario

    static func deliveryDate(
        for fireAt: Date,
        type: KBInsightType,
        now: Date,
        prefs: KBInsightPreferences = KBInsightPreferences(),
        calendar: Calendar = .current
    ) -> Date {
        let earliest = max(fireAt, now.addingTimeInterval(soonDelay))
        guard type != .treatmentDoseMissing else { return earliest }
        return outsideQuietHours(earliest, prefs: prefs, calendar: calendar)
    }

    /// Se `date` cade negli orari di silenzio, la prima fine del silenzio dopo di lei.
    static func outsideQuietHours(
        _ date: Date,
        prefs: KBInsightPreferences = KBInsightPreferences(),
        calendar: Calendar = .current
    ) -> Date {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        guard prefs.isQuiet(minutes: (c.hour ?? 0) * 60 + (c.minute ?? 0)) else { return date }
        let end = at(minutes: prefs.quietEndMinutes, on: date, calendar: calendar)
        return end > date ? end : calendar.date(byAdding: .day, value: 1, to: end) ?? end
    }

    /// Il prossimo riepilogo serale (19:00), spostato fuori dal silenzio se serve.
    static func nextDigest(
        after now: Date,
        prefs: KBInsightPreferences,
        calendar: Calendar = .current
    ) -> Date {
        var digest = at(minutes: KBInsightPreferences.digestMinutes, on: now, calendar: calendar)
        if digest <= now {
            digest = calendar.date(byAdding: .day, value: 1, to: digest) ?? digest
        }
        return outsideQuietHours(digest, prefs: prefs, calendar: calendar)
    }

    private static func at(minutes: Int, on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }

    // MARK: - Testo

    private static func content(for row: KBInsight, type: KBInsightType, context: ModelContext) -> UNMutableNotificationContent? {
        let content = UNMutableNotificationContent()
        content.sound = .default
        if let category = KBInsightNotificationCategory.identifier(for: type) {
            content.categoryIdentifier = category
        }
        var info: [AnyHashable: Any] = [
            "type": typePrefix + type.rawValue,
            "familyId": row.familyId,
            "insightId": row.id,
        ]

        switch type {
        case .todoUnassignedDueSoon:
            let todoId = row.entityId
            guard let todo = try? context.fetch(FetchDescriptor<KBTodoItem>(
                predicate: #Predicate { $0.id == todoId }
            )).first, let due = todo.dueAt else { return nil }
            info["todoId"] = todo.id
            info["childId"] = todo.childId
            info["listId"] = todo.listId ?? ""
            content.userInfo = info
            KBNotificationLocalization.setText(
                on: content,
                titleKey: "Nessuno se ne sta occupando",
                bodyKey: "%1$@ · scade %2$@",
                bodyArgs: [.text(todo.title), .text(relativeDue(due, hasTime: todo.hasDueTime))]
            )

        case .treatmentDoseMissing:
            let treatmentId = String(row.entityId.split(separator: "@").first ?? "")
            guard let treatment = try? context.fetch(FetchDescriptor<KBTreatment>(
                predicate: #Predicate { $0.id == treatmentId }
            )).first else { return nil }
            info["treatmentId"] = treatment.id
            info["childId"] = treatment.childId
            content.userInfo = info
            let name = subjectName(of: treatment, context: context)
            if name.isEmpty {
                KBNotificationLocalization.setText(
                    on: content,
                    titleKey: "Dose da registrare",
                    bodyKey: "Una dose di oggi non risulta registrata"
                )
            } else {
                KBNotificationLocalization.setText(
                    on: content,
                    titleKey: "Dose da registrare",
                    bodyKey: "La dose di oggi per %@ non risulta registrata",
                    bodyArgs: [.text(name)]
                )
            }

        case .eventTomorrowNoReminder, .vaccineDue, .groceryStale:
            // Regole non ancora scritte: il motore non propone questi tipi.
            return nil
        }
        return content
    }

    private static func subjectName(of treatment: KBTreatment, context: ModelContext) -> String {
        if !treatment.petId.isEmpty {
            let pid = treatment.petId
            if let pet = try? context.fetch(FetchDescriptor<KBPet>(predicate: #Predicate { $0.id == pid })).first {
                return pet.name
            }
        }
        let cid = treatment.childId
        let child = try? context.fetch(FetchDescriptor<KBChild>(predicate: #Predicate { $0.id == cid })).first
        return child?.name ?? ""
    }

    /// «domani, 09:00» / «oggi»: nella lingua dell'app al momento della programmazione.
    private static func relativeDue(_ date: Date, hasTime: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: LanguageManager.shared.currentLanguageCode)
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = hasTime ? .short : .none
        return f.string(from: date)
    }
}
