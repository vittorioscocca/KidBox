//
//  TodoReminderNotifications.swift
//  KidBox
//
//  «Fatto» sul promemoria di un to-do: chiude il to-do senza aprire l'app.
//
//  Due ingressi, una sola scrittura (`TodoReminderDoneAction`):
//  - la notifica locale, con la categoria `TODO_REMINDER`;
//  - la sveglia AlarmKit di un to-do urgente, col pulsante secondario che
//    lancia `CompleteTodoFromAlarmIntent`.
//
//  Il pulsante rotondo che AlarmKit disegna da sé spegne soltanto la sveglia:
//  «Fatto» è un'altra cosa e lo dice a parole.
//

import AppIntents
import FirebaseCore
import Foundation
import SwiftData
import UserNotifications
internal import os

enum TodoReminderNotificationCategory {
    static let identifier = "TODO_REMINDER"
    static let actionDone = "TODO_REMINDER_DONE"

    static var category: UNNotificationCategory {
        let done = UNNotificationAction(
            identifier: actionDone,
            title: NSLocalizedString("✅ Fatto", comment: "Todo reminder notification action done"),
            options: []
        )
        return UNNotificationCategory(
            identifier: identifier,
            actions: [done],
            intentIdentifiers: [],
            options: []
        )
    }
}

enum TodoReminderActionHandler {

    /// - Returns: `true` se era l'azione «Fatto» (non un tap normale).
    static func handle(response: UNNotificationResponse) async -> Bool {
        guard response.actionIdentifier == TodoReminderNotificationCategory.actionDone else { return false }

        let content = response.notification.request.content
        let userInfo = content.userInfo
        guard let todoId = userInfo["todoId"] as? String, !todoId.isEmpty else {
            KBLog.todo.kbError("TodoReminderActionHandler: payload senza todoId")
            return true
        }
        await TodoReminderDoneAction.run(
            todoId: todoId,
            familyId: userInfo["familyId"] as? String ?? "",
            childId: userInfo["childId"] as? String ?? "",
            listId: userInfo["listId"] as? String ?? "",
            title: content.body
        )
        return true
    }
}

/// La scrittura vera. **Non è un interruttore** come la spunta nelle liste:
/// se nel frattempo un altro membro ha già chiuso il to-do, un toggle lo
/// riaprirebbe proprio a chi ha premuto «Fatto».
@MainActor
enum TodoReminderDoneAction {

    /// Lo inietta `KidBoxApp.init()`. L'intent della sveglia può svegliare
    /// l'app da chiusa, e lì non si può contare sulla catena dell'AppDelegate.
    static var container: ModelContainer?

    /// Quanto aspettare che l'avvio a freddo abbia preparato database e Firebase.
    private static let launchWait: Duration = .seconds(5)

    static func run(todoId: String, familyId: String, childId: String, listId: String, title: String) async {
        // La sveglia si spegne e la notifica sparisce subito: l'utente ha già
        // scelto, e se la scrittura fallisce lo dice l'avviso qui sotto.
        TodoReminderService.cancel(todoId: todoId)

        guard let context = await readyContext(), KBUid.current != nil else {
            KBLog.todo.kbError("TodoReminderDoneAction: app non pronta o nessun utente todoId=\(todoId)")
            await scheduleRetryNotice(todoId: todoId, familyId: familyId, childId: childId, listId: listId, title: title)
            return
        }
        do {
            guard let todo = try fetchTodo(id: todoId, in: context) else {
                // Cancellato altrove: non resta niente da chiudere.
                KBLog.todo.kbInfo("TodoReminderDoneAction: to-do non trovato todoId=\(todoId)")
                return
            }
            guard !todo.isDone, !todo.isDeleted else {
                KBLog.todo.kbInfo("TodoReminderDoneAction: già chiuso todoId=\(todoId)")
                return
            }
            let uid = KBUid.current ?? "local"
            let now = Date()
            todo.isDone = true
            todo.doneAt = now
            todo.doneBy = uid
            todo.reminderEnabled = false
            todo.reminderId = nil
            todo.updatedAt = now
            todo.updatedBy = uid
            todo.syncState = .pendingUpsert
            try context.save()

            // Da qui il lavoro è al sicuro: senza rete l'operazione resta nella
            // coda di sync e riparte da sola, niente avviso di riprova.
            SyncCenter.shared.enqueueTodoUpsert(todoId: todo.id, familyId: todo.familyId, modelContext: context)
            await SyncCenter.shared.flush(modelContext: context, remote: TodoRemoteStore())
            KBLog.todo.kbInfo("TodoReminderDoneAction: to-do chiuso todoId=\(todoId)")
        } catch {
            KBLog.todo.kbError("TodoReminderDoneAction: save FAIL todoId=\(todoId) err=\(error.localizedDescription)")
            await scheduleRetryNotice(todoId: todoId, familyId: familyId, childId: childId, listId: listId, title: title)
        }
    }

    private static func readyContext() async -> ModelContext? {
        let deadline = ContinuousClock.now + launchWait
        while container == nil || FirebaseApp.app() == nil {
            guard ContinuousClock.now < deadline else { return nil }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return container?.mainContext
    }

    private static func fetchTodo(id: String, in context: ModelContext) throws -> KBTodoItem? {
        var descriptor = FetchDescriptor<KBTodoItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Un «Fatto» non deve perdersi in silenzio: l'avviso riapre il to-do.
    private static func scheduleRetryNotice(todoId: String, familyId: String, childId: String, listId: String, title: String) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Non segnato come fatto")
        content.body = title.isEmpty
            ? String(localized: "Tocca per riprovare.")
            : String(localized: "Tocca per riprovare: \(title)")
        content.sound = .default
        content.userInfo = [
            "type": "todo_reminder",
            "todoId": todoId,
            "listId": listId,
            "familyId": familyId,
            "childId": childId,
        ]
        let request = UNNotificationRequest(
            identifier: "todo-reminder-done-retry-\(todoId)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            KBLog.todo.kbError("TodoReminderDoneAction: avviso di riprova non creato err=\(error.localizedDescription)")
        }
    }
}

#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
/// Il pulsante «Fatto» sulla sveglia di un to-do urgente. Non compare in
/// Comandi Rapidi: è il pezzo interno di una sveglia, non una funzione da offrire.
struct CompleteTodoFromAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Fatto"
    static let isDiscoverable = false

    @Parameter(title: "To-do") var todoId: String
    @Parameter(title: "Famiglia") var familyId: String
    @Parameter(title: "Figlio") var childId: String
    @Parameter(title: "Lista") var listId: String
    @Parameter(title: "Titolo") var todoTitle: String

    init() {}

    init(todoId: String, familyId: String, childId: String, listId: String, todoTitle: String) {
        self.todoId = todoId
        self.familyId = familyId
        self.childId = childId
        self.listId = listId
        self.todoTitle = todoTitle
    }

    func perform() async throws -> some IntentResult {
        await TodoReminderDoneAction.run(
            todoId: todoId,
            familyId: familyId,
            childId: childId,
            listId: listId,
            title: todoTitle
        )
        return .result()
    }
}
#endif
