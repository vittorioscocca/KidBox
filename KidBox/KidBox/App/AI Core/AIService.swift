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
    /// L'utente non è (più) membro della famiglia su cui sta chiamando.
    case familyAccessLost(String)
    
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
        case .familyAccessLost(let msg):
            return msg
        }
    }
}

// MARK: - Response

struct AIResponse {
    let reply: String
    let usageToday: Int
    let dailyLimit: Int
    /// Periodo su cui si resetta il contatore (mensile su Free, giornaliero su Pro/Max).
    let period: AIQuotaPeriod
    /// Messaggi scalati sul contatore per questa richiesta (1 = contesto standard).
    let messageUnitsConsumed: Int
    let isLargeContext: Bool

    /// Caratteri payload inviati (se restituiti dalla Cloud Function).
    let totalPayloadChars: Int?

    init(
        reply: String,
        usageToday: Int,
        dailyLimit: Int,
        period: AIQuotaPeriod = .daily,
        messageUnitsConsumed: Int = 1,
        isLargeContext: Bool = false,
        totalPayloadChars: Int? = nil
    ) {
        self.reply = reply
        self.usageToday = usageToday
        self.dailyLimit = dailyLimit
        self.period = period
        self.messageUnitsConsumed = messageUnitsConsumed
        self.isLargeContext = isLargeContext
        self.totalPayloadChars = totalPayloadChars
    }

    var usageSummary: String {
        period == .lifetime
            ? "\(usageToday)/\(dailyLimit) messaggi gratuiti"
            : "\(usageToday)/\(dailyLimit) messaggi oggi"
    }
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

/// Messaggio askAI: `content` può essere `String` o array di blocchi Anthropic (vision).
struct AIMessagePayload {
    let role: String
    let content: Any
}

// MARK: - Service

/// Sends messages to the KidBox `askAI` Firebase Cloud Function.
///
/// The function handles authentication, rate limiting, and the Anthropic API call.
/// No API key is ever stored or transmitted from the client.
final class AIService {
    
    static let shared = AIService()
    

    /// Itinerario viaggio: risposta lenta (fino a ~2 min lato server).
    private static let travelPlanClientTimeout: TimeInterval = 150
    /// Cartella clinica Sonnet: allineato a `timeoutSeconds: 120` su askAI.
    private static let clinicalRecordClientTimeout: TimeInterval = 240
    /// Piano alimentare Haiku: output lungo (max_tokens 8192), stesso timeout server.
    /// Il piano genera fino a 8192 token di output: 120s non bastavano.
    private static let mealPlanClientTimeout: TimeInterval = 300
    /// Piano fitness: come il piano alimentare, JSON lungo su 4 settimane.
    private static let fitnessPlanClientTimeout: TimeInterval = 300

    /// Purpose askAI riservati ai piani a pagamento.
    ///
    /// È il presidio client sul collo di bottiglia: ogni percorso — prima
    /// generazione, rigenerazione, spostamento di una seduta, copilota — passa
    /// da qui. Il gate vero resta lato server (`quota.period === "lifetime"`),
    /// questo evita di bruciare una chiamata e dà un messaggio sensato.
    private static let paidOnlyPurposes: Set<String> = [
        "mealPlan", "fitnessPlan", "fitnessAdjust", "fitnessCopilot",
    ]
    
    private init() {
        KBLog.ai.kbDebug("AIService initialized region=europe-west1")
    }

    /// Rifiuto perché la famiglia non è (più) nostra, o chiamata non partita
    /// perché il presidio l'ha sospesa. Non è né rete né quota: va detto com'è,
    /// altrimenti l'utente legge "errore di rete" e riprova all'infinito.
    private func familyAccessError(_ error: Error) -> AIServiceError? {
        if let suspended = error as? KBFamilyCallableError {
            return .familyAccessLost(suspended.localizedDescription)
        }
        if KBFamilyAccessGuard.isNotAMember(error) {
            return .familyAccessLost(error.localizedDescription)
        }
        return nil
    }

