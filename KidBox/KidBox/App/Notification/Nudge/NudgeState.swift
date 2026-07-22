//
//  NudgeState.swift
//  KidBox
//
//  Memoria locale del motore di nudge: cosa è già scattato e quando.
//
//  Sta in `UserDefaults` e NON su Firestore, di proposito. Sono dati di
//  frequenza, non di contenuto: metterli sul server significherebbe costruire
//  per ogni utente un registro di "cosa gli abbiamo detto e quando", cioè il
//  profilo per-utente che l'impianto analytics evita apposta. Il prezzo è che
//  cambiando dispositivo la sequenza riparte: accettabile, ed è comunque
//  frenata da `globalCooldownDays` e `maxPerQuarter`.
//

import Foundation

/// Un invio già avvenuto (o pianificato e poi consegnato).
struct NudgeFire: Codable, Equatable {
    let campaignId: String
    let at: Date
}

@MainActor
enum NudgeState {

    private static let defaults = UserDefaults.standard

    private enum Key {
        static let installDate = "kb.nudge.installDate"
        static let fires = "kb.nudge.fires"
        static let optedOut = "kb.nudge.optedOut"
    }

    // MARK: - Installazione

    /// Prima data conosciuta di questa installazione. Serve a `firstDelayDays`.
    ///
    /// Si registra alla prima chiamata: per gli utenti già installati al momento
    /// dell'aggiornamento vale la data dell'update, non quella vera. È corretto
    /// così — un utente di sei mesi non deve ricevere "benvenuto, invita la
    /// famiglia" il giorno dopo l'aggiornamento come se si fosse appena iscritto.
    static var installDate: Date {
        if let d = defaults.object(forKey: Key.installDate) as? Date { return d }
        let now = Date()
        defaults.set(now, forKey: Key.installDate)
        return now
    }

    static var daysSinceInstall: Int {
        Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
    }

    // MARK: - Opt-out

    /// Interruttore utente, indipendente dal permesso di sistema. Chi lo spegne
    /// non riceve più nudge ma continua a ricevere le notifiche che ha chiesto
    /// (promemoria, chat): sono cose diverse e vanno separate.
    static var isOptedOut: Bool {
        get { defaults.bool(forKey: Key.optedOut) }
        set { defaults.set(newValue, forKey: Key.optedOut) }
    }

    // MARK: - Storico invii

    static var fires: [NudgeFire] {
        get {
            guard let data = defaults.data(forKey: Key.fires),
                  let decoded = try? JSONDecoder().decode([NudgeFire].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            // Oltre un anno non serve a nessuna decisione: il tetto più lungo
            // è trimestrale.
            let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? .distantPast
            let pruned = newValue.filter { $0.at > cutoff }
            defaults.set(try? JSONEncoder().encode(pruned), forKey: Key.fires)
        }
    }

    static func recordFire(campaignId: String, at date: Date = Date()) {
        fires = fires + [NudgeFire(campaignId: campaignId, at: date)]
    }

    static func fireCount(campaignId: String) -> Int {
        fires.filter { $0.campaignId == campaignId }.count
    }

    static func lastFire(campaignId: String) -> Date? {
        fires.filter { $0.campaignId == campaignId }.map(\.at).max()
    }

    static var lastFireAny: Date? {
        fires.map(\.at).max()
    }

    static func firesInLast(days: Int) -> Int {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return 0 }
        return fires.filter { $0.at > cutoff }.count
    }

#if DEBUG
    /// Solo per i test manuali: azzera lo storico e riporta l'installazione a
    /// `daysAgo` giorni fa, così la sequenza riparte senza reinstallare l'app.
    static func resetForTesting(installedDaysAgo: Int = 30) {
        defaults.removeObject(forKey: Key.fires)
        let d = Calendar.current.date(byAdding: .day, value: -installedDaysAgo, to: Date()) ?? Date()
        defaults.set(d, forKey: Key.installDate)
    }
#endif
}
