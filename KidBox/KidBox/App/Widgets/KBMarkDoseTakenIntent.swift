//
//  KBMarkDoseTakenIntent.swift
//  KidBox + KidBoxControlsExtension
//
//  Pulsante «Presa» del widget Cure. Il file deve stare nel target app e
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

    init() {}
    init(doseId: String) { self.doseId = doseId }

    func perform() async throws -> some IntentResult {
        KBWidgetDoseQueue.enqueue(doseId)
        KBWidgetDoseQueue.markTakenInSnapshot(doseId)
        WidgetCenter.shared.reloadAllTimelines()
        // Nell'app: scrive la dose e la sincronizza. Nell'estensione è nil e
        // la coda aspetta la prossima apertura.
        await KBWidgetDoseQueue.drainInApp?()
        return .result()
    }
}
