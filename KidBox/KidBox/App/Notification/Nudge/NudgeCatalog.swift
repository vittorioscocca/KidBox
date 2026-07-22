//
//  NudgeCatalog.swift
//  KidBox
//
//  Catalogo delle campagne di nudge: cosa suggerire, a chi, con che cadenza.
//
//  Il catalogo di DEFAULT vive qui, nel codice. Il documento Firestore
//  `config/nudges` è solo un OVERRIDE. Questa è la scelta che rende il motore
//  robusto: se il documento non esiste, non è leggibile o è malformato, l'app
//  continua a funzionare con il catalogo compilato invece di non mandare più
//  nulla. Non c'è nessun seed da fare per partire.
//
//  Cosa si può cambiare da remoto senza una release: testi, cadenze, ordine,
//  numero massimo di invii, e il kill switch globale. Cosa NO: le condizioni
//  disponibili (`NudgeRequirements`) e le destinazioni (`NudgeDestination`),
//  che sono insiemi chiusi perché il client deve saperle valutare e aprire.
//  Un `destination` sconosciuto arrivato da remoto viene ignorato, non
//  indovinato.
//

import Foundation

/// Aree di prodotto su cui si può misurare "non l'ha mai usata".
enum NudgeFeature: String, Codable {
    case documents, wallet, health, ai, chat, calendar
}

/// Dove porta il pulsante primario della notifica.
enum NudgeDestination: String, Codable {
    case invite, documents, wallet, health, ai, chat, calendar
}

/// Condizioni valutate SOLO sul dispositivo, sui dati che l'app ha già in
/// locale. Nessuna query di rete, nessun profilo per-utente lato server.
struct NudgeRequirements: Codable, Equatable {
    /// Scatta solo se la famiglia ha al massimo questi membri.
    var familyMembersMax: Int?
    /// Scatta solo se la famiglia ha almeno questi membri.
    var familyMembersMin: Int?
    /// Scatta solo se di questa feature non esiste ancora nulla in locale.
    var featureUnused: NudgeFeature?

    init(
        familyMembersMax: Int? = nil,
        familyMembersMin: Int? = nil,
        featureUnused: NudgeFeature? = nil
    ) {
        self.familyMembersMax = familyMembersMax
        self.familyMembersMin = familyMembersMin
        self.featureUnused = featureUnused
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        familyMembersMax = try c.decodeIfPresent(Int.self, forKey: .familyMembersMax)
        familyMembersMin = try c.decodeIfPresent(Int.self, forKey: .familyMembersMin)
        featureUnused = try? c.decodeIfPresent(NudgeFeature.self, forKey: .featureUnused)
    }
}

struct NudgeCampaign: Codable, Equatable, Identifiable {
    let id: String
    var enabled: Bool
    /// Ordine di somministrazione. Le campagne non partono in parallelo: una
    /// alla volta, in quest'ordine, distanziate da `globalCooldownDays`.
    var order: Int
    /// Giorni dall'installazione prima del primo invio possibile.
    var firstDelayDays: Int
    /// Distanza fra le ripetizioni della STESSA campagna.
    var repeatEveryDays: Int
    /// Quante volte al massimo questa campagna può scattare, per sempre.
    var maxFires: Int
    var requires: NudgeRequirements
    /// Testo italiano, che è ANCHE la chiave dello String Catalog: è la
    /// convenzione di tutto il progetto (`sourceLanguage: it`, la chiave è la
    /// stringa sorgente). Passando da `NSLocalizedString` il testo esce nella
    /// lingua scelta in-app, perché `LanguageManager` sostituisce il bundle da
    /// cui quella funzione legge.
    var title: String
    var body: String
    /// Testo imposto da remoto. Se presente vince sulla traduzione: è una
    /// scelta esplicita di chi scrive dalla console, e va rispettata anche se
    /// resta in una lingua sola.
    var titleOverride: String?
    var bodyOverride: String?
    var destination: NudgeDestination?

