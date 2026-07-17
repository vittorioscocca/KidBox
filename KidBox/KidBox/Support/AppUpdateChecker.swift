//
//  AppUpdateChecker.swift
//  KidBox
//

import Foundation
import Combine
import UIKit

/// Verifica se sull'App Store c'è una versione di KidBox più recente di quella
/// installata, e in tal caso propone l'aggiornamento (alert presentato da RootHostView).
///
/// iOS non offre alcuna API per interrogare l'App Store (non esiste un equivalente di
/// Play In-App Updates su Android): si usa l'endpoint pubblico `itunes.apple.com/lookup`,
/// che restituisce la versione attualmente pubblicata a partire dal bundle id.
///
/// L'endpoint lookup ignora il **rilascio graduale** (phased release): annuncerebbe la
/// nuova versione a tutti immediatamente, anche a chi non la può ancora scaricare. Vedi
/// ``minDaysOnStore`` per come è tarata l'attesa rispetto al modo in cui pubblichiamo.
@MainActor
final class AppUpdateChecker: ObservableObject {

    static let shared = AppUpdateChecker()

    struct Update: Identifiable {
        let id = UUID()
        let storeVersion: String
        let storeURL: URL
    }

    @Published var availableUpdate: Update?

    private let defaults = UserDefaults.standard
    private var lastCheckAt: Date?

    /// Giorni di permanenza sullo Store prima di proporre l'aggiornamento.
    ///
    /// KidBox pubblica senza rilascio graduale, quindi la versione è scaricabile da
    /// tutti da subito e non serve attendere la fine di un rollout: basta 1 giorno di
    /// margine per il ritardo della CDN dietro cui sta l'endpoint lookup.
    /// Se un domani si attivasse il phased release su App Store Connect, questo valore
    /// va riportato a 7, altrimenti si propone l'aggiornamento a utenti che non lo
    /// possono ancora scaricare.
    private static let minDaysOnStore: TimeInterval = 1
    /// Dopo un "Non ora" non riproponiamo la stessa versione per questi giorni.
    private static let snoozeDays: TimeInterval = 3
    /// Non interroghiamo l'endpoint più di una volta ogni 6 ore.
    private static let checkThrottle: TimeInterval = 6 * 60 * 60

    private static let dayInSeconds: TimeInterval = 24 * 60 * 60

    private init() {}

    // MARK: - Check

    func checkForUpdate() async {
        if let lastCheckAt, Date().timeIntervalSince(lastCheckAt) < Self.checkThrottle {
            KBLog.app.kbDebug("[AppUpdate] check saltato (throttle)")
            return
        }
        lastCheckAt = Date()

        guard let current = Self.currentVersion else { return }
        guard let store = await fetchStoreInfo() else { return }

        // "2.0.10" > "2.0.9": confronto numerico, non lessicografico.
        guard store.version.compare(current, options: .numeric) == .orderedDescending else {
            KBLog.app.kbDebug("[AppUpdate] nessun aggiornamento (installata \(current), store \(store.version))")
            return
        }

        let daysOnStore = Date().timeIntervalSince(store.releaseDate) / Self.dayInSeconds
        guard daysOnStore >= Self.minDaysOnStore else {
            KBLog.app.kbInfo("[AppUpdate] versione \(store.version) sullo Store da \(String(format: "%.1f", daysOnStore))g: attendo fine phased release")
            return
        }

        guard !isSnoozed(version: store.version) else {
            KBLog.app.kbDebug("[AppUpdate] versione \(store.version) rinviata dall'utente")
            return
        }

        KBLog.app.kbInfo("[AppUpdate] propongo aggiornamento \(current) -> \(store.version)")
        availableUpdate = Update(storeVersion: store.version, storeURL: store.url)
    }

#if DEBUG
    /// Controllo forzato per i test manuali dal footer di Impostazioni.
    ///
    /// Scavalca i tre cancelli di policy (throttle, attesa sullo Store, snooze) e tiene
    /// solo il confronto fra versioni: se li rispettasse, con una versione appena
    /// pubblicata non mostrerebbe nulla e sembrerebbe rotto. Restituisce un resoconto
    /// leggibile, così un "non è successo niente" resta diagnosticabile.
    func runDebugCheck() async -> String {
        guard let current = Self.currentVersion else {
            return "Impossibile leggere la versione installata."
        }
        guard let store = await fetchStoreInfo() else {
            let region = Locale.current.region?.identifier ?? "?"
            return "Lookup fallito: offline, oppure app non presente nello storefront \(region)."
        }

        let days = Date().timeIntervalSince(store.releaseDate) / Self.dayInSeconds
        var report = "Installata \(current) · Store \(store.version) · online da \(String(format: "%.1f", days))g\n"

        guard store.version.compare(current, options: .numeric) == .orderedDescending else {
            return report + "→ nessun alert: la versione sullo Store non è superiore."
        }

        availableUpdate = Update(storeVersion: store.version, storeURL: store.url)
        report += "→ alert mostrato (cancelli di policy ignorati nel test)."
        if days < Self.minDaysOnStore {
            report += "\n⚠︎ In produzione sarebbe stato taciuto: online da meno di \(Int(Self.minDaysOnStore))g."
        }
        if isSnoozed(version: store.version) {
            report += "\n⚠︎ In produzione sarebbe stato taciuto: rinviato con \"Non ora\"."
        }
        return report
    }
#endif

