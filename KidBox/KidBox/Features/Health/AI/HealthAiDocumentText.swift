//
//  HealthAiDocumentText.swift
//  KidBox
//
//  Solo normalizzazione testo referto per il contesto AI (nessun troncamento).
//

import Foundation

enum HealthAiDocumentText {

    static func sanitizeExtractedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func prepareExtractedTextForAI(_ raw: String?) -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return sanitizeExtractedText(raw)
    }
}
