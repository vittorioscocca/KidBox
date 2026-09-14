//
//  ReviewPrompter.swift
//  KidBox
//

import Foundation
import StoreKit
import UIKit

/// Decide quando chiedere una recensione con il popup di sistema.
///
/// Si usa solo `AppStore.requestReview`: Apple vieta i popup di recensione
/// fatti in casa (linea guida 5.6.1) e non esiste un'API per inviare un voto
/// raccolto dall'app. Vietato anche chiedere prima "ti piace?" e chiamare il
/// popup solo per chi dice sì.
///
/// L'ultima parola ce l'ha il sistema (al massimo 3 volte in 365 giorni) e non
/// dice se il popup è comparso né se l'utente ha votato: per questo l'evento
/// analytics si chiama "requested", non "shown". In TestFlight non compare mai.
///
/// Stato solo sul dispositivo: nessuna lettura Firestore. Le stesse regole
/// vivono in `ReviewPrompter.kt` su Android.
enum ReviewPrompter {

    enum Moment: String {
        /// Piano Fitness o Alimentare generato con successo.
        case aiPlanGenerated = "ai_plan"
        /// Un contenuto creato; conta solo dalla soglia `minContentCreated`.
        case contentCreated = "content_created"
        /// Un contenuto di un altro membro aperto: la famiglia sta usando l'app insieme.
        case sharedContentRead = "shared_read"
    }

    private static let minDaysSinceFirstOpen = 7
    private static let minOpenDays = 5
    private static let minDaysBetweenRequests = 120
    private static let minContentCreated = 10
    private static let minSharedReads = 5
    private static let presentationDelay: Duration = .seconds(1.5)

    private static let firstOpenKey = "kb_review_firstOpenDate"
    private static let openDaysKey = "kb_review_openDays"
    private static let lastOpenDayKey = "kb_review_lastOpenDay"
    private static let contentCreatedKey = "kb_review_contentCreated"
    private static let sharedReadsKey = "kb_review_sharedReads"
    private static let lastRequestDateKey = "kb_review_lastRequestDate"
    private static let lastRequestVersionKey = "kb_review_lastRequestVersion"
    /// Scritta da `AppAnalytics.trackAppOpen`: chi aggiorna l'app non riparte da zero giorni.
    private static let analyticsInstallDateKey = "kb_appAnalytics_installDate"

    private static var defaults: UserDefaults { .standard }
    private static var pending = false

    /// Da chiamare a ogni ritorno in primo piano: conta i giorni distinti di utilizzo.
    static func registerAppOpen() {
        let now = Date()
        if defaults.object(forKey: firstOpenKey) == nil {
            let seed = defaults.object(forKey: analyticsInstallDateKey) as? Date ?? now
            defaults.set(seed, forKey: firstOpenKey)
        }
        let today = Calendar.current.startOfDay(for: now)
        if (defaults.object(forKey: lastOpenDayKey) as? Date) != today {
            defaults.set(today, forKey: lastOpenDayKey)
            defaults.set(defaults.integer(forKey: openDaysKey) + 1, forKey: openDaysKey)
        }
    }

    /// Da chiamare subito dopo un'azione andata a buon fine.
    static func note(_ moment: Moment) {
        switch moment {
        case .aiPlanGenerated:
            break
        case .contentCreated:
            let count = defaults.integer(forKey: contentCreatedKey) + 1
            defaults.set(count, forKey: contentCreatedKey)
            guard count >= minContentCreated else { return }
        case .sharedContentRead:
            let count = defaults.integer(forKey: sharedReadsKey) + 1
            defaults.set(count, forKey: sharedReadsKey)
            guard count >= minSharedReads else { return }
        }
        guard isEligible(), !pending else { return }

        pending = true
        Task { @MainActor in
            defer { pending = false }
            // A schermata ferma: lascia chiudere lo sheet del salvataggio.
            try? await Task.sleep(for: presentationDelay)
            guard isEligible(), let scene = idleForegroundScene() else { return }
            defaults.set(Date(), forKey: lastRequestDateKey)
            defaults.set(appVersion, forKey: lastRequestVersionKey)
            AppStore.requestReview(in: scene)
            AppAnalytics.reviewPromptRequested(trigger: moment.rawValue)
        }
    }

    private static func isEligible() -> Bool {
        let now = Date()
        guard let firstOpen = defaults.object(forKey: firstOpenKey) as? Date,
              days(from: firstOpen, to: now) >= minDaysSinceFirstOpen,
              defaults.integer(forKey: openDaysKey) >= minOpenDays
        else { return false }

        if let lastRequest = defaults.object(forKey: lastRequestDateKey) as? Date,
           days(from: lastRequest, to: now) < minDaysBetweenRequests {
            return false
        }
        return defaults.string(forKey: lastRequestVersionKey) != appVersion
    }

    /// La scena attiva, ma solo se non c'è niente di presentato sopra
    /// (paywall, permessi, un form ancora aperto): lì il popup interromperebbe.
    private static func idleForegroundScene() -> UIWindowScene? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController,
              root.presentedViewController == nil
        else { return nil }
        return scene
    }

    private static func days(from: Date, to: Date) -> Int {
        Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    // MARK: - Voce "Valuta KidBox" nelle Impostazioni

    /// Apre direttamente la scrittura della recensione sull'App Store.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6761055375?action=write-review")!
}
