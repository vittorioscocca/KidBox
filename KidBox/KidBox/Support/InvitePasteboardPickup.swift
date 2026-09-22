//
//  InvitePasteboardPickup.swift
//  KidBox
//
//  Recupera un invito toccato PRIMA di installare l'app.
//
//  Il problema, misurato a settembre 2026: chi riceve un link senza avere
//  KidBox arriva su kidboxapp.com/join, installa dallo store, apre l'app — e
//  l'app non sa niente dell'invito, quindi gli propone di creare una famiglia
//  sua. In una settimana: 5 viste della pagina, 2 tap sullo store, 0 join.
//  Tornare sul messaggio e ritoccare il link non lo fa quasi nessuno.
//
//  Apple non ha un equivalente del referrer di Play, quindi la strada è una
//  sola: la pagina /join copia il link negli appunti un istante prima di
//  mandare allo store, e qui lo si rilegge. In due tempi, per rispettare il
//  sistema:
//
//  1. `mightHaveInvite()` — chiede al sistema se negli appunti c'è
//     probabilmente un URL, SENZA leggerlo: nessun banner, nessun permesso.
//     Serve a decidere se proporre il passo 2.
//  2. `pickUp()` — legge davvero, dopo un tocco esplicito dell'utente. iOS
//     mostra il suo banner «Consenti incolla» (una volta). Se il contenuto è
//     un link d'invito KidBox lo salva come `PendingFamilyInvite`, e da lì in
//     poi tutto è identico al link toccato ad app installata.
//
//  Se gli appunti sono vuoti o contengono altro non cambia niente: il wizard
//  resta quello di prima. Il segreto non lascia mai il dispositivo.
//
//  Gemello di `InviteReferrerPickup.kt` su Android (che ha in più il referrer).
//

import UIKit

enum InvitePasteboardPickup {

    /// `true` se negli appunti c'è probabilmente un URL. Non legge il
    /// contenuto: usa il rilevamento di pattern del sistema, che non mostra
    /// il banner di incolla.
    static func mightHaveInvite() async -> Bool {
        guard PendingFamilyInvite.load() == nil else { return false }
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings || pasteboard.hasURLs else { return false }
        do {
            let patterns = try await pasteboard.detectedPatterns(for: [\.probableWebURL])
            return patterns.contains(\.probableWebURL)
        } catch {
            // Il rilevamento può fallire su appunti insoliti: si ripiega sul
            // fatto che ci sia un URL o un testo, senza leggerlo.
            return pasteboard.hasURLs
        }
    }

    /// Legge gli appunti (banner di sistema) e, se contengono un link
    /// d'invito, lo mette da parte. Torna l'invito trovato, o `nil`.
    @discardableResult
    static func pickUp() -> PendingFamilyInvite? {
        let pasteboard = UIPasteboard.general
        var candidates: [String] = []
        if let url = pasteboard.url { candidates.append(url.absoluteString) }
        if let text = pasteboard.string { candidates.append(text) }
        for raw in candidates {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.localizedCaseInsensitiveContains("/join"),
                  let url = URL(string: trimmed),
                  let invite = PendingFamilyInvite.parse(from: url) else { continue }
            invite.store()
            KBLog.sync.kbInfo("Invito recuperato dagli appunti familyId=\(invite.familyId)")
            return invite
        }
        KBLog.sync.kbDebug("Appunti senza invito KidBox")
        return nil
    }
}
