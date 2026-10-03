//
//  NewsService.swift
//  KidBox
//
//  Le due callable delle Notizie: `getFamilyNews` (l'edizione del giorno) e
//  `getNewsOffers` (le offerte su misura). È il presidio di servizio di
//  /gating-pro: ogni percorso passa di qui, e il Free si ferma prima della
//  rete. Il presidio vero resta il server (`gate()` in functions/news).
//

import Foundation
import FirebaseFunctions

enum NewsServiceError: LocalizedError, Equatable {
    /// Piano Free: le Notizie sono di Pro e Max.
    case planRequired
    /// La quota AI della famiglia non basta per l'edizione di oggi.
    case quota(units: Int?, remaining: Int?, limit: Int?, reason: String?)
    case disabled
    case budget
    case emptyBrief
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .planRequired:
            return NSLocalizedString("Le Notizie sono incluse nei piani Pro e Max.", comment: "News: plan required")
        case let .quota(units, remaining, _, reason):
            if reason == "trial-limit" {
                return NSLocalizedString("Hai usato tutti i messaggi AI della prova Pro: le notizie tornano con un abbonamento.", comment: "News: trial AI quota exhausted")
            }
            if let units, let remaining {
                return String(
                    format: NSLocalizedString("Le notizie di oggi costano %1$d messaggi AI e alla famiglia ne restano %2$d. Riprova domani.", comment: "News: daily AI quota not enough"),
                    units, remaining
                )
            }
            return NSLocalizedString("La famiglia ha finito i messaggi AI di oggi. Riprova domani.", comment: "News: daily AI quota reached")
        case .disabled:
            return NSLocalizedString("Le notizie sono sospese per qualche ora. Riprova più tardi.", comment: "News: feature switched off")
        case .budget:
            return NSLocalizedString("Le ricerche di oggi sono finite: riprova domani.", comment: "News: global daily budget reached")
        case .emptyBrief:
            return NSLocalizedString("Aggiungi una bolletta in Casa o qualcosa alla lista della spesa: le offerte partono da lì.", comment: "News: offers need bills or grocery")
        case .network(let m), .server(let m):
            return m
        }
    }
}

@MainActor
final class NewsService {

    static let shared = NewsService()

    private let functions = Functions.functions(region: "europe-west1")

    /// L'ultima edizione scaricata, per riaprire la scheda senza attese.
    private(set) var cachedFeed: (familyId: String, dateKey: String, feed: NewsFeed)?

    private init() {}

    // MARK: - Edizione del giorno

    func fetchFeed(familyId: String, prefs: NewsPrefs) async throws -> NewsFeed {
        try await ensurePaidPlan()
        let place = prefs.effectivePlace
        let payload: [String: Any] = [
            "familyId": familyId,
            "lang": LanguageManager.shared.currentLanguageCode,
            "timeZone": TimeZone.current.identifier,
            "categories": prefs.categories.map(\.rawValue),
            "place": place.dictionary,
        ]
        let callable = functions.httpsCallable("getFamilyNews")
        callable.timeoutInterval = 70
        do {
            let result = try await callable.call(payload)
            let feed = try decode(NewsFeed.self, from: result.data)
            cachedFeed = (familyId, feed.dateKey, feed)
            return feed
        } catch let error as NSError {
            throw map(error)
        }
    }

    // MARK: - Offerte su misura

    /// Senza `brief` legge solo le ultime offerte salvate (gratis); con `brief`
    /// cerca offerte nuove e scala i messaggi.
    func fetchOffers(familyId: String, prefs: NewsPrefs, brief: NewsBrief?) async throws -> NewsOffersPayload {
        try await ensurePaidPlan()
        var payload: [String: Any] = [
            "familyId": familyId,
            "lang": LanguageManager.shared.currentLanguageCode,
            "timeZone": TimeZone.current.identifier,
            "place": prefs.effectivePlace.dictionary,
            "refresh": brief != nil,
        ]
        if let brief { payload["brief"] = brief.dictionary }
        let callable = functions.httpsCallable("getNewsOffers")
        callable.timeoutInterval = 190
        do {
            let result = try await callable.call(payload)
            return try decode(NewsOffersPayload.self, from: result.data)
        } catch let error as NSError {
            throw map(error)
        }
    }

    // MARK: - Presidio di piano

    /// `currentPlan`, non `isAIAccessible`: quest'ultimo è vero anche per un
    /// Free col bonus intatto (la trappola di /gating-pro).
    private func ensurePaidPlan() async throws {
        let manager = KBSubscriptionManager.shared
        if manager.currentPlan == .free {
            await manager.loadPlan()
        }
        if manager.currentPlan == .free { throw NewsServiceError.planRequired }
    }

    // MARK: - Lettura

    private func decode<T: Decodable>(_ type: T.Type, from any: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: any)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            KBLog.app.kbError("News decode failed: \(error)")
            throw NewsServiceError.server(NSLocalizedString("Risposta inattesa dal server. Riprova fra poco.", comment: "News: undecodable response"))
        }
    }

    private func map(_ error: NSError) -> Error {
        if let mapped = error as Error as? NewsServiceError { return mapped }
        if error.domain == NSURLErrorDomain {
            return NewsServiceError.network(NSLocalizedString("Nessuna connessione. Controlla Wi‑Fi o dati mobili.", comment: "News: offline"))
        }
        guard error.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: error.code) else {
            return NewsServiceError.network(error.localizedDescription)
        }
        let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
        let reason = details?["reason"] as? String
        switch code {
        case .permissionDenied where reason == "plan":
            return NewsServiceError.planRequired
        case .resourceExhausted where reason == "news-budget":
            return NewsServiceError.budget
        case .resourceExhausted:
            return NewsServiceError.quota(
                units: (details?["units"] as? NSNumber)?.intValue,
                remaining: (details?["remaining"] as? NSNumber)?.intValue,
                limit: (details?["limit"] as? NSNumber)?.intValue,
                reason: reason
            )
        case .failedPrecondition where reason == "news-disabled":
            return NewsServiceError.disabled
        case .invalidArgument where reason == "empty-brief":
            return NewsServiceError.emptyBrief
        case .deadlineExceeded, .unavailable:
            return NewsServiceError.network(NSLocalizedString("La ricerca sta impiegando più del solito. Riprova fra poco.", comment: "News: timeout"))
        default:
            return NewsServiceError.server(error.localizedDescription)
        }
    }

    func clearCache() { cachedFeed = nil }
}
