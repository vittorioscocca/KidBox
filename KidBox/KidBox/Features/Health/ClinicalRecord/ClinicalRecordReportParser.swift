//
//  ClinicalRecordReportParser.swift
//  KidBox
//

import Foundation

enum ClinicalRecordReportParser {

    static func parse(
        text: String,
        subjectName: String,
        source: ClinicalRecordReportSource
    ) -> ClinicalRecordReport {
        let lines = ClinicalRecordTextSanitizer.sanitize(text)
            .components(separatedBy: "\n")

        var areas: [ClinicalRecordReportArea] = []
        var currentTitle = "Sintesi"
        var buffer: [String] = []

        func flush() {
            guard !buffer.isEmpty else { return }
            let body = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { buffer = []; return }
            let id = areaId(for: currentTitle)
            let bullets = body.components(separatedBy: "\n")
                .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("•") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
            areas.append(ClinicalRecordReportArea(
                id: id,
                title: currentTitle,
                summary: bullets.first ?? String(body.prefix(80)),
                narrative: body,
                trendNarrative: extractTrend(from: body),
                bullets: Array(bullets.prefix(8))
            ))
            buffer = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || isSectionHeader(trimmed) {
                flush()
                if isSectionHeader(trimmed) { currentTitle = trimmed }
                continue
            }
            buffer.append(line)
        }
        flush()

        return ClinicalRecordReport(
            generatedAt: Date(),
            source: source,
            subjectName: subjectName,
            headerLines: Array(lines.prefix(6)),
            areas: areas,
            fullDocumentLines: lines.filter { !$0.isEmpty || $0 == "---" }
        )
    }

    private static func isSectionHeader(_ line: String) -> Bool {
        if line.hasPrefix("CARTELLA CLINICA") { return false }
        if line.hasPrefix("•") || line.hasPrefix("-") { return false }
        if line.first?.isNumber == true { return false }
        return line == line.uppercased() && line.count > 8 && !line.contains(":")
    }

    private static func areaId(for title: String) -> String {
        let t = title.lowercased()
        if t.contains("terapie") || t.contains("cure") { return ClinicalRecordTopicBuilder.TopicId.therapies.rawValue }
        if t.contains("attesa") || t.contains("prenotat") { return ClinicalRecordTopicBuilder.TopicId.pending.rawValue }
        if t.contains("pressione") { return ClinicalRecordTopicBuilder.TopicId.cardiology.rawValue }
        if t.contains("cardio") || t.contains("cuore") { return ClinicalRecordTopicBuilder.TopicId.cardiology.rawValue }
        if t.contains("gastro") || t.contains("fegato") || t.contains("milza") { return ClinicalRecordTopicBuilder.TopicId.gastroenterology.rawValue }
        if t.contains("urolog") || t.contains("prostata") || t.contains("ren") { return ClinicalRecordTopicBuilder.TopicId.urology.rawValue }
        if t.contains("glicem") || t.contains("metabol") || t.contains("emocromo") || t.contains("laboratorio") {
            return ClinicalRecordTopicBuilder.TopicId.metabolism.rawValue
        }
        if t.contains("auxolog") || t.contains("crescita") || (t.contains("peso") && t.contains("altezza")) {
            return "auxology"
        }
        if t.contains("oculist") || t.contains("vista") { return "ophthalmology" }
        if t.contains("riepilogo") || t.contains("valutazione generale") { return "summary" }
        if t.contains("patolog") || t.contains("condizioni") { return "pathologies" }
        if t.contains("ultimi esami") || t.contains("esami significativ") { return "recent_exams" }
        return "section_\(abs(title.hashValue))"
    }

    private static func extractTrend(from body: String) -> String? {
        guard let range = body.range(of: "Andamento nel tempo", options: .caseInsensitive) else { return nil }
        return String(body[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
