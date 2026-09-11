//
//  KBFamilyAccessGuard.swift
//  KidBox
//
//  Presidio davanti alle Cloud Function che portano un `familyId`.
//
//  Il problema che risolve, visto nei log l'8/09/2026: quando un utente esce
//  (o viene tolto) da una famiglia, l'app non se ne accorge. `activeFamilyId`
//  resta in App Group e ogni schermata continua a chiedere al server i dati di
//  quella famiglia — `getAIUsage`, `getStorageUsage`, `askAI`. Il server
//  risponde `permission-denied` ogni volta, e il client ritenta: dieci rifiuti
//  in dieci minuti per un solo utente, che è come si sono generati i due terzi
//  degli errori di quella settimana.
//
//  Qui il rifiuto viene riconosciuto (dal `reason` nei `details`, non dal
//  messaggio, che è tradotto), la chiamata smette di ripartire per un po', e
//  il caso viene passato al macchinario di revoca già esistente in
//  `SyncCenter`, che è l'unico autorizzato a decidere se è un'espulsione vera.
//
//  ⚠️ Il wipe locale non si fa mai da qui: solo `verifyRevocation` sa
//  distinguere un'espulsione da un rifiuto infrastrutturale, e nel dubbio non
//  si tocca niente. Vedi il commento su `SyncCenter.verifyRevocation`.
//

import Foundation
import FirebaseFunctions

@MainActor
final class KBFamilyAccessGuard {

    static let shared = KBFamilyAccessGuard()

    /// Il `details.reason` che il server manda su un permission-denied per
    /// mancata appartenenza. Deve restare uguale a `NOT_FAMILY_MEMBER` in
    /// `functions/index.js`.
    static let notFamilyMemberReason = "not-family-member"

    /// Quanto si sta zitti dopo un rifiuto non confermato come espulsione.
    /// Serve solo a non martellare: se è un problema transitorio si riprende
    /// da solo, se è un'espulsione vera ci pensa la revoca.
    private static let cooldown: TimeInterval = 60

    /// Dopo un'espulsione confermata non ha senso ritentare: la famiglia
    /// cambia per altra via (la revoca) e il breaker viene azzerato da
    /// `clear(familyId:)`.
    private static let confirmedCooldown: TimeInterval = 3600

    private var blockedUntil: [String: Date] = [:]

    private init() {}

    // MARK: - Riconoscimento

    /// `true` se l'errore di una callable dice «non sei (più) membro di questa
    /// famiglia». Si legge dai `details`, non dal messaggio: quello è testo
    /// per l'utente e cambia con la lingua.
    nonisolated static func isNotAMember(_ error: Error) -> Bool {
        let ns = error as NSError
        guard FunctionsErrorCode(rawValue: ns.code) == .permissionDenied else { return false }
        guard let details = ns.userInfo[FunctionsErrorDetailsKey] as? [String: Any] else { return false }
        return details["reason"] as? String == notFamilyMemberReason
    }

    // MARK: - Breaker

    /// `true` se le chiamate verso questa famiglia sono sospese.
    func isBlocked(_ familyId: String) -> Bool {
        guard let until = blockedUntil[familyId] else { return false }
        if until <= Date() {
            blockedUntil.removeValue(forKey: familyId)
            return false
        }
        return true
    }

    /// Riapre le chiamate verso una famiglia. Da chiamare quando la situazione
    /// è cambiata per davvero: join, switch famiglia, nuovo login.
    func clear(familyId: String? = nil) {
        if let familyId {
            blockedUntil.removeValue(forKey: familyId)
        } else {
            blockedUntil.removeAll()
        }
    }

    /// Registra un rifiuto per mancata appartenenza: sospende le chiamate e
    /// chiede a `SyncCenter` di verificare se è un'espulsione vera.
    func noteAccessDenied(familyId: String, source: String, error: Error) {
        guard !familyId.isEmpty else { return }

        // Già sospesa: la verifica è in corso o è appena stata fatta.
        if isBlocked(familyId) { return }

        blockedUntil[familyId] = Date().addingTimeInterval(Self.cooldown)
        KBLog.sync.kbError(
            "Callable rifiutata: non siamo membri di questa famiglia. " +
            "Chiamate sospese \(Int(Self.cooldown))s source=\(source) familyId=\(familyId)"
        )

        Task { @MainActor in
            switch await SyncCenter.verifyRevocation(familyId: familyId) {
            case .confirmed:
                self.blockedUntil[familyId] = Date().addingTimeInterval(Self.confirmedCooldown)
                // Da qui in poi decide il macchinario di revoca: ferma i
                // listener, verifica di nuovo e, se conferma, emette
                // currentUserRevoked.
                SyncCenter.shared.handleFamilyAccessLost(
                    familyId: familyId,
                    source: "callable:\(source)",
                    error: error
                )
            case .notRevoked:
                // Il documento membro c'è ancora: il rifiuto viene da altro
                // (rules, attestazione, un familyId sbagliato passato dalla UI).
                // Non si tocca niente, si riprova dopo il cooldown.
                KBLog.sync.kbError(
                    "Callable rifiutata ma il documento membro è al suo posto: " +
                    "nessuna espulsione. source=\(source) familyId=\(familyId)"
                )
            case .undetermined:
                KBLog.sync.kbError(
                    "Callable rifiutata, verifica impossibile (rete o credenziali): " +
                    "nessuna espulsione. source=\(source) familyId=\(familyId)"
                )
            }
        }
    }
}

// MARK: - Chiamata protetta

enum KBFamilyCallableError: LocalizedError {
    /// Le chiamate verso questa famiglia sono sospese dal breaker.
    case accessSuspended
    /// Nessuna famiglia attiva: la chiamata non ha senso e non parte.
    case missingFamily

    var errorDescription: String? {
        switch self {
        case .accessSuspended:
            return String(
                localized: "Non hai più accesso a questa famiglia.",
                comment: "Callable rifiutata: l'utente non è più membro della famiglia"
            )
        case .missingFamily:
            return String(
                localized: "Famiglia non trovata. Riprova dopo aver effettuato il login.",
                comment: "Callable non inviata: nessuna famiglia attiva"
            )
        }
    }
}

extension KBFamilyAccessGuard {

    /// Chiama una Cloud Function che porta un `familyId`, con il presidio
    /// davanti (non parte se le chiamate sono sospese) e dietro (riconosce il
    /// rifiuto per mancata appartenenza).
    ///
    /// Ogni callable con `familyId` dovrebbe passare di qui: è il solo punto in
    /// cui il rifiuto viene visto una volta sola invece che in otto schermate.
    nonisolated static func call(
        _ name: String,
        familyId: String,
        payload: [String: Any] = [:],
        timeout: TimeInterval? = nil,
        source: String
    ) async throws -> HTTPSCallableResult {
        guard !familyId.isEmpty else {
            throw KBFamilyCallableError.missingFamily
        }
        if await shared.isBlocked(familyId) {
            KBLog.sync.kbDebug("Callable \(name) non inviata: accesso sospeso familyId=\(familyId)")
            throw KBFamilyCallableError.accessSuspended
        }

        var body = payload
        body["familyId"] = familyId

        let callable = Functions.functions(region: "europe-west1").httpsCallable(name)
        if let timeout {
            callable.timeoutInterval = timeout
        }

        do {
            return try await callable.call(body)
        } catch {
            if isNotAMember(error) {
                await shared.noteAccessDenied(familyId: familyId, source: source, error: error)
            }
            throw error
        }
    }
}
