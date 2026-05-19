//
//  AIService.swift
//  KidBox
//
//  Chiama la Cloud Function `askAI` su Firebase invece di Anthropic direttamente.
//  La API key Anthropic è gestita interamente lato server — mai sul client.
//
//  Il limite AI è per FAMIGLIA (non per utente):
//  Pro = 30 msg/giorno/famiglia, Max = 100 msg/giorno/famiglia.
//  familyId viene letto dall'App Group e passato in ogni chiamata.
//

import Foundation
import FirebaseFunctions
import OSLog

// MARK: - Errors

enum AIServiceError: LocalizedError {
    case notEnabled
    case rateLimitReached(String)
    case networkError(String)
    case serverError(String)
    case invalidResponse
    case missingFamilyId
    
    var errorDescription: String? {
        switch self {
        case .notEnabled:
            return "Assistente AI non attivato. Vai in Impostazioni per abilitarlo."
        case .rateLimitReached(let msg):
            return msg
        case .networkError(let msg):
            return "Errore di rete: \(msg)"
        case .serverError(let msg):
            return msg
        case .invalidResponse:
            return "Risposta non valida dal servizio AI."
        case .missingFamilyId:
            return "Famiglia non trovata. Riprova dopo aver effettuato il login."
        }
    }
}

// MARK: - Response

struct AIResponse {
    let reply: String
    let usageToday: Int
    let dailyLimit: Int
    /// Messaggi scalati sul contatore per questa richiesta (1 = contesto standard).
    let messageUnitsConsumed: Int
    let isLargeContext: Bool
    
    init(
        reply: String,
        usageToday: Int,
        dailyLimit: Int,
        messageUnitsConsumed: Int = 1,
        isLargeContext: Bool = false
    ) {
        self.reply = reply
        self.usageToday = usageToday
        self.dailyLimit = dailyLimit
        self.messageUnitsConsumed = messageUnitsConsumed
        self.isLargeContext = isLargeContext
    }
    
    var usageSummary: String { "\(usageToday)/\(dailyLimit) messaggi oggi" }
    var isNearLimit: Bool { usageToday >= Int(Double(dailyLimit) * 0.8) }
}

// MARK: - Travel plan

struct TravelPlanRequest {
    let wizardData: [String: Any]
    let freeTextPrompt: String
    let familyContext: [String: Any]
    /// Rigenerazione di un solo giorno: la Cloud Function accetta `legs` minimi e 1 dayPlan.
    var regenerateSingleDay: Bool = false
}

struct TravelPlanResponse {
    let travelPlan: [String: Any]?
    let narrativeText: String
    let usageToday: Int
    let dailyLimit: Int
}

struct TravelSuggestionsRequest {
    let travelProfile: [String: Any]
}

// MARK: - Service

/// Sends messages to the KidBox `askAI` Firebase Cloud Function.
///
/// The function handles authentication, rate limiting, and the Anthropic API call.
/// No API key is ever stored or transmitted from the client.
final class AIService {
    
    static let shared = AIService()
    
    private lazy var functions = Functions.functions(region: "europe-west1")

    /// Itinerario viaggio: risposta lenta (fino a ~2 min lato server).
    private static let travelPlanClientTimeout: TimeInterval = 150
    
    private init() {
        KBLog.ai.kbDebug("AIService initialized region=europe-west1")
    }

