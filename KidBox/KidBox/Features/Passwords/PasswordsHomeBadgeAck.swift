//
//  PasswordsHomeBadgeAck.swift
//  KidBox
//
//  Il badge sulla Home mostra le password compromesse (HIBP) finché l’utente non apre
//  la home Password: a quel punto si considera “visto” l’insieme corrente e il badge si azzera
//  finché non cambia l’elenco delle voci compromesse (nuova compromissione o risoluzione).
//

import Foundation

enum PasswordsHomeBadgeAck {
    static func storageKey(familyId: String) -> String {
        "kb.passwords.homeCompromisedAckSig.\(familyId)"
    }

    /// Firma ordinata degli id delle entry visibili con `pwnedCount > 0`.
    static func compromisedSignature(entries: [PasswordEntry], currentUid: String?) -> String {
        entries
            .filter { $0.deletedAt == nil && $0.isVisible(to: currentUid) && ($0.pwnedCount ?? 0) > 0 }
            .map(\.id)
            .sorted()
            .joined(separator: "|")
    }

    /// Salva la firma attuale (anche vuota se non ci sono compromesse).
    static func acknowledgeCurrent(entries: [PasswordEntry], familyId: String, currentUid: String?) {
        let sig = compromisedSignature(entries: entries, currentUid: currentUid)
        UserDefaults.standard.set(sig, forKey: storageKey(familyId: familyId))
    }

    /// Numero da mostrare sul badge Home (0 se l’utente ha già “visto” questo stato).
    static func homeBadgeCount(entries: [PasswordEntry], familyId: String, currentUid: String?) -> Int {
        let compromised = entries.filter {
            $0.deletedAt == nil && $0.isVisible(to: currentUid) && ($0.pwnedCount ?? 0) > 0
        }
        guard !compromised.isEmpty else { return 0 }
        let sig = compromisedSignature(entries: entries, currentUid: currentUid)
        let key = storageKey(familyId: familyId)
        if UserDefaults.standard.string(forKey: key) == sig { return 0 }
        return compromised.count
    }
}
