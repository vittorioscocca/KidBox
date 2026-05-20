//
//  ClinicalRecordMeasurementSummary.swift
//  KidBox
//

import Foundation

/// Sintesi misure ripetute (anti-elenco stesso anno / stesso parametro).
enum ClinicalRecordMeasurementSummary {

    /// Se >4 misure nello stesso anno, restituisce range + ultimo valore + tendenza invece dell'elenco completo.
    static func bloodPressureYearSummary(points: [ParameterTrendPoint]) -> String? {
        summarizeYearly(points: points) { $0.displayValue }
    }

    static func summarizeYearly(
        points: [ParameterTrendPoint],
        valueLabel: (ParameterTrendPoint) -> String
    ) -> String? {
        guard !points.isEmpty else { return nil }
        let sorted = points.sorted { $0.date < $1.date }
        let cal = Calendar.current
        var byYear: [Int: [ParameterTrendPoint]] = [:]
        for p in sorted {
            let y = cal.component(.year, from: p.date)
            byYear[y, default: []].append(p)
        }

        var phrases: [String] = []
        for year in byYear.keys.sorted() {
            let yearPoints = byYear[year] ?? []
            guard !yearPoints.isEmpty else { continue }
            if yearPoints.count > 4 {
                let labels = yearPoints.map(valueLabel)
                let minLabel = labels.first ?? "—"
                let maxLabel = labels.last ?? "—"
                let last = yearPoints.last.map(valueLabel) ?? "—"
                let trend = yearPoints.count >= 2
                    ? (stableTrend(yearPoints) ? "con tendenza alla stabilità" : "con variazioni nel corso dell'anno")
                    : ""
                phrases.append(
                    "Nel \(year) i valori si sono attestati tra \(minLabel) e \(maxLabel), ultima rilevazione \(last)\(trend.isEmpty ? "" : ", \(trend)")"
                )
            } else {
                let series = yearPoints.map { "\(formatShort($0.date)): \(valueLabel($0))" }.joined(separator: ", ")
                phrases.append("Nel \(year): \(series)")
            }
        }
        return phrases.isEmpty ? nil : phrases.joined(separator: ". ") + "."
    }

    private static func stableTrend(_ points: [ParameterTrendPoint]) -> Bool {
        guard points.count >= 2 else { return true }
        let nums = points.compactMap(\.numericValue)
        guard nums.count >= 2, let first = nums.first, let last = nums.last else { return true }
        let delta = abs(last - first)
        return delta <= max(5, first * 0.08)
    }

    private static func formatShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.dateFormat = "MMM yyyy"
        return f.string(from: date)
    }
}
