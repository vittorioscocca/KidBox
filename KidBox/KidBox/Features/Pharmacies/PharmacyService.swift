//
//  PharmacyService.swift
//  KidBox
//
//  Le tre callable delle farmacie di turno. Presidio di servizio di /gating-pro:
//  il Free si ferma prima della rete; il presidio vero resta il server
//  (`gate()` in functions/pharmacies).
//

import Foundation
import FirebaseFunctions

enum PharmacyServiceError: LocalizedError, Equatable {
    case planRequired
    case quota(units: Int?, remaining: Int?)
    case budget
    case attempts
    case disabled
    case invalidURL
    /// Il sito non si apre (indirizzo interno, non risponde, non è una pagina di testo).
    case unreachable
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .planRequired:
            return NSLocalizedString("Le farmacie di turno sono incluse nei piani Pro e Max.", comment: "Pharmacies: plan required")
        case let .quota(units, remaining):
            if let units, let remaining {
                return String(
                    format: NSLocalizedString("Questa ricerca costa circa %1$d messaggi AI e alla famiglia ne restano %2$d.", comment: "Pharmacies: AI quota not enough"),
                    units, remaining
                )
            }
            return NSLocalizedString("La famiglia ha finito i messaggi AI disponibili.", comment: "Pharmacies: AI quota reached")
        case .budget:
            return NSLocalizedString("Le ricerche di oggi sono finite: riprova domani.", comment: "Pharmacies: global daily budget reached")
        case .attempts:
            return NSLocalizedString("Hai già provato diverse volte oggi: riprova domani.", comment: "Pharmacies: too many attempts today")
        case .disabled:
            return NSLocalizedString("Le farmacie di turno sono sospese per qualche ora. Riprova più tardi.", comment: "Pharmacies: feature switched off")
        case .invalidURL:
            return NSLocalizedString("Questo non sembra un indirizzo web.", comment: "Pharmacies: invalid URL")
        case .unreachable:
            return NSLocalizedString("Non riesco ad aprire questo sito.", comment: "Pharmacies: site unreachable")
        case .network(let m), .server(let m):
            return m
        }
    }
}

@MainActor
final class PharmacyService {

    static let shared = PharmacyService()
    private let functions = Functions.functions(region: "europe-west1")
    private init() {}

    // MARK: - Turni

    func fetch(familyId: String, place: NewsPlace) async throws -> PharmacyFeed {
        try await ensurePaidPlan()
        let callable = functions.httpsCallable("getPharmacies")
        callable.timeoutInterval = 70
        return try await call(callable, ["familyId": familyId, "place": place.dictionary])
    }

    // MARK: - Ricerca della fonte (AI, scala i messaggi)

    /// `exists`, `found`, `unreadable` o `not-found`.
    func findSource(familyId: String, place: NewsPlace) async throws -> String {
        try await ensurePaidPlan()
        let callable = functions.httpsCallable("findPharmacySource")
        callable.timeoutInterval = 300
        let reply: [String: Any] = try await callRaw(callable, ["familyId": familyId, "place": place.dictionary])
        return reply["status"] as? String ?? "not-found"
    }

    // MARK: - Sito indicato a mano

    /// `url == nil` toglie la scelta e torna alla fonte automatica.
    /// Risposta: `ok`, `unreadable` (il sito non si sa leggere: resta il link) o `cleared`.
    func setSource(familyId: String, place: NewsPlace, url: String?) async throws -> String {
        try await ensurePaidPlan()
        let callable = functions.httpsCallable("setPharmacySource")
        callable.timeoutInterval = 190
        var payload: [String: Any] = ["familyId": familyId, "place": place.dictionary]
        payload["url"] = url ?? NSNull()
        let reply: [String: Any] = try await callRaw(callable, payload)
        return reply["status"] as? String ?? "unreadable"
    }

    // MARK: - Presidio e lettura

    /// `currentPlan`, non `isAIAccessible`: quest'ultimo è vero anche per un
    /// Free col bonus intatto (la trappola di /gating-pro).
    private func ensurePaidPlan() async throws {
        let manager = KBSubscriptionManager.shared
        if manager.currentPlan == .free {
            await manager.loadPlan()
        }
        if manager.currentPlan == .free { throw PharmacyServiceError.planRequired }
    }

    private func call<T: Decodable>(_ callable: HTTPSCallable, _ payload: [String: Any]) async throws -> T {
        let data: Any = try await callRaw(callable, payload)
        do {
            return try JSONDecoder().decode(T.self, from: try JSONSerialization.data(withJSONObject: data))
        } catch {
            KBLog.app.kbError("Pharmacies decode failed: \(error)")
            throw PharmacyServiceError.server(NSLocalizedString("Risposta inattesa dal server. Riprova fra poco.", comment: "Pharmacies: undecodable response"))
        }
    }

    private func callRaw<T>(_ callable: HTTPSCallable, _ payload: [String: Any]) async throws -> T {
        do {
            let result = try await callable.call(payload)
            guard let value = result.data as? T else {
                throw PharmacyServiceError.server(NSLocalizedString("Risposta inattesa dal server. Riprova fra poco.", comment: "Pharmacies: undecodable response"))
            }
            return value
        } catch let error as PharmacyServiceError {
            throw error
        } catch let error as NSError {
            throw map(error)
        }
    }

    private func map(_ error: NSError) -> Error {
        if error.domain == NSURLErrorDomain {
            return PharmacyServiceError.network(NSLocalizedString("Nessuna connessione. Controlla Wi‑Fi o dati mobili.", comment: "Pharmacies: offline"))
        }
        guard error.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: error.code) else {
            return PharmacyServiceError.network(error.localizedDescription)
        }
        let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
        let reason = details?["reason"] as? String
        switch code {
        case .permissionDenied where reason == "plan":
            return PharmacyServiceError.planRequired
        case .resourceExhausted where reason == "pharmacies-budget":
            return PharmacyServiceError.budget
        case .resourceExhausted where reason == "pharmacies-attempts":
            return PharmacyServiceError.attempts
        case .resourceExhausted:
            return PharmacyServiceError.quota(
                units: (details?["units"] as? NSNumber)?.intValue,
                remaining: (details?["remaining"] as? NSNumber)?.intValue
            )
        case .failedPrecondition where reason == "pharmacies-disabled":
            return PharmacyServiceError.disabled
        case .failedPrecondition:
            return PharmacyServiceError.unreachable
        case .invalidArgument where reason == "invalid-url":
            return PharmacyServiceError.invalidURL
        case .deadlineExceeded, .unavailable:
            return PharmacyServiceError.network(NSLocalizedString("La ricerca sta impiegando più del solito. Riprova fra poco.", comment: "Pharmacies: timeout"))
        default:
            return PharmacyServiceError.server(error.localizedDescription)
        }
    }
}