    private func mapCallableError(_ error: NSError) -> AIServiceError {
        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return .networkError("Nessuna connessione. Controlla Wi‑Fi o dati mobili.")
            case NSURLErrorTimedOut:
                return .serverError("La richiesta ha impiegato troppo tempo. Riprova tra poco.")
            default:
                break
            }
        }

        let message = error.localizedDescription
        guard let code = FunctionsErrorCode(rawValue: error.code) else {
            return .networkError(message)
        }

        switch code {
        case .resourceExhausted:
            return .rateLimitReached(message)
        case .permissionDenied:
            return .rateLimitReached(
                message.isEmpty
                    ? "Piano Pro o Max richiesto per la pianificazione AI."
                    : message
            )
        case .unauthenticated:
            return .serverError("Sessione scaduta. Effettua di nuovo il login.")
        case .notFound, .unimplemented:
            return .serverError(
                "La funzione «generateTravelPlan» non è attiva su Firebase (regione europe-west1). " +
                "Serve il deploy delle Cloud Functions, non un aggiornamento dell'app."
            )
        case .deadlineExceeded:
            return .serverError("La generazione dell'itinerario ha impiegato troppo tempo. Riprova.")
        case .invalidArgument:
            return .serverError("Dati del viaggio non validi. Controlla nome, date e tappe.")
        case .unavailable, .internal:
            return .serverError("Servizio AI temporaneamente non disponibile.")
        default:
            KBLog.ai.kbError("mapCallableError unhandled code=\(code.rawValue) message=\(message)")
            return .networkError(message)
        }
    }

    private func jsonSafeCallablePayload(_ payload: [String: Any]) throws -> [String: Any] {
        guard JSONSerialization.isValidJSONObject(payload) else {
            KBLog.ai.kbError("jsonSafeCallablePayload: invalid JSON object")
            throw AIServiceError.invalidResponse
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let normalized = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }
        return normalized
    }
    
    // MARK: - FamilyId helper
    
    /// Legge il familyId corrente dall'App Group.
    /// Tutte le chiamate AI richiedono familyId per il contatore condiviso.
    private var currentFamilyId: String? {
        let id = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
            .string(forKey: "activeFamilyId") ?? ""
        return id.isEmpty ? nil : id
    }
    
    // MARK: - Send message
    
    /// Sends the conversation to the AI and returns the assistant reply.
    func sendMessage(
        messages: [KBAIMessage],
        systemPrompt: String
    ) async throws -> AIResponse {
        
        guard AISettings.shared.isEnabled else {
            KBLog.ai.kbInfo("sendMessage blocked: AI assistant disabled")
            throw AIServiceError.notEnabled
        }
        
        guard let familyId = currentFamilyId else {
            KBLog.ai.kbError("sendMessage blocked: missing familyId")
            throw AIServiceError.missingFamilyId
        }
        
        KBLog.ai.kbInfo("sendMessage started messagesCount=\(messages.count) familyId=\(familyId)")
        
        let payload: [String: Any] = [
            "messages": messages.map { [
                "role": $0.role.rawValue,
                "content": $0.content
            ] },
            "systemPrompt": systemPrompt,
            "familyId": familyId
        ]
        
        KBLog.ai.kbDebug("Calling Firebase Function askAI payloadMessagesCount=\(messages.count)")
        
        do {
            let result = try await functions.httpsCallable("askAI").call(payload)
            
            guard
                let data = result.data as? [String: Any],
                let reply = data["reply"] as? String,
                let usageToday = data["usageToday"] as? Int,
                let dailyLimit = data["dailyLimit"] as? Int
            else {
                KBLog.ai.kbError("sendMessage invalid response: missing expected fields")
                throw AIServiceError.invalidResponse
            }
            let messageUnitsConsumed = data["messageUnitsConsumed"] as? Int ?? 1
            let isLargeContext = data["isLargeContext"] as? Bool ?? (messageUnitsConsumed > 1)
            
            KBLog.ai.kbInfo(
                "sendMessage succeeded replyLength=\(reply.count) usageToday=\(usageToday) dailyLimit=\(dailyLimit) units=\(messageUnitsConsumed)"
            )
            await AIUsageStore.shared.apply(usageToday: usageToday, dailyLimit: dailyLimit)

            return AIResponse(
                reply: reply,
                usageToday: usageToday,
                dailyLimit: dailyLimit,
                messageUnitsConsumed: messageUnitsConsumed,
                isLargeContext: isLargeContext
            )
            
        } catch let error as NSError {
            let message = error.localizedDescription
            let code = FunctionsErrorCode(rawValue: error.code)
            
            KBLog.ai.kbError("sendMessage failed firebaseCode=\(error.code) description=\(message)")
            
            switch code {
            case .resourceExhausted:
                KBLog.ai.kbInfo("sendMessage mapped to rateLimitReached")
                throw AIServiceError.rateLimitReached(message)
                
            case .unauthenticated:
                KBLog.ai.kbInfo("sendMessage mapped to unauthenticated session error")
                throw AIServiceError.serverError("Sessione scaduta. Effettua di nuovo il login.")
                
            case .unavailable, .internal:
                KBLog.ai.kbInfo("sendMessage mapped to temporary server unavailable")
                throw AIServiceError.serverError("Servizio AI temporaneamente non disponibile.")
                
            default:
                KBLog.ai.kbInfo("sendMessage mapped to networkError")
                throw AIServiceError.networkError(message)
            }
        }
    }
    
    // MARK: - Fetch usage
    
    /// Fetches today's usage counters without sending a message.
    func fetchUsage() async throws -> AIResponse {
        KBLog.ai.kbDebug("fetchUsage started")
        
        guard let familyId = currentFamilyId else {
            KBLog.ai.kbError("fetchUsage blocked: missing familyId")
            throw AIServiceError.missingFamilyId
        }
        
        do {
            let result = try await functions.httpsCallable("getAIUsage")
                .call(["familyId": familyId])
            
            guard
                let data = result.data as? [String: Any],
                let usageToday = data["usageToday"] as? Int,
                let dailyLimit = data["dailyLimit"] as? Int
            else {
                KBLog.ai.kbError("fetchUsage invalid response: missing expected fields")
                throw AIServiceError.invalidResponse
            }
            
            KBLog.ai.kbInfo("fetchUsage succeeded usageToday=\(usageToday) dailyLimit=\(dailyLimit) familyId=\(familyId)")
            await AIUsageStore.shared.apply(usageToday: usageToday, dailyLimit: dailyLimit)

            return AIResponse(
                reply: "",
                usageToday: usageToday,
                dailyLimit: dailyLimit
            )
            
        } catch let error as NSError {
            let message = error.localizedDescription
            let code = FunctionsErrorCode(rawValue: error.code)
            
            KBLog.ai.kbError("fetchUsage failed firebaseCode=\(error.code) description=\(message)")
            
            switch code {
            case .resourceExhausted:
                throw AIServiceError.rateLimitReached(message)
                
            case .unauthenticated:
                throw AIServiceError.serverError("Sessione scaduta. Effettua di nuovo il login.")
                
            case .unavailable, .internal:
                throw AIServiceError.serverError("Servizio AI temporaneamente non disponibile.")
                
            default:
                throw AIServiceError.networkError(message)
            }
        }
    }

    // MARK: - Travel suggestions

    func suggestTravelDestinations(
        _ request: TravelSuggestionsRequest,
        familyId: String
    ) async throws -> TravelSuggestionsResponse {
        await KBSubscriptionManager.shared.loadPlan()
        guard KBSubscriptionManager.shared.currentPlan.includesAI else {
            throw AIServiceError.rateLimitReached("Piano Pro o Max richiesto per i suggerimenti AI.")
        }
        guard AISettings.shared.isEnabled else {
            throw AIServiceError.notEnabled
        }
        guard !familyId.isEmpty else {
            throw AIServiceError.missingFamilyId
        }

        let payload = try jsonSafeCallablePayload([
            "familyId": familyId,
            "travelProfile": request.travelProfile,
        ])

        let callable = functions.httpsCallable("suggestTravelDestinations")
        callable.timeoutInterval = 90

        do {
            let result = try await callable.call(payload)
            guard let data = result.data as? [String: Any],
                  let rawList = data["destinations"] as? [[String: Any]] else {
                throw AIServiceError.invalidResponse
            }
            let destinations = rawList.compactMap { TravelDestination(dictionary: $0) }
            guard !destinations.isEmpty else { throw AIServiceError.invalidResponse }

            let usageToday = data["usageToday"] as? Int ?? 0
            let dailyLimit = data["dailyLimit"] as? Int ?? 0
            await AIUsageStore.shared.apply(usageToday: usageToday, dailyLimit: dailyLimit)

            return TravelSuggestionsResponse(
                destinations: destinations,
                profileSummary: data["profileSummary"] as? String ?? "",
                usageToday: usageToday,
                dailyLimit: dailyLimit
            )
        } catch let error as NSError {
            throw mapCallableError(error)
        }
    }

    // MARK: - Travel plan

    func generateTravelPlan(_ request: TravelPlanRequest, familyId: String) async throws -> TravelPlanResponse {
        // Allinea il piano con Firestore (planOverride / families.plan) prima del gate client.
        await KBSubscriptionManager.shared.loadPlan()
        guard KBSubscriptionManager.shared.currentPlan.includesAI else {
            KBLog.ai.kbInfo("generateTravelPlan blocked: plan does not include AI")
            throw AIServiceError.rateLimitReached(
                "Piano Pro o Max richiesto. Verifica planOverride su families/\(familyId) in Firebase."
            )
        }
        guard AISettings.shared.isEnabled else {
            throw AIServiceError.notEnabled
        }
        guard !familyId.isEmpty else {
            throw AIServiceError.missingFamilyId
        }

        KBLog.ai.kbInfo("generateTravelPlan started familyId=\(familyId)")

        var callableFields: [String: Any] = [
            "familyId": familyId,
            "wizardData": request.wizardData,
            "freeTextPrompt": request.freeTextPrompt,
            "familyContext": request.familyContext,
        ]
        if request.regenerateSingleDay {
            callableFields["regenerateSingleDay"] = true
        }
        let payload = try jsonSafeCallablePayload(callableFields)

        let callable = functions.httpsCallable("generateTravelPlan")
        callable.timeoutInterval = Self.travelPlanClientTimeout

        do {
            KBLog.ai.kbInfo("generateTravelPlan calling function timeout=\(Self.travelPlanClientTimeout)s regenerateSingleDay=\(request.regenerateSingleDay)")
            NSLog("[KidBox][AI] generateTravelPlan → calling Firebase callable (timeout=\(Self.travelPlanClientTimeout)s, regenerateSingleDay=\(request.regenerateSingleDay))")
            let startedAt = Date()
            let result = try await callable.call(payload)
            let elapsed = Date().timeIntervalSince(startedAt)
            NSLog("[KidBox][AI] generateTravelPlan ← callable returned after \(String(format: "%.1f", elapsed))s")

            guard let data = result.data as? [String: Any] else {
                NSLog("[KidBox][AI] generateTravelPlan: invalid response (data not [String:Any])")
                throw AIServiceError.invalidResponse
            }

            let usageToday = data["usageToday"] as? Int ?? 0
            let dailyLimit = data["dailyLimit"] as? Int ?? 0
            await AIUsageStore.shared.apply(usageToday: usageToday, dailyLimit: dailyLimit)

            let travelPlan = TravelJSONCoercion.travelPlan(data["travelPlan"])
            let dayPlanCount = travelPlan.map { TravelJSONCoercion.dayPlans(from: $0).count } ?? 0
            let narrativeLen = (data["narrativeText"] as? String ?? "").count
            KBLog.ai.kbInfo(
                "generateTravelPlan success dayPlans=\(dayPlanCount) narrativeLen=\(narrativeLen)"
            )
            NSLog("[KidBox][AI] generateTravelPlan SUCCESS dayPlans=\(dayPlanCount) narrativeLen=\(narrativeLen) usage=\(usageToday)/\(dailyLimit)")

            return TravelPlanResponse(
                travelPlan: travelPlan,
                narrativeText: data["narrativeText"] as? String ?? "",
                usageToday: usageToday,
                dailyLimit: dailyLimit
            )
        } catch let error as NSError {
            KBLog.ai.kbError("generateTravelPlan failed domain=\(error.domain) code=\(error.code) desc=\(error.localizedDescription)")
            NSLog("[KidBox][AI] generateTravelPlan FAILED domain=\(error.domain) code=\(error.code) desc=\(error.localizedDescription) userInfo=\(error.userInfo)")
            throw mapCallableError(error)
        }
    }
}