    /// Frase localizzata per il limite giornaliero, dai `details` del server.
    ///
    /// Un messaggio del copilota fitness o della cartella clinica scala più di
    /// un'unità: chi vede 95/100 e si sente dire "limite raggiunto" non capisce.
    /// Il testo del server è solo in italiano, i numeri invece viaggiano nei
    /// details e qui diventano una frase nella lingua dell'app.
    private func quotaExceededMessage(_ error: NSError) -> String? {
        guard let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any],
              details["reason"] as? String == "daily-limit",
              let units = details["units"] as? Int,
              let remaining = details["remaining"] as? Int,
              let limit = details["limit"] as? Int
        else { return nil }
        if units > 1, remaining > 0 {
            return String(
                format: NSLocalizedString(
                    "Questo messaggio costa %1$d messaggi AI perché il contesto è ampio, e oggi alla famiglia ne restano %2$d su %3$d. Riprova domani.",
                    comment: "AI daily quota: message costs more units than remaining"
                ),
                units, remaining, limit
            )
        }
        return String(
            format: NSLocalizedString(
                "La famiglia ha raggiunto il limite di %d messaggi AI per oggi. Riprova domani.",
                comment: "AI daily quota reached"
            ),
            limit
        )
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
            return .rateLimitReached(quotaExceededMessage(error) ?? message)
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
            return .serverError("La richiesta AI ha impiegato troppo tempo. Riprova con una connessione stabile.")
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
    /// - Parameter purpose: `"clinicalRecord"` usa Sonnet lato server; `"mealPlan"` usa Haiku con max_tokens esteso; `"fitnessPlan"` usa Sonnet con max_tokens esteso; `"fitnessAdjust"` e `"fitnessCopilot"` sono chat su Sonnet riservate ai piani a pagamento (tutto il fitness scala 3× le unità); `nil` = Haiku (chat Salute, visite, esami, ecc.).
    func sendMessage(
        messages: [KBAIMessage],
        systemPrompt: String,
        purpose: String? = nil
    ) async throws -> AIResponse {
        let payloadMessages = messages.map {
            AIMessagePayload(role: $0.role.rawValue, content: $0.content)
        }
        return try await sendMessages(
            messages: payloadMessages,
            systemPrompt: systemPrompt,
            purpose: purpose,
        )
    }

