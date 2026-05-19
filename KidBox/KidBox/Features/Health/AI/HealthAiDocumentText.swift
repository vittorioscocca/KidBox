//
//  HealthAiDocumentText.swift
//  KidBox
//
//  Normalizzazione testo referto per il contesto AI.
//

import Foundation

enum HealthAiDocumentText {

    /// Limite per referto nel contesto “standard” (caricamento UI). Massima accuratezza usa testo intero.
    static let standardRefertoMaxChars = 4_000

    static func sanitizeExtractedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func prepareExtractedTextForAI(_ raw: String?, maxChars: Int? = nil) -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let sanitized = sanitizeExtractedText(raw)
        guard let maxChars, sanitized.count > maxChars else { return sanitized }
        let clipped = String(sanitized.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return clipped + "\n[… referto troncato nel contesto standard; usa “Massima accuratezza” per il testo completo]"
    }
}
