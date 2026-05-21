//
//  SupportAssistantReplyParser.swift
//  KidBox
//

import Foundation

struct ParsedSupportAssistantReply {
    let displayText: String
    let type: String?
    let requestSubmit: Bool
}

enum SupportAssistantReplyParser {
    private static let typePattern = #"\[TYPE:(question|bug|suggestion)\]"#
    private static let submitPattern = #"\[SUBMIT\]"#

    private static let submitPhrases = [
        "posso inviare il ticket",
        "invio il ticket",
        "confermi l'invio",
        "procedo con l'invio",
        "ticket pronto per l'invio",
    ]

    static func parse(_ raw: String) -> ParsedSupportAssistantReply {
        let type = extractType(from: raw)
        let lower = raw.lowercased()
        let requestSubmit = raw.range(of: submitPattern, options: [.regularExpression, .caseInsensitive]) != nil
            || submitPhrases.contains { lower.contains($0) }
        var display = raw
        if let regex = try? NSRegularExpression(pattern: typePattern, options: .caseInsensitive) {
            display = regex.stringByReplacingMatches(
                in: display,
                range: NSRange(display.startIndex..., in: display),
                withTemplate: "",
            )
        }
        if let regex = try? NSRegularExpression(pattern: submitPattern, options: .caseInsensitive) {
            display = regex.stringByReplacingMatches(
                in: display,
                range: NSRange(display.startIndex..., in: display),
                withTemplate: "",
            )
        }
        return ParsedSupportAssistantReply(
            displayText: display.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            requestSubmit: requestSubmit,
        )
    }

    private static func extractType(from raw: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: typePattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: raw) else { return nil }
        return String(raw[r]).lowercased()
    }
}
