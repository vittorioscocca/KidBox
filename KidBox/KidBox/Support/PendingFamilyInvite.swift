//
//  PendingFamilyInvite.swift
//  KidBox
//
//  Invito famiglia arrivato da un Universal Link, tenuto da parte finché non è
//  possibile applicarlo.
//
//  Serve perché i due momenti quasi mai coincidono: chi riceve il link di norma
//  **non ha ancora un account**. Tocca il link, l'app si apre sul login, si
//  registra, e solo allora si può entrare in famiglia. Senza un posto dove
//  parcheggiare l'invito, quel percorso perderebbe il segreto per strada e
//  l'utente entrerebbe senza chiave — esattamente il difetto che il link
//  doveva eliminare.
//

import Foundation

extension Notification.Name {
    /// Un invito da link è stato messo da parte.
    ///
    /// Serve perché il link può arrivare ad app **già aperta**: il wizard ha
    /// letto `PendingFamilyInvite` solo all'`onAppear` e non se ne accorgerebbe,
    /// e `RootHostView` aspetterebbe il prossimo passaggio in primo piano — che
    /// è già avvenuto nel momento in cui l'URL viene consegnato.
    static let kbPendingFamilyInviteStored = Notification.Name("kbPendingFamilyInviteStored")
}

struct PendingFamilyInvite: Equatable {

    let familyId: String
    let inviteId: String
    /// Segreto base64url che sblocca la master key. Arriva dal **frammento**
    /// dell'URL, quindi non transita dai server né dai bot delle anteprime.
    let secret: String

    // MARK: - Parsing

    /// Estrae l'invito da un Universal Link, o `nil` se l'URL non è un invito valido.
    ///
    /// Formato atteso:
    /// `https://<dominio>/join?familyId=…&inviteId=…#k=<secret>`
    ///
    /// Il segreto è cercato **solo** nel frammento: accettarlo anche dalla query
    /// renderebbe possibile generare link che lo espongono ai server, vanificando
    /// la ragione per cui sta dopo il cancelletto.
    static func parse(from url: URL) -> PendingFamilyInvite? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.path == "/join" || comps.path.hasPrefix("/join/") else {
            return nil
        }

        let items = comps.queryItems ?? []
        func query(_ name: String) -> String? {
            items.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let familyId = query("familyId"), !familyId.isEmpty,
              let inviteId = query("inviteId"), !inviteId.isEmpty,
              let secret = secretFromFragment(comps.fragment), !secret.isEmpty else {
            KBLog.sync.kbError("PendingFamilyInvite: link non valido o senza segreto")
            return nil
        }

        return PendingFamilyInvite(familyId: familyId, inviteId: inviteId, secret: secret)
    }

    /// Legge `k=<secret>` dal frammento, tollerando altri parametri.
    private static func secretFromFragment(_ fragment: String?) -> String? {
        guard let fragment, !fragment.isEmpty else { return nil }
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == "k" else { continue }
            return String(parts[1])
        }
        return nil
    }

    /// Estrae l'invito dal payload di un QR (`kidbox://join?...&secret=...`).
    ///
    /// Il QR e il link portano la stessa cosa in due formati: qui il segreto è
    /// nella query, perché il QR non passa da nessun server e non ha bisogno del
    /// frammento. Ricondurli entrambi a `PendingFamilyInvite` fa sì che il join
    /// abbia un percorso solo, invece di due copie da tenere allineate.
    static func parse(fromQRPayload raw: String) -> PendingFamilyInvite? {
        guard let comps = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              comps.scheme == "kidbox",
              comps.host == "join",
              let items = comps.queryItems else {
            return nil
        }
        func query(_ name: String) -> String? {
            items.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let familyId = query("familyId"), !familyId.isEmpty,
              let inviteId = query("inviteId"), !inviteId.isEmpty,
              let secret = query("secret"), !secret.isEmpty else {
            return nil
        }
        return PendingFamilyInvite(familyId: familyId, inviteId: inviteId, secret: secret)
    }

    /// Payload equivalente al QR, per riusare `JoinWrapService` senza duplicarne
    /// la logica di sblocco della chiave.
    var qrEquivalentPayload: String {
        "kidbox://join?familyId=\(familyId)&inviteId=\(inviteId)&secret=\(secret)"
    }

    // MARK: - Persistenza

    private static let storeKey = "kb.pendingFamilyInvite"

    /// Mette da parte l'invito in attesa di login / app pronta.
    ///
    /// Sta in `UserDefaults` e non in memoria perché fra il tocco sul link e il
    /// join può esserci una registrazione completa, con l'app che passa in
    /// background (verifica email, Google, Apple) e può essere terminata.
    func store() {
        UserDefaults.standard.set(
            ["familyId": familyId, "inviteId": inviteId, "secret": secret],
            forKey: Self.storeKey
        )
        KBLog.sync.kbInfo("PendingFamilyInvite salvato familyId=\(familyId) inviteId=\(inviteId)")
        NotificationCenter.default.post(name: .kbPendingFamilyInviteStored, object: nil)
    }

    static func load() -> PendingFamilyInvite? {
        guard let dict = UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String],
              let familyId = dict["familyId"],
              let inviteId = dict["inviteId"],
              let secret = dict["secret"] else {
            return nil
        }
        return PendingFamilyInvite(familyId: familyId, inviteId: inviteId, secret: secret)
    }

    /// Da chiamare sempre a esito concluso, riuscito o meno.
    ///
    /// Anche in caso di fallimento: l'invito è monouso e a scadenza, quindi
    /// ritentarlo all'infinito a ogni avvio produrrebbe solo errori ripetuti.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: storeKey)
        KBLog.sync.kbDebug("PendingFamilyInvite rimosso")
    }
}
