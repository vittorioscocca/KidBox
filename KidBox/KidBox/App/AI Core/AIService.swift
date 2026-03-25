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
    
    var usageSummary: String { "\(usageToday)/\(dailyLimit) messaggi oggi" }
    var isNearLimit: Bool { usageToday >= Int(Double(dailyLimit) * 0.8) }
}

// MARK: - Service

/// Sends messages to the KidBox `askAI` Firebase Cloud Function.
///
/// The function handles authentication, rate limiting, and the Anthropic API call.
/// No API key is ever stored or transmitted from the client.
final class AIService {
    
    static let shared = AIService()
    
    private lazy var functions = Functions.functions(region: "europe-west1")
    
    private init() {
        KBLog.ai.kbDebug("AIService initialized region=europe-west1")
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
            
            KBLog.ai.kbInfo("sendMessage succeeded replyLength=\(reply.count) usageToday=\(usageToday) dailyLimit=\(dailyLimit)")
            
            return AIResponse(
                reply: reply,
                usageToday: usageToday,
                dailyLimit: dailyLimit
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
}
