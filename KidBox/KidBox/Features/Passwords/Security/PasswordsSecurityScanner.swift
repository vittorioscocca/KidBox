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
    private let remote = PasswordRemoteStore()

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
            let prev = entry.pwnedCount

            let result = (try? await checker.check(plain)) ?? PwnedChecker.unknown
            if result == PwnedChecker.unknown {
                continue
            }

            // La data del controllo vive solo in locale: è "quando QUESTO device
            // ha verificato", non un dato della famiglia.
            entry.pwnedCheckedAt = .now
            touched += 1

            // Verdetto invariato: nessuna scrittura su Firestore. Prima ogni scan
            // riscriveva il documento intero di TUTTE le password, con
            // `updatedAt: serverTimestamp()`: ~150 scritture a settimana a
            // pagamento, contate come «aggiornamenti» nel rollup, e sugli altri
            // device tutte le password risultavano «modificate adesso» (la lista
            // si riordinava — il difetto che il commento qui sotto credeva di aver
            // chiuso, e che invece era chiuso solo in locale).
            //
            // `updatedAt` NON si tocca, né in locale né in remoto: significa
            // "quando l'utente ha modificato questa password", e uno scan non è
            // una modifica sua. La sincronizzazione regge: in ingresso
            // `applyEntryDTO` accetta con `remoteTs >= existing.updatedAt`, quindi
            // il nuovo `pwnedCount` si propaga anche a parità di timestamp.
            guard prev != result else { continue }

            // Solo i due campi del verdetto, e il valore locale si aggiorna solo se
            // il server l'ha preso: se la scrittura fallisce (offline) il prossimo
            // scan rivede la differenza e riprova, senza passare dall'outbox che
            // farebbe l'upsert intero.
            do {
                try await remote.updatePwnedVerdict(
                    entryId: entry.id,
                    familyId: familyId,
                    pwnedCount: result,
                    checkedAt: entry.pwnedCheckedAt ?? .now
                )
                entry.pwnedCount = result
            } catch {
                KBLog.sync.kbError("[PasswordSecurity] verdict write failed id=\(entry.id): \(error.localizedDescription)")
                continue
            }

            if (prev ?? 0) <= 0, result > 0 {
                newlyCompromised += 1
            }
        }

        if touched > 0 {
            try? modelContext.save()
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
