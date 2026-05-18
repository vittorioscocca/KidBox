//
//  TravelAIResponseParser.swift
//  KidBox
//

import Foundation

enum TravelAIResponseParser {

    static func parseTravelPlan(from raw: String) -> [String: Any]? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let regex = try? NSRegularExpression(
            pattern: "```(?:json)?\\s*\\n?([\\s\\S]*?)\\n?```",
            options: [.caseInsensitive]
        ) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let jsonRange = Range(match.range(at: 1), in: text) {
                let json = String(text[jsonRange])
                if let plan = parsePlanJSON(json) { return plan }
            }
        }

        if let regex = try? NSRegularExpression(
            pattern: "```(?:json)?\\s*([\\s\\S]+)",
            options: [.caseInsensitive]
        ) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let jsonRange = Range(match.range(at: 1), in: text) {
                let json = String(text[jsonRange])
                if let plan = parsePlanJSON(json) { return plan }
            }
        }

        if let tripRange = text.range(of: #"{\s*"trip"\s*:"#, options: .regularExpression) {
            let candidate = String(text[tripRange.lowerBound...])
            if let json = extractJSONObject(from: candidate),
               let plan = parsePlanJSON(json) {
                return plan
            }
        }

        if let dayRange = text.range(of: #"{\s*"dayPlans"\s*:"#, options: .regularExpression) {
            let candidate = String(text[dayRange.lowerBound...])
            if let json = extractJSONObject(from: candidate),
               let plan = parsePlanJSON(json) {
                return plan
            }
        }

        return nil
    }

    static func isStructuredTravelPlan(_ plan: [String: Any]?) -> Bool {
        guard let plan, !plan.isEmpty else { return false }
        if let trip = plan["trip"] as? [String: Any], !trip.isEmpty { return true }
        if let days = plan["dayPlans"] as? [[String: Any]], !days.isEmpty { return true }
        return false
    }

    /// Testo introduttivo senza blocco ```json``` o JSON grezzo finale.
    static func sanitizedNarrative(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let regex = try? NSRegularExpression(
            pattern: "```(?:json)?\\s*[\\s\\S]*?```",
            options: [.caseInsensitive]
        ) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }

        if let tripRange = text.range(of: #"{\s*"trip"\s*:"#, options: .regularExpression) {
            text = String(text[..<tripRange.lowerBound])
        }

        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        text = text.replacingOccurrences(
            of: "```(?:json)?\\s*",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parsePlanJSON(_ json: String) -> [String: Any]? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        func accept(_ obj: [String: Any]) -> [String: Any]? {
            if obj["trip"] != nil { return obj }
            if let days = obj["dayPlans"] as? [[String: Any]], !days.isEmpty { return obj }
            return nil
        }

        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let plan = accept(obj) {
            return plan
        }
        if let repaired = extractJSONObject(from: trimmed),
           let data = repaired.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let plan = accept(obj) {
            return plan
        }
        return nil
    }

    private static func extractJSONObject(from source: String) -> String? {
        var depth = 0
        var started = false
        var builder = ""
        for ch in source {
            if ch == "{" {
                if !started { started = true }
                depth += 1
            } else if ch == "}", started {
                depth -= 1
            }
            if started {
                builder.append(ch)
            }
            if started, depth == 0 {
                return builder
            }
        }
        if started, depth > 0 {
            builder.append(String(repeating: "}", count: depth))
            return builder
        }
        return nil
    }
}
