//
//  AIService.swift
//  KidBox
//
//  Chiama la Cloud Function `askAI` su Firebase invece di Anthropic direttamente.
//  La API key Anthropic è gestita interamente lato server — mai sul client.
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
    
    private let log = Logger(subsystem: "com.kidbox", category: "ai_service")
    private lazy var functions = Functions.functions(region: "europe-west1")
    
    private init() {}
    
    /// Sends the conversation to the AI and returns the assistant reply.
    func sendMessage(
        messages: [KBAIMessage],
        systemPrompt: String
    ) async throws -> AIResponse {
        
        guard AISettings.shared.isEnabled else {
            throw AIServiceError.notEnabled
        }
        
        log.debug("AIService: sending \(messages.count) messages")
        
        let payload: [String: Any] = [
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "systemPrompt": systemPrompt
        ]
        
        do {
            let result = try await functions.httpsCallable("askAI").call(payload)
            
            guard
                let data       = result.data as? [String: Any],
                let reply      = data["reply"]      as? String,
                let usageToday = data["usageToday"] as? Int,
                let dailyLimit = data["dailyLimit"] as? Int
            else {
                throw AIServiceError.invalidResponse
            }
            
            log.info("AIService: reply OK usageToday=\(usageToday)/\(dailyLimit)")
            return AIResponse(reply: reply, usageToday: usageToday, dailyLimit: dailyLimit)
            
        } catch let error as NSError {
            let message = error.localizedDescription
            let code = FunctionsErrorCode(rawValue: error.code)
            
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
    
    /// Fetches today's usage counters without sending a message.
    func fetchUsage() async throws -> AIResponse {
        let result = try await functions.httpsCallable("getAIUsage").call([:])
        guard
            let data       = result.data as? [String: Any],
            let usageToday = data["usageToday"] as? Int,
            let dailyLimit = data["dailyLimit"] as? Int
        else { throw AIServiceError.invalidResponse }
        return AIResponse(reply: "", usageToday: usageToday, dailyLimit: dailyLimit)
    }
}
