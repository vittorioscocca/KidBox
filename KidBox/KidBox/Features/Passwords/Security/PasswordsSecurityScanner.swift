//
//  PasswordsSecurityScanner.swift
//  KidBox
//

import Foundation
import SwiftData
import FirebaseAuth

@MainActor
final class PasswordsSecurityScanner {
    private let modelContext: ModelContext
    private let familyId: String
    private let checker: PwnedChecker

    init(modelContext: ModelContext, familyId: String, checker: PwnedChecker = .shared) {
        self.modelContext = modelContext
        self.familyId = familyId
        self.checker = checker
    }

    /// Esegue lo scan completo su tutte le entry visibili.
    /// - Returns: numero di entry newly-compromised trovate in questo run.
    func runFullSecurityScan() async -> Int {
        let uid = Auth.auth().currentUser?.uid
        let descriptor = FetchDescriptor<PasswordEntry>(
            predicate: #Predicate<PasswordEntry> { $0.familyId == familyId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\PasswordEntry.updatedAt, order: .reverse)]
        )
        guard let all = try? modelContext.fetch(descriptor) else { return 0 }
        let visible = all.filter { $0.isVisible(to: uid) }

        var newlyCompromised = 0
        var touched = 0

        for entry in visible {
            // onlyCreator: solo il creatore esegue il check.
            let vis = PasswordEntry.normalizedPasswordVisibility(entry.visibility)
            if vis == KBVisibilityScope.onlyCreator, entry.createdBy != uid {
                continue
            }

            guard let plain = try? entry.decryptPassword(), !plain.isEmpty else { continue }
            let prev = entry.pwnedCount ?? 0

            let result = (try? await checker.check(plain)) ?? PwnedChecker.unknown
            if result == PwnedChecker.unknown {
                continue
            }

            entry.pwnedCount = result
            entry.pwnedCheckedAt = .now
            // `updatedAt` NON si tocca: significa "quando l'utente ha modificato
            // questa password", e uno scan di sicurezza non è una modifica sua.
            //
            // Toccarlo faceva danni visibili: le sezioni della lista sono ordinate
            // per data di modifica decrescente (PasswordsHomeView.sections), quindi
            // a ogni risposta del controllo quella voce saltava in cima al gruppo.
            // Con lo scan che procede una password alla volta — c'è un throttle di
            // 200ms per richiesta in PwnedChecker — la lista si riordinava sotto gli
            // occhi dell'utente per tutta la durata, per poi fermarsi di colpo.
            //
            // La data del controllo ha già il suo campo dedicato, `pwnedCheckedAt`,
            // aggiornato qui sopra. La sincronizzazione continua a funzionare: in
            // ingresso `applyEntryDTO` accetta con `remoteTs >= existing.updatedAt`,
            // quindi il nuovo `pwnedCount` si propaga anche a parità di timestamp.
            entry.syncState = .pendingUpsert
            PasswordsRepository.enqueuePasswordEntryUpsert(
                entryId: entry.id,
                familyId: familyId,
                modelContext: modelContext
            )

            if prev <= 0, result > 0 {
                newlyCompromised += 1
            }
            touched += 1
        }

        if touched > 0 {
            try? modelContext.save()
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            UserDefaults.standard.set(Date(), forKey: Self.lastScanKey(familyId: familyId))
            UserDefaults.standard.set(true, forKey: Self.moduleOpenedKey(familyId: familyId))
        }

        if newlyCompromised > 0 {
            await NotificationManager.shared.schedulePasswordSecuritySummaryNotification(
                familyId: familyId,
                newlyCompromised: newlyCompromised
            )
        }
        return newlyCompromised
    }

    static func markModuleOpened(familyId: String) {
        UserDefaults.standard.set(true, forKey: moduleOpenedKey(familyId: familyId))
    }

    /// Chiave della preferenza "controllo settimanale automatico".
    ///
    /// Esposta perché la usa anche `@AppStorage` nella schermata Sicurezza:
    /// così l'interruttore e il gate leggono lo stesso valore senza duplicarne
    /// il nome in due posti.
    static let weeklyScanEnabledKey = "kb.password.security.weeklyScanEnabled"

    /// `true` se l'utente non ha disattivato il controllo automatico.
    ///
    /// Non si usa direttamente `bool(forKey:)`: restituirebbe `false` quando la
    /// preferenza non è mai stata scritta, cioè disattiverebbe la funzione a
    /// tutti quelli che non l'hanno mai toccata. Il valore assente vale
    /// **attivo**, come il `?: true` di `PasswordSecurityPreferences` su Android.
    static var isWeeklyAutoScanEnabled: Bool {
        guard UserDefaults.standard.object(forKey: weeklyScanEnabledKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: weeklyScanEnabledKey)
    }

    static func shouldRunWeeklyAutoScan(familyId: String) -> Bool {
        // Il controllo interroga un servizio esterno con gli hash delle password:
        // se l'utente lo ha disattivato non deve partire da nessuna parte. Questo
        // gate è attraversato sia dal task in background (AppDelegate) sia
        // dall'apertura della schermata, quindi copre entrambi i percorsi.
        guard isWeeklyAutoScanEnabled else { return false }
        guard UserDefaults.standard.bool(forKey: moduleOpenedKey(familyId: familyId)) else { return false }
        guard let last = UserDefaults.standard.object(forKey: lastScanKey(familyId: familyId)) as? Date else {
            return true
        }
        return Date().timeIntervalSince(last) >= 7 * 24 * 60 * 60
    }

    private static func moduleOpenedKey(familyId: String) -> String {
        "kb.password.security.opened.\(familyId)"
    }

    private static func lastScanKey(familyId: String) -> String {
        "kb.password.security.lastScan.\(familyId)"
    }
}
