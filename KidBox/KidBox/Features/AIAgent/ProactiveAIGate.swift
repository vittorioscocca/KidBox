//
//  ProactiveAIGate.swift
//  KidBox
//
//  Cancello della Mente proattiva (briefing, recap, pattern salute): sono
//  funzioni Pro/Max che partono da sole, quindi senza questo controllo un Free
//  con l'AI accesa consumerebbe il bonus una tantum senza averlo chiesto.
//  `isAIAccessible` non basta: è vero anche per un Free col bonus intatto.
//
//  Il piano si rilegge da Firestore solo quando un servizio sta per generare
//  (al più qualche volta al giorno); le tre richieste che partono insieme
//  all'apertura condividono la stessa lettura. Stesso cancello su Android
//  (`ProactiveAIGate.kt`).
//

import Foundation

@MainActor
enum ProactiveAIGate {

    private static var inFlight: Task<Bool, Never>?

    static func allows() async -> Bool {
        if let inFlight { return await inFlight.value }
        let task = Task { @MainActor in
            await KBSubscriptionManager.shared.loadPlan()
            return KBSubscriptionManager.shared.currentPlan != .free
        }
        inFlight = task
        let allowed = await task.value
        inFlight = nil
        if !allowed {
            KBLog.ai.kbInfo("ProactiveAIGate: free plan, automatic AI skipped")
        }
        return allowed
    }
}