    /// Chiamata askAI con content String o blocchi multimodali (vision).
    func sendMessages(
        messages: [AIMessagePayload],
        systemPrompt: String,
        purpose: String? = nil
    ) async throws -> AIResponse {

        guard AISettings.shared.isEnabled else {
            KBLog.ai.kbInfo("sendMessage blocked: AI assistant disabled")
            throw AIServiceError.notEnabled
        }

        if let purpose, Self.paidOnlyPurposes.contains(purpose) {
            // Allinea il piano con Firestore prima del gate: `isAIAccessible`
            // non basta, lascerebbe passare un Free col bonus ancora intatto.
            await KBSubscriptionManager.shared.loadPlan()
            guard KBSubscriptionManager.shared.currentPlan != .free else {
                KBLog.ai.kbInfo("sendMessages blocked: purpose=\(purpose) requires a paid plan")
                throw AIServiceError.rateLimitReached(
                    NSLocalizedString(
                        "Questa funzione AI è inclusa nei piani Pro e Max. Passa a Pro per usarla.",
                        comment: "Paid-only AI purpose blocked"
                    )
                )
            }
        }

        guard let familyId = currentFamilyId else {
            KBLog.ai.kbError("sendMessage blocked: missing familyId")
            throw AIServiceError.missingFamilyId
        }

        KBLog.ai.kbInfo("sendMessages started messagesCount=\(messages.count) familyId=\(familyId) purpose=\(purpose ?? "default")")

        var payload: [String: Any] = [
            "messages": messages.map { [
                "role": $0.role,
                "content": $0.content,
            ] },
            "systemPrompt": systemPrompt,
            "familyId": familyId,
        ]
        if let purpose, !purpose.isEmpty {
            payload["purpose"] = purpose
        }

        var timeout: TimeInterval?
        if purpose == "clinicalRecord" {
            timeout = Self.clinicalRecordClientTimeout
        } else if purpose == "mealPlan" {
            timeout = Self.mealPlanClientTimeout
        } else if purpose == "fitnessPlan" {
            timeout = Self.fitnessPlanClientTimeout
        } else if purpose == "fitnessAdjust" || purpose == "fitnessCopilot" {
            // Su Sonnet una modifica a più sedute supera i 70s di default.
            timeout = Self.clinicalRecordClientTimeout
        }
        let timeoutLabel = timeout.map { "\($0)s" } ?? "default"
        KBLog.ai.kbDebug(
            "Calling Firebase Function askAI payloadMessagesCount=\(messages.count) timeout=\(timeoutLabel)"
        )

        do {
            let safePayload = try jsonSafeCallablePayload(payload)
            let result = try await KBFamilyAccessGuard.call(
                "askAI",
                familyId: familyId,
                payload: safePayload,
                timeout: timeout,
                source: "AIService.sendMessages"
            )

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
            let totalPayloadChars = data["totalPayloadChars"] as? Int
            let period = (data["period"] as? String).flatMap(AIQuotaPeriod.init) ?? .daily

            KBLog.ai.kbInfo(
                "sendMessage succeeded replyLength=\(reply.count) usageToday=\(usageToday) dailyLimit=\(dailyLimit) units=\(messageUnitsConsumed) payloadChars=\(totalPayloadChars ?? -1)"
            )
            await AIUsageStore.shared.apply(usageToday: usageToday, dailyLimit: dailyLimit)

            return AIResponse(
                reply: reply,
                usageToday: usageToday,
                dailyLimit: dailyLimit,
                period: period,
                messageUnitsConsumed: messageUnitsConsumed,
                isLargeContext: isLargeContext,
                totalPayloadChars: totalPayloadChars,
            )

        } catch {
            if let accessError = familyAccessError(error) {
                KBLog.ai.kbError("sendMessage failed: accesso alla famiglia perso familyId=\(familyId)")
                throw accessError
            }
            let ns = error as NSError
            KBLog.ai.kbError("sendMessage failed firebaseCode=\(ns.code) description=\(ns.localizedDescription)")
            throw mapCallableError(ns)
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
            let result = try await KBFamilyAccessGuard.call(
                "getAIUsage",
                familyId: familyId,
                source: "AIService.fetchUsage"
            )
            
            guard
                let data = result.data as? [String: Any],
                let usageToday = data["usageToday"] as? Int,
                let dailyLimit = data["dailyLimit"] as? Int
            else {
                KBLog.ai.kbError("fetchUsage invalid response: missing expected fields")
                throw AIServiceError.invalidResponse
            }
            
            let period = (data["period"] as? String).flatMap(AIQuotaPeriod.init) ?? .daily
            KBLog.ai.kbInfo("fetchUsage succeeded usageToday=\(usageToday) dailyLimit=\(dailyLimit) familyId=\(familyId)")
            await AIUsageStore.shared.apply(usageToday: usageToday, dailyLimit: dailyLimit)

            return AIResponse(
                reply: "",
                usageToday: usageToday,
                dailyLimit: dailyLimit,
                period: period
            )
            
        } catch {
            if let accessError = familyAccessError(error) {
                KBLog.ai.kbError("fetchUsage failed: accesso alla famiglia perso familyId=\(familyId)")
                throw accessError
            }
            let ns = error as NSError
            let message = ns.localizedDescription
            let code = FunctionsErrorCode(rawValue: ns.code)
            
            KBLog.ai.kbError("fetchUsage failed firebaseCode=\(ns.code) description=\(message)")
            
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
        guard KBSubscriptionManager.shared.isAIAccessible else {
            throw AIServiceError.rateLimitReached(
                "Hai esaurito i messaggi AI gratuiti del piano Free. Passa a Pro per i suggerimenti AI."
            )
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

        do {
            let result = try await KBFamilyAccessGuard.call(
                "suggestTravelDestinations",
                familyId: familyId,
                payload: payload,
                timeout: 90,
                source: "AIService.suggestTravelDestinations"
            )
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
        } catch {
            if let accessError = familyAccessError(error) { throw accessError }
            throw mapCallableError(error as NSError)
        }
    }

    // MARK: - Travel plan

    func generateTravelPlan(_ request: TravelPlanRequest, familyId: String) async throws -> TravelPlanResponse {
        // Allinea il piano con Firestore (planOverride / families.plan) prima del gate client.
        await KBSubscriptionManager.shared.loadPlan()
        // Feature dei soli piani a pagamento (il server rifiuta comunque i Free):
        // `isAIAccessible` da solo lascerebbe passare un Free col bonus intatto.
        guard KBSubscriptionManager.shared.currentPlan != .free else {
            KBLog.ai.kbInfo("generateTravelPlan blocked: travel planner requires a paid plan")
            throw AIServiceError.rateLimitReached(
                "Il Pianificatore Viaggi è incluso nei piani Pro e Max. Passa a Pro per pianificare il viaggio con l'AI."
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

        do {
            KBLog.ai.kbInfo("generateTravelPlan calling function timeout=\(Self.travelPlanClientTimeout)s regenerateSingleDay=\(request.regenerateSingleDay)")
            NSLog("[KidBox][AI] generateTravelPlan → calling Firebase callable (timeout=\(Self.travelPlanClientTimeout)s, regenerateSingleDay=\(request.regenerateSingleDay))")
            let startedAt = Date()
            let result = try await KBFamilyAccessGuard.call(
                "generateTravelPlan",
                familyId: familyId,
                payload: payload,
                timeout: Self.travelPlanClientTimeout,
                source: "AIService.generateTravelPlan"
            )
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
        } catch {
            if let accessError = familyAccessError(error) { throw accessError }
            let ns = error as NSError
            KBLog.ai.kbError("generateTravelPlan failed domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")
            NSLog("[KidBox][AI] generateTravelPlan FAILED domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription) userInfo=\(ns.userInfo)")
            throw mapCallableError(ns)
        }
    }
}
