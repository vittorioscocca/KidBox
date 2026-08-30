//
//  SyncCenter+ForceRefresh.swift
//  KidBox
//

import Foundation
import SwiftData

// MARK: - Force refresh (pull-to-refresh)

extension SyncCenter {

    /// Rilegge dal server i dati di una sezione: è il motore del pull-to-refresh.
    ///
    /// Non esiste una "fetch" separata da invocare: la sorgente di verità sono i
    /// listener realtime, e un `addSnapshotListener` appena creato rilegge dal
    /// server l'INTERA collection. Il force refresh quindi è semplicemente
    /// staccare e riagganciare i listener della sezione (`reattach`), più uno
    /// svuotamento dell'outbox: così il gesto serve anche a spingere fuori le
    /// modifiche rimaste in coda offline, che è quello che l'utente si aspetta
    /// quando tira giù perché "non si vede il dato".
    ///
    /// - Parameters:
    ///   - listenerKeys: chiavi dei listener protetti da `isListenerBound`
    ///     (`todo`, `pets`, `vehicles`, `expenses`, …). Senza invalidarne il
    ///     binding, lo `start…Realtime` dentro `reattach` verrebbe saltato e il
    ///     pull non rileggerebbe nulla.
    ///   - modelContext: se passato, il pull fa anche un `flushGlobal`.
    ///   - reattach: stop + start dei listener della sezione (o, per le sezioni
    ///     senza listener, la loro fetch one-shot).
    func forceRefresh(
        listenerKeys: [String] = [],
        modelContext: ModelContext? = nil,
        reattach: @MainActor () -> Void
    ) async {
        KBLog.sync.kbInfo("forceRefresh keys=[\(listenerKeys.joined(separator: ","))]")
        unbindListeners(listenerKeys)
        reattach()
        if let modelContext {
            flushGlobal(modelContext: modelContext)
        }
        // Lo spinner di `refreshable` sparisce appena la closure ritorna, mentre
        // le risposte dei listener arrivano subito dopo: senza questa attesa il
        // gesto sembrerebbe non aver fatto nulla.
        try? await Task.sleep(nanoseconds: 900_000_000)
    }

    /// Force refresh delle schermate di Salute.
    ///
    /// Vive qui e non nelle singole view perché i dati di quella sezione
    /// arrivano da cinque listener diversi (cure, visite, vaccini, analisi,
    /// cartella) e la home li mostra tutti insieme: replicare l'elenco in ogni
    /// view avrebbe voluto dire dimenticarne uno prima o poi.
    ///
    /// - Parameter scope: quali listener riagganciare. Le liste di dettaglio
    ///   passano solo il proprio, la home li passa tutti.
    func forceRefreshHealth(
        _ scope: KBHealthRefreshScope = .all,
        familyId: String,
        childId: String,
        modelContext: ModelContext
    ) async {
        await forceRefresh(modelContext: modelContext) {
            if scope.contains(.treatments) {
                stopTreatmentsRealtime()
                startTreatmentsRealtime(familyId: familyId, modelContext: modelContext)
            }
            if scope.contains(.visits) {
                stopVisitsRealtime()
                startVisitsRealtime(familyId: familyId, modelContext: modelContext)
            }
            if scope.contains(.vaccines) {
                stopVaccinesRealtime()
                startVaccinesRealtime(familyId: familyId, childId: childId, modelContext: modelContext)
            }
            if scope.contains(.exams) {
                // `startMedicalExamsRealtime` esce subito se il listener è già
                // vivo: senza lo stop il refresh non rileggerebbe nulla.
                stopMedicalExamsRealtime()
                startMedicalExamsRealtime(familyId: familyId, childId: childId, modelContext: modelContext)
            }
            if scope.contains(.profile) {
                stopPediatricProfileRealtime()
                startPediatricProfileRealtime(familyId: familyId, childId: childId, modelContext: modelContext)
            }
        }
    }
}

/// I listener della sezione Salute che un pull-to-refresh può riagganciare.
struct KBHealthRefreshScope: OptionSet {
    let rawValue: Int

    static let treatments = KBHealthRefreshScope(rawValue: 1 << 0)
    static let visits     = KBHealthRefreshScope(rawValue: 1 << 1)
    static let vaccines   = KBHealthRefreshScope(rawValue: 1 << 2)
    static let exams      = KBHealthRefreshScope(rawValue: 1 << 3)
    static let profile    = KBHealthRefreshScope(rawValue: 1 << 4)

    static let all: KBHealthRefreshScope = [.treatments, .visits, .vaccines, .exams, .profile]
}
