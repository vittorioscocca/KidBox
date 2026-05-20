//
//  ClinicalRecordSpecialtyRefertoSynthesis.swift
//  KidBox
//
//  Sintesi UI Cardiologia / Urologia: linguaggio dei referti, documenti uniti nel tempo.
//

import Foundation

enum ClinicalRecordSpecialtyRefertoSynthesis {

    struct Result {
        let synthesisParagraph: String
        let timelineDetail: String
        let highlights: [String]
    }

    private struct RefertoEntry: Identifiable {
        let date: Date
        let title: String
        let snippets: [String]
        var id: Date { date }
    }

    static func synthesize(
        specialty: ClinicalRecordTopicBuilder.TopicId,
        exams: [KBMedicalExam],
        visits: [KBMedicalVisit],
        parameters: [ParameterTrend]
    ) -> Result? {
        guard specialty == .cardiology || specialty == .urology else { return nil }

        let vocabulary = vocabulary(for: specialty)
        var entries: [RefertoEntry] = []

        for exam in exams where hasResultText(exam) {
            let blob = exam.name + " " + (exam.resultText ?? "")
            guard matchesSpecialty(specialty, blob) else { continue }
            let text = exam.resultText ?? ""
            let snippets = extractSnippets(from: text, vocabulary: vocabulary)
            guard !snippets.isEmpty else { continue }
            entries.append(RefertoEntry(
                date: exam.resultDate ?? exam.updatedAt,
                title: exam.name,
                snippets: snippets
            ))
        }

        for visit in visits {
            let blob = [visit.reason, visit.diagnosis, visit.recommendations]
                .compactMap { $0 }
                .joined(separator: " ")
            guard !blob.isEmpty, matchesSpecialty(specialty, blob) else { continue }
            let snippets = extractSnippets(from: blob, vocabulary: vocabulary)
            guard !snippets.isEmpty else { continue }
            entries.append(RefertoEntry(
                date: visit.date,
                title: visit.reason.isEmpty ? "Visita" : visit.reason,
                snippets: snippets
            ))
        }

        entries.sort { $0.date < $1.date }
        guard !entries.isEmpty else {
            return fallbackFromParameters(specialty: specialty, parameters: parameters)
        }

        let paragraph = buildSynthesisParagraph(
            specialty: specialty,
            entries: entries,
            parameters: parameters
        )
        let timeline = buildTimeline(entries: entries)
        let highlights = buildHighlights(entries: entries, parameters: parameters)

        return Result(
            synthesisParagraph: paragraph,
            timelineDetail: timeline,
            highlights: highlights
        )
    }

    // MARK: - Vocabulary

    private static func vocabulary(for specialty: ClinicalRecordTopicBuilder.TopicId) -> Set<String> {
        switch specialty {
        case .cardiology:
            return [
                "ecocardio", "ecocardiogramma", "sforzo", "ergometr", "coronar", "ischem",
                "ventricol", "valvol", "frazione", "fev", "f.e.", "mets", "aritmi", "extrasist",
                "lp", "ldl", "hdl", "colester", "triglicerid", "lipid", "pressione", "sistol",
                "diastol", "mmhg", "cuore", "cardiac", "normale", "nei limiti", "negativ", "stabile",
                "profilo", "capacità", "frequenza cardiaca", "bpm",
            ]
        case .urology:
            return [
                "prostata", "psa", "ren", "renale", "nefr", "cisti", "varicocele", "inguin",
                "vescica", "uro", "urofluss", "residuo", "iperplasia", "volume", "mm", "ml",
                "normale", "nei limiti", "negativ", "stabile", "ecografia", "addome",
            ]
        default:
            return []
        }
    }

    private static func matchesSpecialty(_ specialty: ClinicalRecordTopicBuilder.TopicId, _ text: String) -> Bool {
        let t = text.lowercased()
        switch specialty {
        case .cardiology:
            return t.contains("cardio") || t.contains("cuore") || t.contains("sforzo")
                || t.contains("ecocardio") || t.contains("coronar") || t.contains("colester")
                || t.contains("ldl") || t.contains("lipid") || t.contains("ergometr")
        case .urology:
            return t.contains("prostata") || t.contains("psa") || t.contains("ren")
                || t.contains("urolog") || t.contains("varicocele") || t.contains("inguin")
                || t.contains("vescica") || t.contains("cisti ren")
        default:
            return false
        }
    }

    // MARK: - Extraction

    private static func extractSnippets(from text: String, vocabulary: Set<String>) -> [String] {
        let clean = HealthAiDocumentText.sanitizeExtractedText(text)
        var candidates: [(score: Int, line: String)] = []

        let chunks = clean
            .replacingOccurrences(of: ". ", with: ".\n")
            .components(separatedBy: .newlines)

        for chunk in chunks {
            let line = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.count >= 12 else { continue }
            let lower = line.lowercased()
            let hits = vocabulary.filter { lower.contains($0) }.count
            guard hits > 0 else { continue }
            let bonus = line.contains(where: \.isNumber) ? 1 : 0
            candidates.append((hits + bonus, clipRefertoPhrase(line)))
        }

        var seen = Set<String>()
        return candidates
            .sorted { $0.score > $1.score }
            .map(\.line)
            .filter { seen.insert($0).inserted }
            .prefix(3)
            .map { $0 }
    }

