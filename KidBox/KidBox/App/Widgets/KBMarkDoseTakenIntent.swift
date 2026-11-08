//
//  KBMarkDoseTakenIntent.swift
//  KidBox + KidBoxControlsExtension
//
//  Pulsanti «Presa» e «Saltata» del widget Cure. Il file deve stare nel target app e
//  nell'estensione (vedi eccezione nel progetto Xcode): se l'intent è anche
//  nell'app, il sistema può eseguirlo lì e la dose si scrive subito.
//

import AppIntents
import WidgetKit

struct KBMarkDoseTakenIntent: AppIntent {
    static let title: LocalizedStringResource = "Segna come presa"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Dose")
    var doseId: String

    @Parameter(title: "Presa", default: true)
    var taken: Bool

    init() {}
    init(doseId: String, taken: Bool = true) {
        self.doseId = doseId
        self.taken = taken
    }

    func perform() async throws -> some IntentResult {
        KBWidgetDoseQueue.enqueue(doseId, taken: taken)
        KBWidgetDoseQueue.markInSnapshot(doseId, taken: taken)
        WidgetCenter.shared.reloadAllTimelines()
        // Nell'app: scrive la dose e la sincronizza. Nell'estensione è nil e
        // la coda aspetta la prossima apertura.
        await KBWidgetDoseQueue.drainInApp?()
        return .result()
    }
}

/// Cerchietto del widget To-do: segna il to-do come fatto.
struct KBMarkTodoDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Segna come fatto"
    static let isDiscoverable: Bool = false

    @Parameter(title: "To-do")
    var todoId: String

    init() {}
    init(todoId: String) { self.todoId = todoId }

    func perform() async throws -> some IntentResult {
        KBWidgetTodoQueue.queue.enqueue(todoId)
        KBWidgetTodoQueue.markDoneInSnapshot(todoId)
        WidgetCenter.shared.reloadAllTimelines()
        await KBWidgetDoseQueue.drainInApp?()
        return .result()
    }
}

/// Cerchietto del widget Spesa: segna la voce come comprata.
struct KBMarkGroceryBoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Segna come comprato"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Voce")
    var itemId: String

    init() {}
    init(itemId: String) { self.itemId = itemId }

    func perform() async throws -> some IntentResult {
        KBWidgetGroceryQueue.queue.enqueue(itemId)
        KBWidgetGroceryQueue.markBoughtInSnapshot(itemId)
        WidgetCenter.shared.reloadAllTimelines()
        await KBWidgetDoseQueue.drainInApp?()
        return .result()
    }
}
