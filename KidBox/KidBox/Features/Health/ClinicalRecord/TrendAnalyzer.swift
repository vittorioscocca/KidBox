//
//  TrendAnalyzer.swift
//  KidBox
//

import Foundation

enum TrendAnalyzer {

    static func buildSpecialtyTrend(
        specialtyId: String,
        specialtyTitle: String,
        values: [ExtractedMedicalValue],
        chronologyLines: [String],
        pendingLines: [String] = []
    ) -> SpecialtyTrendSnapshot? {
        guard ClinicalRecordSectionPolicy.shouldGenerateStandaloneSection(id: specialtyId) else { return nil }
        let relevant = values.filter { mapsToSpecialty($0, specialtyId: specialtyId) }
        let parameters = buildParameters(from: relevant, specialtyId: specialtyId)
        let hasChronology = !chronologyLines.isEmpty
        guard !parameters.isEmpty || hasChronology else { return nil }

        let overall = classifyOverall(parameters: parameters)
        let narrative = buildNarrative(
            specialtyTitle: specialtyTitle,
            specialtyId: specialtyId,
            parameters: parameters,
            chronologyLines: chronologyLines,
            pendingLines: pendingLines
        )
        let lastDate = (parameters.flatMap(\.points).map(\.date) + values.map(\.date)).max() ?? Date()

        return SpecialtyTrendSnapshot(
            specialtyId: specialtyId,
            specialtyTitle: specialtyTitle,
            parameters: parameters,
            narrativeAnalysis: narrative,
            overallStatus: overall,
            lastUpdated: lastDate
        )
    }

    static func buildGlobalSummary(
        trends: [SpecialtyTrendSnapshot],
        therapyNames: [String],
        nextAppointment: String?
    ) -> ClinicalRecordGlobalSummary {
        let attention = trends.filter {
            $0.overallStatus == .daMonitorare || $0.overallStatus == .attenzione || $0.overallStatus == .peggiorato
        }.count
        let lines = trends.map { t in
            let headline = t.parameters.first?.points.last?.displayValue
                ?? t.parameters.first?.name
                ?? t.narrativeAnalysis.prefix(60).description
            return GlobalStatusLine(
                specialtyTitle: t.specialtyTitle,
                status: t.overallStatus,
                headline: String(headline)
            )
        }
        return ClinicalRecordGlobalSummary(
            monitoredSpecialtiesCount: trends.count,
            attentionCount: attention,
            lastUpdated: trends.map(\.lastUpdated).max() ?? Date(),
            activeTherapyNames: therapyNames,
            nextAppointmentLine: nextAppointment,
            statusLines: lines
        )
    }

    // MARK: - Parameters

    private static func buildParameters(
        from values: [ExtractedMedicalValue],
        specialtyId: String
    ) -> [ParameterTrend] {
        var groups: [String: [ExtractedMedicalValue]] = [:]
        for v in values {
            let key = parameterGroupKey(v, specialtyId: specialtyId)
            groups[key, default: []].append(v)
        }
        return groups.map { name, items in
            let sorted = items.sorted { $0.date < $1.date }
            let points = sorted.map { v -> ParameterTrendPoint in
                ParameterTrendPoint(
                    date: v.date,
                    displayValue: v.textValue ?? v.parameterName,
                    numericValue: v.numericValue ?? v.dimensionMm,
                    source: v.sourceLabel
                )
            }
            let (trend, delta) = computeTrend(points: points, lowerIsBetter: isLowerBetter(name))
            return ParameterTrend(
                name: name,
                points: points,
                trend: trend,
                deltaPercent: delta,
                clinicalNote: clinicalNote(name: name, trend: trend, points: points)
            )
        }.sorted { $0.name < $1.name }
    }

    private static func parameterGroupKey(_ v: ExtractedMedicalValue, specialtyId: String) -> String {
        switch v.kind {
        case .bloodPressure:
            return "Pressione arteriosa"
        case .lesion:
            return v.lesionType.map { "\($0) epatico/organico" } ?? v.parameterName
        case .lab:
            return v.parameterName
        case .heartRate:
            return "Frequenza cardiaca (prova da sforzo)"
        case .stressTest:
            return v.parameterName
        case .weight:
            return "Peso"
        case .generic:
            return v.parameterName
        }
    }

