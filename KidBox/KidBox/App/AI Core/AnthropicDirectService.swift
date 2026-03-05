//
//  AnthropicDirectService.swift
//  KidBox
//
//  Created by vscocca on 05/03/26.
//


import Foundation
import OSLog

/// Calls the Anthropic API directly from the client.
///
/// Used ONLY for the first message of a visit chat session,
/// when images (referti) need to be included in the context.
///
/// For all subsequent text-only messages, `AIService` (Firebase Function) is used.
///
/// The API key is fetched at runtime from Firebase Remote Config — never hardcoded.
final class AnthropicDirectService {
    
    static let shared = AnthropicDirectService()
    
    private let log = Logger(subsystem: "com.kidbox", category: "anthropic_direct")
    private let model = "claude-sonnet-4-20250514"
    private let maxTokens = 1024
    
    private init() {}
    
    /// Sends the first contextual message with optional images to Anthropic directly.
    ///
    /// - Parameters:
    ///   - systemPrompt: Visit context built by `MedicalVisitContextBuilder`
    ///   - userText: The user's first question
    ///   - images: Encoded visit photos from `VisitImageLoader`
    /// - Returns: The assistant's reply text
    func sendInitialContext(
        systemPrompt: String,
        userText: String,
        images: [VisitImageLoader.EncodedImage]
    ) async throws -> String {
        
        log.debug("AnthropicDirectService: sending with \(images.count) images")
        
        let apiKey = try await RemoteConfigService.shared.anthropicAPIKey()
        
        // Build content array: text + images
        var contentItems: [[String: Any]] = []
        
        // Add images first (Anthropic recommends images before text)
        for image in images {
            contentItems.append([
                "type": "image",
                "source": [
                    "type":       "base64",
                    "media_type": image.mediaType,
                    "data":       image.base64
                ]
            ])
        }
        
        // Add user text
        contentItems.append([
            "type": "text",
            "text": userText.isEmpty
            ? "Analizza i referti allegati e spiegami cosa significano in modo semplice."
            : userText
        ])
        
        let body: [String: Any] = [
            "model":      model,
            "max_tokens": maxTokens,
            "system":     systemPrompt,
            "messages": [
                ["role": "user", "content": contentItems]
            ]
        ]
        
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Timeout più lungo per upload immagini
        request.timeoutInterval = 90
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        
        log.debug("AnthropicDirectService: HTTP \(http.statusCode)")
        
        switch http.statusCode {
        case 200:
            return try parseResponse(data)
        case 429:
            throw AIServiceError.rateLimitReached("Servizio AI sovraccarico. Riprova tra qualche secondo.")
        case 401:
            throw AIServiceError.serverError("Configurazione AI non valida. Contatta il supporto.")
        default:
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            log.error("AnthropicDirectService: error \(http.statusCode) \(body)")
            throw AIServiceError.serverError("Errore dal servizio AI (\(http.statusCode)).")
        }
    }
    
    // MARK: - Private
    
    private func parseResponse(_ data: Data) throws -> String {
        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let first   = content.first,
            let text    = first["text"] as? String
        else {
            throw AIServiceError.invalidResponse
        }
        return text
    }
}
