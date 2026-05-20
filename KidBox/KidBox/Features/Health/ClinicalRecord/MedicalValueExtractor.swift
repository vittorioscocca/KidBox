//
//  MedicalValueExtractor.swift
//  KidBox
//

import Foundation

/// Estrae valori clinici numerici e strutturati da testo referto (offline).
enum MedicalValueExtractor {

    static func extract(
        from text: String,
        sourceId: String,
        sourceLabel: String,
        date: Date
    ) -> [ExtractedMedicalValue] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }

        var out: [ExtractedMedicalValue] = []
        out.append(contentsOf: extractBloodPressure(normalized, sourceId: sourceId, sourceLabel: sourceLabel, date: date))
        out.append(contentsOf: extractLesions(normalized, sourceId: sourceId, sourceLabel: sourceLabel, date: date))
        out.append(contentsOf: extractLabValues(normalized, sourceId: sourceId, sourceLabel: sourceLabel, date: date))
        out.append(contentsOf: extractHeartRate(normalized, sourceId: sourceId, sourceLabel: sourceLabel, date: date))
        out.append(contentsOf: extractWeight(normalized, sourceId: sourceId, sourceLabel: sourceLabel, date: date))
        out.append(contentsOf: extractStressTest(normalized, sourceId: sourceId, sourceLabel: sourceLabel, date: date))
        return dedupe(out)
    }

    // MARK: - Blood pressure

    private static func extractBloodPressure(
        _ text: String,
        sourceId: String,
        sourceLabel: String,
        date: Date
    ) -> [ExtractedMedicalValue] {
        let pattern = #"(?i)(?:PA|pressione(?:\s+arteriosa)?|misurata)[^\d]{0,30}(\d{2,3})\s*[/\\]\s*(\d{2,3})\s*(mm\s*Hg|mmhg)?"#
        return allMatches(pattern, in: text).map { m in
            let sys = Int(capture(m, 1)) ?? 0
            let dia = Int(capture(m, 2)) ?? 0
            return ExtractedMedicalValue(
                kind: .bloodPressure,
                parameterName: "Pressione arteriosa",
                numericValue: Double(sys),
                textValue: "\(sys)/\(dia) mmHg",
                unit: "mmHg",
                systolic: sys,
                diastolic: dia,
                lesionType: nil,
                dimensionMm: nil,
                date: date,
                sourceId: sourceId,
                sourceLabel: sourceLabel
            )
        }
    }

    // MARK: - Lesions (cisti, angioma, nodulo…)

    private static func extractLesions(
        _ text: String,
        sourceId: String,
        sourceLabel: String,
        date: Date
    ) -> [ExtractedMedicalValue] {
        let pattern = #"(?i)(cist[a-zà]*|angiom[a-zà]*|agiom[a-zà]*|nodul[oàa]|formazione|lesione)\s+(?:di\s+)?(\d+(?:[.,]\d+)?)\s*(mm|cm)\b"#
        return allMatches(pattern, in: text).map { m in
            var mm = parseNumber(capture(m, 2)) ?? 0
            if capture(m, 3).lowercased() == "cm" { mm *= 10 }
            let tipo = capture(m, 1).capitalized
            return ExtractedMedicalValue(
                kind: .lesion,
                parameterName: "\(tipo) \(Int(mm)) mm",
                numericValue: mm,
                textValue: "\(tipo) \(formatNum(mm)) mm",
                unit: "mm",
                systolic: nil,
                diastolic: nil,
                lesionType: tipo,
                dimensionMm: mm,
                date: date,
                sourceId: sourceId,
                sourceLabel: sourceLabel
            )
        }
    }

    // MARK: - Lab

    private static let labNames: [(String, String)] = [
        ("glicemia", "Glicemia"),
        ("colesterolo totale", "Colesterolo totale"),
        ("colesterolo", "Colesterolo totale"),
        ("ldl", "LDL"),
        ("hdl", "HDL"),
        ("trigliceridi", "Trigliceridi"),
        ("creatinina", "Creatinina"),
        ("ferritina", "Ferritina"),
        ("tsh", "TSH"),
        ("psa", "PSA"),
        ("got", "GOT"),
        ("gpt", "GPT"),
        ("emoglobina", "Emoglobina"),
    ]

    private static func extractLabValues(
        _ text: String,
        sourceId: String,
        sourceLabel: String,
        date: Date
    ) -> [ExtractedMedicalValue] {
        var results: [ExtractedMedicalValue] = []
        for (key, label) in labNames {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let pattern = "(?i)\\b\(escaped)\\b\\s*[:=\\-]?\\s*(\\d+(?:[.,]\\d+)?)\\s*(mg/dl|mmol/l|ng/ml|m?ui/l|u/l|g/dl)?"
            for m in allMatches(pattern, in: text) {
                let value = parseNumber(capture(m, 1)) ?? 0
                let unitRaw = capture(m, 2)
                let unit = unitRaw.isEmpty ? defaultUnit(for: label) : unitRaw
                let textValue = unitRaw.isEmpty ? formatNum(value) : "\(formatNum(value)) \(unit)"
                results.append(ExtractedMedicalValue(
                    kind: .lab,
                    parameterName: label,
                    numericValue: value,
                    textValue: textValue,
                    unit: unit,
                    systolic: nil,
                    diastolic: nil,
                    lesionType: nil,
                    dimensionMm: nil,
                    date: date,
                    sourceId: sourceId,
                    sourceLabel: sourceLabel
                ))
            }
        }
        return results
    }

    // MARK: - Heart rate / weight / stress

    private static func extractHeartRate(
        _ text: String,
        sourceId: String,
        sourceLabel: String,
        date: Date
    ) -> [ExtractedMedicalValue] {
        let pattern = #"(?i)(?:FC(?:\s+max)?|frequenza\s+cardiaca)[^\d]{0,20}(\d{2,3})\s*bpm"#
        return allMatches(pattern, in: text).map { m in
            let v = parseNumber(capture(m, 1)) ?? 0
            return ExtractedMedicalValue(
                kind: .heartRate,
                parameterName: "Frequenza cardiaca",
                numericValue: v,
                textValue: "\(Int(v)) bpm",
                unit: "bpm",
                systolic: nil,
                diastolic: nil,
                lesionType: nil,
                dimensionMm: nil,
                date: date,
                sourceId: sourceId,
                sourceLabel: sourceLabel
            )
        }
    }

    private static func extractWeight(
        _ text: String,
        sourceId: String,
        sourceLabel: String,
        date: Date
    ) -> [ExtractedMedicalValue] {
        let pattern = #"(?i)peso\s*[:=]?\s*(\d+(?:[.,]\d+)?)\s*kg"#
        return allMatches(pattern, in: text).map { m in
            let v = parseNumber(capture(m, 1)) ?? 0
            return ExtractedMedicalValue(
                kind: .weight,
                parameterName: "Peso",
                numericValue: v,
                textValue: "\(formatNum(v)) kg",
                unit: "kg",
                systolic: nil,
                diastolic: nil,
                lesionType: nil,
                dimensionMm: nil,
                date: date,
                sourceId: sourceId,
                sourceLabel: sourceLabel
            )
        }
    }

    private static func extractStressTest(
        _ text: String,
        sourceId: String,
        sourceLabel: String,
        date: Date
    ) -> [ExtractedMedicalValue] {
        var results: [ExtractedMedicalValue] = []
        if let watts = firstMatch(#"(?i)(\d+(?:[.,]\d+)?)\s*W\b"#, in: text), let w = parseNumber(watts) {
            results.append(ExtractedMedicalValue(
                kind: .stressTest, parameterName: "Carico prova da sforzo",
                numericValue: w, textValue: "\(Int(w)) W", unit: "W",
                systolic: nil, diastolic: nil, lesionType: nil, dimensionMm: nil,
                date: date, sourceId: sourceId, sourceLabel: sourceLabel
            ))
        }
        if let mets = firstMatch(#"(?i)(\d+(?:[.,]\d+)?)\s*METS?"#, in: text), let m = parseNumber(mets) {
            results.append(ExtractedMedicalValue(
                kind: .stressTest, parameterName: "METS",
                numericValue: m, textValue: "\(formatNum(m)) METS", unit: "METS",
                systolic: nil, diastolic: nil, lesionType: nil, dimensionMm: nil,
                date: date, sourceId: sourceId, sourceLabel: sourceLabel
            ))
        }
        if let pct = firstMatch(#"(?i)(\d+)\s*%\s*(?:della\s+)?(?:FC|frequenza)"#, in: text), let p = Double(pct) {
            results.append(ExtractedMedicalValue(
                kind: .stressTest, parameterName: "% FC massima teorica",
                numericValue: p, textValue: "\(Int(p))%", unit: "%",
                systolic: nil, diastolic: nil, lesionType: nil, dimensionMm: nil,
                date: date, sourceId: sourceId, sourceLabel: sourceLabel
            ))
        }
        return results
    }

    // MARK: - Helpers

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "—", with: "-")
    }

    /// Gruppi regex a indice fisso: `[0]` match completo, `[1]` primo capture, `[2]` secondo, …
    /// I capture opzionali assenti sono `""` (non compattati, per evitare index out of range).
    private static func allMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).map { match -> [String] in
            (0..<match.numberOfRanges).map { i -> String in
                let nsRange = match.range(at: i)
                guard nsRange.location != NSNotFound, let r = Range(nsRange, in: text) else { return "" }
                return String(text[r])
            }
        }
    }

    /// Indice del capture group (1 = primo gruppo tra parentesi, non il match completo).
    private static func capture(_ groups: [String], _ index: Int) -> String {
        guard index < groups.count else { return "" }
        return groups[index]
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let groups = allMatches(pattern, in: text).first else { return nil }
        let cap = capture(groups, 1)
        return cap.isEmpty ? nil : cap
    }

    private static func parseNumber(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }

    private static func formatNum(_ v: Double) -> String {
        v == floor(v) ? String(Int(v)) : String(format: "%.1f", v)
    }

    private static func defaultUnit(for label: String) -> String {
        switch label {
        case "PSA": return "ng/mL"
        case "TSH": return "mUI/L"
        case "GOT", "GPT": return "U/L"
        default: return "mg/dL"
        }
    }

    private static func dedupe(_ values: [ExtractedMedicalValue]) -> [ExtractedMedicalValue] {
        var seen = Set<String>()
        return values.filter { v in
            let key = "\(v.sourceId)|\(v.parameterName)|\(v.textValue ?? "")|\(v.date.timeIntervalSince1970)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }
}
