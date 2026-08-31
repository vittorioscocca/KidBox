//
//  KBNotificationLocalization.swift
//  KidBox
//
//  Testi delle notifiche locali che sopravvivono a un cambio di lingua.
//

import Foundation
import UserNotifications

/// Localizzazione dei testi delle notifiche locali, con ri-traduzione di quelle
/// già in coda.
///
/// Una notifica locale già programmata la mostra il **sistema**, senza eseguire
/// codice dell'app: `willPresent` scatta solo in foreground e la Notification
/// Service Extension vale solo per le push remote. Il testo quindi si congela nel
/// momento in cui la si programma — chi cambia lingua a marzo si ritroverebbe il
/// promemoria di giugno ancora in italiano.
///
/// La soluzione è tenere il testo *ricostruibile*: il contenuto viene risolto
/// subito, ma chiave e argomenti restano dentro `userInfo`. Al cambio lingua
/// `relocalizePending()` rilegge la coda e riscrive i testi, senza che i servizi
/// debbano ricalcolare date, destinatari e trigger dai dati di partenza.
///
/// Le notifiche prive di queste chiavi restano intatte: è il caso dei testi
/// generati dall'AI (briefing, sintesi settimanale), che non sono traducibili
/// perché nascono già scritti in una lingua.
enum KBNotificationLocalization {

    // Chiavi dentro `userInfo`. Il prefisso `kb.loc.` le tiene distinte dai dati
    // che i router di deep link si aspettano di trovare lì (`type`, `familyId`…).
    private static let titleKeyField = "kb.loc.titleKey"
    private static let titleArgsField = "kb.loc.titleArgs"
    private static let bodyKeyField = "kb.loc.bodyKey"
    private static let bodyArgsField = "kb.loc.bodyArgs"

    /// Lingua con cui la coda è stata scritta l'ultima volta.
    private static let lastLanguageKey = "kb.notif.lastLanguage"

    /// Un argomento di un testo: dato grezzo oppure a sua volta da tradurre.
    ///
    /// Serve perché diversi titoli sono composti da più pezzi tradotti — "Treno
    /// tra 2 ore" è il tipo di biglietto più il quando. Passando il pezzo già
    /// tradotto resterebbe nella lingua vecchia mentre la cornice cambia, con un
    /// risultato mezzo tradotto peggiore del non tradurre affatto.
    ///
    /// Conforme a `ExpressibleByStringLiteral`: una stringa nuda è un `.text`,
    /// così i casi semplici restano `["Mario"]`.
    enum Arg: ExpressibleByStringLiteral {
        /// Contenuto dell'utente o dato già formattato: passa così com'è.
        case text(String)
        /// Chiave del catalogo, tradotta ogni volta che il testo viene ricostruito.
        case localized(String, args: [String] = [])

        public init(stringLiteral value: String) { self = .text(value) }

        var resolved: String {
            switch self {
            case .text(let value):
                return value
            case .localized(let key, let args):
                return KBNotificationLocalization.text(key, args.map { Arg.text($0) })
            }
        }

        /// Forma serializzabile in `userInfo` (che accetta solo property list).
        var encoded: [String: Any] {
            switch self {
            case .text(let value):
                return ["t": value]
            case .localized(let key, let args):
                return ["k": key, "a": args]
            }
        }

        static func decode(_ raw: Any) -> Arg? {
            guard let dict = raw as? [String: Any] else { return nil }
            if let value = dict["t"] as? String { return .text(value) }
            if let key = dict["k"] as? String {
                return .localized(key, args: dict["a"] as? [String] ?? [])
            }
            return nil
        }
    }

    /// Traduce una chiave del catalogo, con i `%@` sostituiti dagli argomenti.
    ///
    /// Passa da `Bundle.main`, quindi rispetta la lingua scelta in app: è lo
    /// stesso bundle che `LanguageManager` sostituisce a runtime.
    static func text(_ key: String, _ args: [Arg] = []) -> String {
        let template = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        guard !args.isEmpty else { return template }
        return String(format: template, arguments: args.map(\.resolved))
    }