    private static func clipRefertoPhrase(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "  ", with: " ")
        if t.count <= 140 { return t }
        return String(t.prefix(139)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Narrative

    private static func buildSynthesisParagraph(
        specialty: ClinicalRecordTopicBuilder.TopicId,
        entries: [RefertoEntry],
        parameters: [ParameterTrend]
    ) -> String {
        let areaLabel = specialty == .cardiology ? "cardiologico" : "urologico"
        let yFirst = year(entries.first!.date)
        let yLast = year(entries.last!.date)
        var parts: [String] = []

        parts.append(
            "Sintesi \(areaLabel) da \(entries.count) referti in archivio (\(yFirst)–\(yLast)), "
            + "con formulazioni tratte dai documenti originali."
        )

        if entries.count >= 2 {
            let opening = specialty == .cardiology
                ? "Nel periodo considerato la documentazione cardiologica mostra un percorso clinico ricostruibile dai referti."
                : "Nel periodo considerato i controlli urologici documentati nei referti delineano l'evoluzione del quadro."
            parts.append(opening)
        }

        for entry in entries {
            let when = formatMonthYear(entry.date)
            let quotes = entry.snippets.joined(separator: " Inoltre, ")
            parts.append("\(when), \(entry.title): \(quotes)")
        }

        if let paramNote = parameterEvolutionNote(parameters: parameters, specialty: specialty) {
            parts.append(paramNote)
        }

        let closing = specialty == .cardiology
            ? "Complessivamente, i referti vanno interpretati nel contesto delle terapie in corso e dei prossimi controlli programmati."
            : "Nel complesso, la documentazione urologica suggerisce di mantenere il follow-up indicato dai referti più recenti."
        parts.append(closing)

        return parts.joined(separator: " ")
    }

    private static func buildTimeline(entries: [RefertoEntry]) -> String {
        entries.map { entry in
            let when = formatMonthYear(entry.date)
            let body = entry.snippets.joined(separator: " ")
            return "\(when) — \(entry.title)\n\(body)"
        }.joined(separator: "\n\n")
    }

    private static func buildHighlights(
        entries: [RefertoEntry],
        parameters: [ParameterTrend]
    ) -> [String] {
        var out: [String] = []
        for entry in entries.suffix(3) {
            if let first = entry.snippets.first {
                out.append("\(formatMonthYear(entry.date)): \(first)")
            }
        }
        for param in parameters.suffix(2) {
            guard let last = param.points.last else { continue }
            let y = year(last.date)
            out.append("\(param.name) (\(y)): \(last.displayValue)")
        }
        return Array(out.prefix(4))
    }

    private static func parameterEvolutionNote(
        parameters: [ParameterTrend],
        specialty: ClinicalRecordTopicBuilder.TopicId
    ) -> String? {
        guard !parameters.isEmpty else { return nil }
        let bits = parameters.prefix(4).compactMap { param -> String? in
            guard param.points.count >= 2 else {
                guard let last = param.points.last else { return nil }
                return "\(param.name) nell'ultimo referto: \(last.displayValue)"
            }
            let series = param.points.map { p in
                "\(year(p.date)): \(p.displayValue)"
            }.joined(separator: " → ")
            let dir = param.trend == .stabile ? "stabile" : (param.trend == .inAumento ? "in aumento" : "in diminuzione")
            return "\(param.name) \(dir) nel periodo (\(series))"
        }
        guard !bits.isEmpty else { return nil }
        let label = specialty == .cardiology ? "Parametri ematici e funzionali" : "Parametri monitorati"
        return "\(label): \(bits.joined(separator: "; "))."
    }

    private static func fallbackFromParameters(
        specialty: ClinicalRecordTopicBuilder.TopicId,
        parameters: [ParameterTrend]
    ) -> Result? {
        guard let note = parameterEvolutionNote(parameters: parameters, specialty: specialty) else { return nil }
        let label = specialty.title
        return Result(
            synthesisParagraph: "Per \(label), dai dati estratti risulta: \(note)",
            timelineDetail: "",
            highlights: parameters.prefix(3).compactMap { p in
                p.points.last.map { "\(p.name): \($0.displayValue)" }
            }
        )
    }

    // MARK: - Helpers

    private static func hasResultText(_ exam: KBMedicalExam) -> Bool {
        guard let t = exam.resultText else { return false }
        return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func formatMonthYear(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    private static func year(_ date: Date) -> Int {
        Calendar.current.component(.year, from: date)
    }
}
