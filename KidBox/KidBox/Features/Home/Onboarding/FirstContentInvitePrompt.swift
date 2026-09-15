//
//  FirstContentInvitePrompt.swift
//  KidBox
//
//  L'invito nel momento giusto: subito dopo aver creato qualcosa, se in
//  famiglia non c'è ancora nessun altro che possa vederlo.
//
//  Perché un'altra superficie, quando la Home ha già la checklist «Invita un
//  familiare» e il motore nudge la push `family_invite`. I numeri dell'11/08 →
//  14/09/2026: la checklist mostrata a 77 persone, toccata da 13, chiusa da un
//  secondo membro per 11; la push pianificata per 12, aperta da nessuno. Sono
//  richieste in astratto — «invita» — fatte a chi non ha ancora niente da
//  condividere, ripetute ogni giorno finché non le si ignora. Il passo invito
//  del wizard, per lo stesso motivo, lo salta il 55%.
//
//  Qui la richiesta è concreta e arriva una volta sola: hai appena aggiunto un
//  documento, e per ora lo vedi solo tu. È la frase che dice il problema che
//  KidBox risolve, nel momento in cui esiste davvero.
//
//  Regole:
//  - una volta per utente, per sempre. Chi dice «Non ora» non lo rivede: le
//    altre due richieste continuano a esistere, non serve una terza che insiste;
//  - solo se la famiglia attiva ha UN membro. Chi ne ha già due o più non ha
//    bisogno dell'invito, e la prima creazione «consuma» comunque l'occasione,
//    così un membro che se ne va in futuro non fa riapparire un foglio pensato
//    per il primo giorno;
//  - parte da `AppAnalytics.contentCreated`, l'unico punto attraversato da
//    tutti i salvataggi (quindici tipi di contenuto): aggiungere una chiamata
//    in ogni schermata sarebbe stato il modo per dimenticarne una.
//

import Foundation
import SwiftData
import FirebaseAuth

enum FirstContentInvitePrompt {

    /// Pubblicata da `AppAnalytics.contentCreated`; la ascolta `RootHostView`,
    /// che ha il contesto dati per decidere e la gerarchia per presentare.
    static let notification = Notification.Name("kbFirstContentCreated")
    static let contentTypeKey = "contentType"

    private static let doneKeyPrefix = "kb_firstContentInvitePromptDone."

    /// Chiave per utente, non per dispositivo: due account sullo stesso
    /// telefono sono due persone, e ciascuna ha diritto alla sua occasione.
    private static var doneKey: String {
        doneKeyPrefix + (Auth.auth().currentUser?.uid ?? "anonymous")
    }

    static var isDone: Bool {
        get { UserDefaults.standard.bool(forKey: doneKey) }
        set { UserDefaults.standard.set(newValue, forKey: doneKey) }
    }

    /// Da chiamare a ogni contenuto creato. Costa un `bool` finché l'occasione
    /// non è stata consumata, niente dopo.
    static func noteContentCreated(type: String) {
        guard !isDone, Auth.auth().currentUser != nil else { return }
        NotificationCenter.default.post(
            name: notification,
            object: nil,
            userInfo: [contentTypeKey: type]
        )
    }

    /// Decide se mostrare il foglio e, in ogni caso, consuma l'occasione.
    ///
    /// Vero solo se la famiglia attiva ha esattamente un membro. Con due o più
    /// la risposta è no *e* l'occasione è comunque spesa: vedi le regole in
    /// testa al file.
    @MainActor
    static func shouldPresent(modelContext: ModelContext, familyId: String?) -> Bool {
        guard !isDone, let familyId, !familyId.isEmpty else { return false }
        isDone = true
        let members = (try? modelContext.fetchCount(
            FetchDescriptor<KBFamilyMember>(predicate: #Predicate {
                $0.familyId == familyId && $0.isDeleted == false
            })
        )) ?? 0
        return members == 1
    }

    /// Il contenuto appena creato, nella frase del foglio. Le chiavi sono i
    /// tipi di `AppAnalytics.contentCreated`; per un tipo nuovo che nessuno ha
    /// ancora aggiunto qui la frase resta generica, non sbagliata.
    static func subject(for contentType: String) -> String {
        switch contentType {
        case "documents":     return String(localized: "questo documento")
        case "photos":        return String(localized: "questa foto")
        case "calendar":      return String(localized: "questo evento")
        case "expenses":      return String(localized: "questa spesa")
        case "grocery":       return String(localized: "questa lista della spesa")
        case "todo":          return String(localized: "questa cosa da fare")
        case "notes":         return String(localized: "questa nota")
        case "wallet":        return String(localized: "questo biglietto")
        case "loyalty_card":  return String(localized: "questa carta")
        case "passwords":     return String(localized: "questa password")
        case "health":        return String(localized: "questo dato di salute")
        case "pets":          return String(localized: "questo animale")
        case "home_vehicles": return String(localized: "questo veicolo")
        case "travel":        return String(localized: "questo viaggio")
        case "location":      return String(localized: "questo luogo")
        default:              return String(localized: "questo contenuto")
        }
    }
}

/// Valore da presentare con `.sheet(item:)`: il tipo di contenuto basta a
/// identificare l'occasione, che è comunque una sola.
struct FirstContentInvite: Identifiable {
    let contentType: String
    var id: String { contentType }
}