    private static func computeTrend(
        points: [ParameterTrendPoint],
        lowerIsBetter: Bool
    ) -> (ClinicalTrendDirection, Double?) {
        let nums = points.compactMap(\.numericValue)
        guard nums.count >= 2, let first = nums.first, let last = nums.last, first != 0 else {
            return (.stabile, nil)
        }
        let deltaPct = ((last - first) / abs(first)) * 100
        if abs(deltaPct) < 5 { return (.stabile, deltaPct) }
        let increased = last > first
        if lowerIsBetter {
            return increased ? (.inAumento, deltaPct) : (.inDiminuzione, deltaPct)
        }
        return increased ? (.inAumento, deltaPct) : (.inDiminuzione, deltaPct)
    }

    private static func isLowerBetter(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("pressione") || n.contains("ldl") || n.contains("colesterolo")
            || n.contains("glicemia") || n.contains("trigliceridi")
    }

    private static func clinicalNote(
        name: String,
        trend: ClinicalTrendDirection,
        points: [ParameterTrendPoint]
    ) -> String? {
        guard let last = points.last else { return nil }
        let n = name.lowercased()
        if n.contains("pressione") {
            switch trend {
            case .stabile: return "Pressione sostanzialmente stabile nel periodo."
            case .inAumento: return "Possibile incremento pressorio; utile controllo medico."
            case .inDiminuzione: return "Pressione in diminuzione rispetto alle misure precedenti."
            }
        }
        if n.contains("angioma") || n.contains("cist") {
            return trend == .stabile
                ? "Dimensioni stabili nei controlli disponibili."
                : "Variazione dimensionale rilevata; confrontare i referti completi."
        }
        if trend == .stabile { return "Valore stabile nel periodo considerato." }
        return "Andamento da discutere con il medico curante."
    }

    private static func classifyOverall(parameters: [ParameterTrend]) -> ClinicalOverallStatus {
        if parameters.isEmpty { return .daMonitorare }
        if parameters.contains(where: { $0.points.count == 1 && ($0.name.lowercased().contains("angioma") || $0.name.lowercased().contains("cist")) }) {
            return .daMonitorare
        }
        if parameters.contains(where: { $0.trend == .inAumento && isLowerBetter($0.name) }) {
            return .attenzione
        }
        if parameters.allSatisfy({ $0.trend == .stabile }) { return .stabile }
        if parameters.contains(where: { $0.trend == .inDiminuzione && isLowerBetter($0.name) }) {
            return .migliorato
        }
        return .daMonitorare
    }

    // MARK: - Narrative

    private static func buildNarrative(
        specialtyTitle: String,
        specialtyId: String,
        parameters: [ParameterTrend],
        chronologyLines: [String],
        pendingLines: [String]
    ) -> String {
        var parts: [String] = []

        if specialtyId == ClinicalRecordTopicBuilder.TopicId.cardiology.rawValue {
            parts.append(cardiologyNarrative(parameters: parameters, chronologyLines: chronologyLines))
        } else if specialtyId == ClinicalRecordTopicBuilder.TopicId.gastroenterology.rawValue {
            parts.append(gastroNarrative(parameters: parameters, chronologyLines: chronologyLines))
        } else if specialtyId == ClinicalRecordTopicBuilder.TopicId.urology.rawValue {
            parts.append(urologyNarrative(chronologyLines: chronologyLines))
        } else if specialtyId == ClinicalRecordTopicBuilder.TopicId.metabolism.rawValue {
            parts.append(metabolismNarrative(parameters: parameters))
        } else if !parameters.isEmpty {
            parts.append("Per \(specialtyTitle), i parametri monitorati mostrano un andamento \(parameters.first?.trend == .stabile ? "stabile" : "variabile") nel tempo.")
        }

        if !pendingLines.isEmpty {
            parts.append("Prossimi controlli: \(pendingLines.joined(separator: "; ")).")
        }
        return parts.joined(separator: " ")
    }