    /// L'override remoto vince; altrimenti si traduce il testo italiano.
    ///
    /// Se la chiave non è nel catalogo, `NSLocalizedString` restituisce la
    /// chiave stessa — che qui è il testo italiano, quindi il degrado è una
    /// frase in italiano, non un identificatore mostrato all'utente. È il
    /// motivo principale per cui questa convenzione è preferibile alle chiavi
    /// simboliche.
    var resolvedTitle: String {
        if let titleOverride, !titleOverride.isEmpty { return titleOverride }
        return NSLocalizedString(title, comment: "Nudge title")
    }

    var resolvedBody: String {
        if let bodyOverride, !bodyOverride.isEmpty { return bodyOverride }
        return NSLocalizedString(body, comment: "Nudge body")
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 99
        firstDelayDays = try c.decodeIfPresent(Int.self, forKey: .firstDelayDays) ?? 7
        repeatEveryDays = try c.decodeIfPresent(Int.self, forKey: .repeatEveryDays) ?? 7
        maxFires = try c.decodeIfPresent(Int.self, forKey: .maxFires) ?? 1
        requires = try c.decodeIfPresent(NudgeRequirements.self, forKey: .requires) ?? NudgeRequirements()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        titleOverride = try c.decodeIfPresent(String.self, forKey: .titleOverride)
        bodyOverride = try c.decodeIfPresent(String.self, forKey: .bodyOverride)
        // Destinazione sconosciuta → nessuna azione, non un crash e non un
        // salto in un posto a caso: la notifica resta informativa.
        destination = try? c.decodeIfPresent(NudgeDestination.self, forKey: .destination)
    }

    init(
        id: String,
        order: Int,
        firstDelayDays: Int,
        repeatEveryDays: Int = 7,
        maxFires: Int = 1,
        requires: NudgeRequirements,
        title: String,
        body: String,
        destination: NudgeDestination?
    ) {
        self.id = id
        self.enabled = true
        self.order = order
        self.firstDelayDays = firstDelayDays
        self.repeatEveryDays = repeatEveryDays
        self.maxFires = maxFires
        self.requires = requires
        self.title = title
        self.body = body
        self.titleOverride = nil
        self.bodyOverride = nil
        self.destination = destination
    }
}

