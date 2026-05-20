//
//  ClinicalRecordTextSanitizer.swift
//  KidBox
//

import Foundation

/// Rimuove artefatti Markdown e simboli AI (`*`, `**`, `` ` ``, `#`, `*/`, ecc.) da testi cartella clinica.
enum ClinicalRecordTextSanitizer {

    static func sanitize(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "```", with: "")
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")
        s = s.replacingOccurrences(of: "`", with: "")
        s = s.replacingOccurrences(of: "*/", with: "")
        s = s.replacingOccurrences(of: "/*", with: "")

        let lines = s.components(separatedBy: "\n").map { line -> String in
            var l = line.trimmingCharacters(in: .whitespaces)
            while l.hasPrefix("#") { l.removeFirst() }
            l = l.trimmingCharacters(in: .whitespaces)
            l = stripListMarker(l)
            l = l.replacingOccurrences(of: "*", with: "")
            return l
        }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sanitizeLines(_ lines: [String]) -> [String] {
        lines.map { sanitize($0) }.filter { !$0.isEmpty || $0 == "---" }
    }

    /// Rimuove prefissi elenco (bullet/numeri) lasciando testo continuo per output narrativo AI.
    private static func stripListMarker(_ line: String) -> String {
        var l = line
        if l.hasPrefix("• ") { return String(l.dropFirst(2)) }
        if l.hasPrefix("- ") && !l.hasPrefix("--") { return String(l.dropFirst(2)) }
        if l.hasPrefix("* ") { return String(l.dropFirst(2)) }
        if let dot = l.firstIndex(of: "."),
           l[..<dot].allSatisfy(\.isNumber),
           l.index(after: dot) < l.endIndex,
           l[l.index(after: dot)] == " " {
            return String(l[l.index(dot, offsetBy: 2)...])
        }
        return l
    }

    static func sanitizeArea(_ area: ClinicalRecordReportArea) -> ClinicalRecordReportArea {
        ClinicalRecordReportArea(
            id: area.id,
            title: sanitize(area.title),
            summary: sanitize(area.summary),
            narrative: sanitize(area.narrative),
            trendNarrative: area.trendNarrative.map { sanitize($0) },
            bullets: area.bullets.map { sanitize($0) }
        )
    }

    static func sanitizeReport(_ report: ClinicalRecordReport) -> ClinicalRecordReport {
        ClinicalRecordReport(
            generatedAt: report.generatedAt,
            source: report.source,
            subjectName: sanitize(report.subjectName),
            headerLines: sanitizeLines(report.headerLines),
            areas: report.areas.map { sanitizeArea($0) },
            fullDocumentLines: sanitizeLines(report.fullDocumentLines)
        )
    }
}