    // MARK: - Azioni alert

    func openAppStore(_ update: Update) {
        UIApplication.shared.open(update.storeURL)
        availableUpdate = nil
    }

    /// "Non ora": rinvia la stessa versione per ``snoozeDays`` giorni.
    func snooze(_ update: Update) {
        defaults.set(update.storeVersion, forKey: Keys.snoozedVersion)
        defaults.set(Date(), forKey: Keys.snoozedAt)
        availableUpdate = nil
    }

    private func isSnoozed(version: String) -> Bool {
        guard defaults.string(forKey: Keys.snoozedVersion) == version,
              let snoozedAt = defaults.object(forKey: Keys.snoozedAt) as? Date
        else { return false }
        let elapsed = Date().timeIntervalSince(snoozedAt)
        return elapsed >= 0 && elapsed < Self.snoozeDays * Self.dayInSeconds
    }

    // MARK: - Lookup App Store

    private struct StoreInfo {
        let version: String
        let url: URL
        let releaseDate: Date
    }

    private func fetchStoreInfo() async -> StoreInfo? {
        guard let bundleId = Bundle.main.bundleIdentifier,
              var components = URLComponents(string: "https://itunes.apple.com/lookup")
        else { return nil }

        var items = [URLQueryItem(name: "bundleId", value: bundleId)]
        // Lo storefront cambia la scheda restituita; senza `country` Apple assume US.
        // Se l'app non è pubblicata nello store dell'utente, resultCount = 0 e non
        // proponiamo nulla: fallimento silenzioso, che è il comportamento voluto.
        if let region = Locale.current.region?.identifier {
            items.append(URLQueryItem(name: "country", value: region))
        }
        // L'endpoint è dietro CDN: il timestamp evita risposte troppo stantie.
        items.append(URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970))))
        components.queryItems = items

        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let result = decoded.results.first else {
                KBLog.app.kbDebug("[AppUpdate] lookup senza risultati per \(bundleId)")
                return nil
            }
            guard let storeURL = URL(string: result.trackViewUrl),
                  let releaseDate = ISO8601DateFormatter().date(from: result.currentVersionReleaseDate)
            else { return nil }
            return StoreInfo(version: result.version, url: storeURL, releaseDate: releaseDate)
        } catch {
            // Offline o endpoint non raggiungibile: nessun alert, si riproverà.
            KBLog.app.kbDebug("[AppUpdate] lookup fallito: \(error.localizedDescription)")
            return nil
        }
    }

    private struct LookupResponse: Decodable {
        let results: [Result]

        struct Result: Decodable {
            let version: String
            let trackViewUrl: String
            let currentVersionReleaseDate: String
        }
    }

    private static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private enum Keys {
        static let snoozedVersion = "appUpdate.snoozedVersion"
        static let snoozedAt = "appUpdate.snoozedAt"
    }
}