    private static func cardiologyNarrative(parameters: [ParameterTrend], chronologyLines: [String]) -> String {
        var s = "Quadro cardiologico ricostruito da prove da sforzo, visite, valori lipidici e profilo pressorio disponibili."
        if let bp = parameters.first(where: { $0.name.contains("Pressione") }) {
            if let summary = ClinicalRecordMeasurementSummary.bloodPressureYearSummary(points: bp.points) {
                s += " " + summary
            } else if let last = bp.points.last {
                s += " Ultima pressione documentata: \(last.displayValue)."
            }
        }
        if let ldl = parameters.first(where: { $0.name == "LDL" }) {
            s += " LDL: \(ldl.points.map { "\(Calendar.current.component(.year, from: $0.date)) \($0.displayValue)" }.joined(separator: ", "))."
        }
        let stress = parameters.filter { $0.name.contains("Carico") || $0.name.contains("METS") || $0.name.contains("FC") }
        if !stress.isEmpty {
            let vals = stress.flatMap(\.points).map(\.displayValue).joined(separator: ", ")
            s += " Prova da sforzo: \(vals)."
        }
        if chronologyLines.count >= 2 {
            s += " Sono documentate \(chronologyLines.count) voci cardiologiche nel periodo."
        }
        return s
    }

    private static func gastroNarrative(parameters: [ParameterTrend], chronologyLines: [String]) -> String {
        var s = "Monitoraggio gastroenterologico"
        if let lesion = parameters.first(where: { $0.name.lowercased().contains("angiom") || $0.name.lowercased().contains("cist") }) {
            if lesion.points.count >= 2 {
                let series = lesion.points.map { "\(Calendar.current.component(.year, from: $0.date)): \(Int($0.numericValue ?? 0)) mm" }.joined(separator: " → ")
                s += ": \(lesion.name) con misure \(series) (\(lesion.trend == .stabile ? "stabile" : "da verificare"))."
            } else if let mm = lesion.points.last?.numericValue {
                s += ": \(lesion.name) di \(Int(mm)) mm rilevato; serve un controllo successivo per confermare stabilità."
            }
        } else {
            s += " basato su visite ed esami registrati."
        }
        if chronologyLines.count >= 2 {
            s += " Negli ultimi mesi risultano \(chronologyLines.count) eventi gastroenterologici (visite o esami)."
        }
        return s
    }

    private static func urologyNarrative(chronologyLines: [String]) -> String {
        if chronologyLines.isEmpty {
            return "Nessuna visita o esame urologico strutturato in archivio."
        }
        return "Sono documentate \(chronologyLines.count) visite o esami urologici nel periodo. Confronta le diagnosi nel tempo per confermare stabilità del quadro prostatico e renale."
    }

    private static func metabolismNarrative(parameters: [ParameterTrend]) -> String {
        guard !parameters.isEmpty else { return "Valori ematici non estratti dai referti testuali." }
        let bits = parameters.prefix(4).map { p -> String in
            let last = p.points.last?.displayValue ?? "—"
            let dir = p.trend == .stabile ? "stabile" : (p.trend == .inAumento ? "in aumento" : "in diminuzione")
            return "\(p.name) \(last) (\(dir))"
        }
        return "Parametri ematici: \(bits.joined(separator: "; "))."
    }

    private static func mapsToSpecialty(_ v: ExtractedMedicalValue, specialtyId: String) -> Bool {
        switch specialtyId {
        case ClinicalRecordTopicBuilder.TopicId.cardiology.rawValue:
            return v.kind == .bloodPressure
                || (v.kind == .lab && ["LDL", "HDL", "Colesterolo totale", "Trigliceridi"].contains(v.parameterName))
                || v.kind == .stressTest || v.kind == .heartRate
        case ClinicalRecordTopicBuilder.TopicId.gastroenterology.rawValue:
            return v.kind == .lesion
        case ClinicalRecordTopicBuilder.TopicId.urology.rawValue:
            return v.parameterName == "PSA" || v.kind == .lesion
                || (v.kind == .lab && v.parameterName.lowercased().contains("creatinina"))
        case ClinicalRecordTopicBuilder.TopicId.metabolism.rawValue:
            return v.kind == .lab
        default:
            return false
        }
    }
}