    /// Imposta titolo e corpo tradotti, lasciando in `userInfo` di che rifarli.
    ///
    /// `bodyKey` è opzionale: alcune notifiche hanno un corpo che è contenuto
    /// dell'utente (il titolo di un biglietto, una nota) o testo generato, e
    /// quello non va tradotto né riscritto.
    static func setText(
        on content: UNMutableNotificationContent,
        titleKey: String,
        titleArgs: [Arg] = [],
        bodyKey: String? = nil,
        bodyArgs: [Arg] = []
    ) {
        content.title = text(titleKey, titleArgs)
        if let bodyKey {
            content.body = text(bodyKey, bodyArgs)
        }

        var info = content.userInfo
        info[titleKeyField] = titleKey
        info[titleArgsField] = titleArgs.map(\.encoded)
        if let bodyKey {
            info[bodyKeyField] = bodyKey
            info[bodyArgsField] = bodyArgs.map(\.encoded)
        }
        content.userInfo = info
    }

    /// Rilegge da `userInfo` gli argomenti serializzati da `setText`.
    private static func decodeArgs(_ raw: Any?) -> [Arg] {
        (raw as? [Any])?.compactMap(Arg.decode) ?? []
    }

    /// Riscrive la coda se la lingua è cambiata dall'ultimo avvio.
    ///
    /// Il selettore in-app chiama direttamente `relocalizePending()`, ma non è
    /// l'unico modo di cambiare lingua: chi la cambia dalle Impostazioni di
    /// sistema non passa di lì, e i nudge programmati al primo login scattano
    /// settimane dopo. Questo controllo all'avvio copre quel caso.
    static func relocalizePendingIfLanguageChanged() async {
        let current = LanguageManager.shared.currentLanguageCode
        let previous = UserDefaults.standard.string(forKey: lastLanguageKey)
        guard previous != current else { return }
        // Primo avvio dopo l'aggiornamento: si registra la lingua e basta. Le
        // notifiche messe in coda dalle versioni precedenti non hanno le chiavi
        // in `userInfo`, quindi non ci sarebbe comunque nulla da riscrivere.
        guard previous != nil else {
            UserDefaults.standard.set(current, forKey: lastLanguageKey)
            return
        }
        KBLog.sync.kbInfo("[NotifLoc] lingua cambiata \(previous ?? "?") → \(current)")
        await relocalizePending()
    }

    /// Riscrive nella lingua corrente tutte le notifiche in coda che portano con
    /// sé le proprie chiavi.
    ///
    /// Identifier e trigger restano quelli di prima, quindi la riprogrammazione
    /// non sposta di un minuto l'orario di consegna: `add` su un identifier già
    /// presente sostituisce la richiesta esistente.
    static func relocalizePending() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()

        var rewritten = 0
        for request in pending {
            let info = request.content.userInfo
            guard let titleKey = info[titleKeyField] as? String else { continue }

            guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else { continue }
            content.title = text(titleKey, decodeArgs(info[titleArgsField]))
            if let bodyKey = info[bodyKeyField] as? String {
                content.body = text(bodyKey, decodeArgs(info[bodyArgsField]))
            }

            let updated = UNNotificationRequest(
                identifier: request.identifier,
                content: content,
                trigger: request.trigger
            )
            do {
                try await center.add(updated)
                rewritten += 1
            } catch {
                // Una notifica che non si riesce a riscrivere resta quella di
                // prima: lingua vecchia, ma consegnata.
                KBLog.sync.kbError("[NotifLoc] rewrite failed id=\(request.identifier): \(error.localizedDescription)")
            }
        }

        UserDefaults.standard.set(LanguageManager.shared.currentLanguageCode, forKey: lastLanguageKey)
        KBLog.sync.kbInfo("[NotifLoc] relocalized \(rewritten)/\(pending.count) pending notifications")
    }
}
