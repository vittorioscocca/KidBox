//
//  ClinicalRecordLabTrends.swift
//  KidBox
//

import Foundation

struct LabMeasurementPoint: Equatable {
    let date: Date
    let year: Int
    let examName: String
    let metricLabel: String
    let value: String
    let unit: String?
    let context: String?
}

enum LabMetricFamily: String, CaseIterable {
    case lipids
    case cardiac
    case liverKidney
    case bloodCount
    case glycemic
    case other

    var displayTitle: String {
        switch self {
        case .lipids: return "Colesterolo e lipidi"
        case .cardiac: return "Cuore e prova da sforzo"
        case .liverKidney: return "Fegato, milza e reni"
        case .bloodCount: return "Emocromo e funzionalità"
        case .glycemic: return "Glicemia e metabolismo"
        case .other: return "Altri parametri"
        }
    }
}

enum ClinicalRecordLabTrends {

    private static let metricPatterns: [(LabMetricFamily, String, NSRegularExpression?)] = {
        func rx(_ pattern: String) -> NSRegularExpression? {
            try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        return [
            (.lipids, "Colesterolo totale", rx(#"(?i)colesterolo\s*totale[:\s]*(\d+[,.]?\d*)"#)),
            (.lipids, "LDL", rx(#"(?i)\bLDL[:\s-]*(\d+[,.]?\d*)"#)),
            (.lipids, "HDL", rx(#"(?i)\bHDL[:\s-]*(\d+[,.]?\d*)"#)),
            (.lipids, "Trigliceridi", rx(#"(?i)trigliceridi[:\s]*(\d+[,.]?\d*)"#)),
            (.glycemic, "Glicemia", rx(#"(?i)glicemia[:\s]*(\d+[,.]?\d*)"#)),
            (.bloodCount, "GOT", rx(#"(?i)\bGOT[:\s]*(\d+[,.]?\d*)"#)),
            (.bloodCount, "GPT", rx(#"(?i)\bGPT[:\s]*(\d+[,.]?\d*)"#)),
            (.bloodCount, "Creatinina", rx(#"(?i)creatinina[:\s]*(\d+[,.]?\d*)"#)),
            (.bloodCount, "PSA", rx(#"(?i)\bPSA[:\s]*(\d+[,.]?\d*)"#)),
            (.bloodCount, "Emoglobina", rx(#"(?i)emoglobina[:\s]*(\d+[,.]?\d*)"#)),
        ]
    }()

    static func extract(from exams: [KBMedicalExam]) -> [LabMetricFamily: [LabMeasurementPoint]] {
        var result: [LabMetricFamily: [LabMeasurementPoint]] = [:]
        for exam in exams {
            let text = [exam.name, exam.resultText ?? ""].joined(separator: "\n")
            guard !text.isEmpty else { continue }
            let date = exam.resultDate ?? exam.deadline ?? exam.updatedAt
            let year = Calendar.current.component(.year, from: date)

            for (family, label, regex) in metricPatterns {
                guard let regex, let value = firstMatch(regex, in: text) else { continue }
                let point = LabMeasurementPoint(
                    date: date,
                    year: year,
                    examName: exam.name,
                    metricLabel: label,
                    value: value.replacingOccurrences(of: ",", with: "."),
                    unit: unitHint(label: label, in: text),
                    context: clipContext(text)
                )
                result[family, default: []].append(point)
            }

            // Valori strutturati: usare MedicalValueExtractor via ClinicalRecordValueIndex.
        }
        for key in result.keys {
            result[key]?.sort { $0.date < $1.date }
        }
        return result
    }

    static func narrative(for family: LabMetricFamily, points: [LabMeasurementPoint]) -> String? {
        guard !points.isEmpty else { return nil }
        let byMetric = Dictionary(grouping: points, by: \.metricLabel)
        var lines: [String] = []
        lines.append("Andamento \(family.displayTitle.lowercased()):")
        for (metric, items) in byMetric.sorted(by: { $0.key < $1.key }) {
            let series = items.map { p -> String in
                let u = p.unit.map { " \($0)" } ?? ""
                return "\(p.year): \(p.value)\(u) (\(formatShort(p.date)))"
            }.joined(separator: " → ")
            lines.append("• \(metric): \(series)")
            if items.count >= 2, let first = items.first, let last = items.last,
               let v1 = Double(first.value), let v2 = Double(last.value) {
                let delta = v2 - v1
                let dir = delta > 5 ? "in aumento" : (delta < -5 ? "in diminuzione" : "sostanzialmente stabile")
                lines.append("  Sintesi: valore \(dir) nel periodo considerato.")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func formatAllTrends(_ trends: [LabMetricFamily: [LabMeasurementPoint]]) -> [String] {
        var out: [String] = []
        for family in LabMetricFamily.allCases {
            guard let points = trends[family], !points.isEmpty,
                  let text = narrative(for: family, points: points) else { continue }
            out.append(text)
        }
        return out
    }

    // MARK: - Private

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func unitHint(label: String, in text: String) -> String? {
        if text.lowercased().contains("mg/dl") { return "mg/dL" }
        if text.lowercased().contains("ng/ml") { return "ng/mL" }
        if text.lowercased().contains("u/l") || text.lowercased().contains("ui/l") { return "U/L" }
        if label.contains("Colesterolo") || label == "LDL" || label == "HDL" || label == "Trigliceridi" { return "mg/dL" }
        return nil
    }

    private static func clipContext(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.count <= 220 { return t }
        return String(t.prefix(219)) + "…"
    }

    private static func formatShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.dateFormat = "MMM yyyy"
        return f.string(from: date)
    }
}