struct NudgeConfig: Codable, Equatable {
    /// Kill switch globale: si spegne tutto da console, senza release.
    var enabled: Bool
    /// Distanza minima fra due nudge qualsiasi. È il freno principale contro
    /// il fastidio: le singole campagne non possono aggirarlo.
    var globalCooldownDays: Int
    /// Tetto assoluto di nudge in 90 giorni, comunque vada l'aritmetica sopra.
    var maxPerQuarter: Int
    /// Ore in cui non si notifica (locali). `start` incluso, `end` escluso.
    var quietHoursStart: Int
    var quietHoursEnd: Int
    var campaigns: [NudgeCampaign]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = NudgeConfig.builtIn
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? fallback.enabled
        globalCooldownDays = try c.decodeIfPresent(Int.self, forKey: .globalCooldownDays) ?? fallback.globalCooldownDays
        maxPerQuarter = try c.decodeIfPresent(Int.self, forKey: .maxPerQuarter) ?? fallback.maxPerQuarter
        quietHoursStart = try c.decodeIfPresent(Int.self, forKey: .quietHoursStart) ?? fallback.quietHoursStart
        quietHoursEnd = try c.decodeIfPresent(Int.self, forKey: .quietHoursEnd) ?? fallback.quietHoursEnd
        let remote = try c.decodeIfPresent([NudgeCampaign].self, forKey: .campaigns)
        campaigns = (remote?.isEmpty == false) ? remote! : fallback.campaigns
    }

    init(
        enabled: Bool,
        globalCooldownDays: Int,
        maxPerQuarter: Int,
        quietHoursStart: Int,
        quietHoursEnd: Int,
        campaigns: [NudgeCampaign]
    ) {
        self.enabled = enabled
        self.globalCooldownDays = globalCooldownDays
        self.maxPerQuarter = maxPerQuarter
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.campaigns = campaigns
    }

    // MARK: - Catalogo di default

    /// La sequenza decisa a prodotto:
    ///
    /// 1. **Invito in famiglia** — la priorità. Da solo, KidBox è un archivio
    ///    personale: il valore esiste solo quando c'è più di una persona. Parte
    ///    il giorno dopo l'installazione e insiste per due settimane, poi
    ///    smette. Se nel frattempo la famiglia cresce, `familyMembersMax`
    ///    smette di essere vera e la campagna si spegne da sola.
    ///
    /// 2..7. **Le feature**, una a settimana, ognuna una volta sola e solo se
    ///    quella feature non è mai stata usata. Tutte richiedono
    ///    `familyMembersMin: 2`: non ha senso spiegare la condivisione a chi
    ///    non ha ancora nessuno con cui condividere.
    static let builtIn = NudgeConfig(
        enabled: true,
        globalCooldownDays: 7,
        maxPerQuarter: 10,
        quietHoursStart: 21,
        quietHoursEnd: 9,
        campaigns: [
            NudgeCampaign(
                id: "family_invite",
                order: 0,
                firstDelayDays: 1,
                repeatEveryDays: 7,
                maxFires: 3,
                requires: NudgeRequirements(familyMembersMax: 1),
                title: "KidBox funziona in famiglia",
                body: "Invita l'altro genitore o gli altri membri: documenti, "
                    + "wallet, salute, spese e calendario diventano condivisi e "
                    + "aggiornati per tutti, in tempo reale.",
                destination: .invite
            ),
            NudgeCampaign(
                id: "documents_share",
                order: 1,
                firstDelayDays: 7,
                requires: NudgeRequirements(familyMembersMin: 2, featureUnused: .documents),
                title: "I documenti, sempre con te",
                body: "Carica un documento una volta sola: tutta la famiglia "
                    + "lo vede subito, senza doverlo chiedere a nessuno.",
                destination: .documents
            ),
            NudgeCampaign(
                id: "wallet_expiry",
                order: 2,
                firstDelayDays: 7,
                requires: NudgeRequirements(familyMembersMin: 2, featureUnused: .wallet),
                title: "Carte d'identità e biglietti nel Wallet",
                body: "Conserva documenti d'identità e di viaggio, e ricevi un "
                    + "promemoria una settimana prima che scadano.",
                destination: .wallet
            ),
            NudgeCampaign(
                id: "health_records",
                order: 3,
                firstDelayDays: 7,
                requires: NudgeRequirements(familyMembersMin: 2, featureUnused: .health),
                title: "La salute dei tuoi figli, in un posto solo",
                body: "Visite, accertamenti, cure e cartella clinica: lo storico "
                    + "completo, condiviso con chi se ne occupa insieme a te.",
                destination: .health
            ),
            NudgeCampaign(
                id: "ai_assistant",
                order: 4,
                firstDelayDays: 7,
                requires: NudgeRequirements(familyMembersMin: 2, featureUnused: .ai),
                title: "Chiedi, invece di cercare",
                body: "L'assistente conosce quello che hai in KidBox: fai una "
                    + "domanda, e può anche creare promemoria ed eventi per te.",
                destination: .ai
            ),
            NudgeCampaign(
                id: "chat_family",
                order: 5,
                firstDelayDays: 7,
                requires: NudgeRequirements(familyMembersMin: 2, featureUnused: .chat),
                title: "La chat di famiglia",
                body: "Un posto solo per parlarne, con accanto i documenti e le "
                    + "foto di cui state parlando.",
                destination: .chat
            ),
            NudgeCampaign(
                id: "calendar_shared",
                order: 6,
                firstDelayDays: 7,
                requires: NudgeRequirements(familyMembersMin: 2, featureUnused: .calendar),
                title: "Un calendario che vedete in due",
                body: "Visite, sport, compleanni: chi c'è, quando, e chi ci pensa. "
                    + "Senza rincorrersi a messaggi.",
                destination: .calendar
            ),
        ]
    )
}
