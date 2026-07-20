//
//  ClinicalRecordTopicBuilder.swift
//  KidBox
//

import Foundation

/// Sezioni cartella clinica per argomento medico (non per tipo dato: visite/esami).
enum ClinicalRecordTopicBuilder {

    enum TopicId: String, CaseIterable {
        case therapies
        case pending
        case bloodPressure
        case cardiology
        case gastroenterology
        case urology
        case metabolism

        /// `String` (non `LocalizedStringKey`): usato con `.uppercased()` e persistito
        /// dentro `ClinicalRecordReportArea` (Codable), quindi passa da NSLocalizedString.
        var title: String {
            switch self {
            case .therapies: return NSLocalizedString("Terapie in corso", comment: "Clinical topic: ongoing therapies")
            case .pending: return NSLocalizedString("Esami in attesa", comment: "Clinical topic: pending exams")
            case .bloodPressure: return NSLocalizedString("Pressione", comment: "Clinical topic: blood pressure")
            case .cardiology: return NSLocalizedString("Cardiologia", comment: "Clinical topic: cardiology")
            case .gastroenterology: return NSLocalizedString("Gastroenterologia", comment: "Clinical topic: gastroenterology")
            case .urology: return NSLocalizedString("Urologia", comment: "Clinical topic: urology")
            case .metabolism: return NSLocalizedString("Glicemia e metabolismo", comment: "Clinical topic: metabolism")
            }
        }

        var systemImage: String {
            switch self {
            case .therapies: return "pills.fill"
            case .pending: return "calendar.badge.clock"
            case .bloodPressure: return "waveform.path.ecg"
            case .cardiology: return "heart.fill"
            case .gastroenterology: return "list.clipboard.fill"
            case .urology: return "cross.case.fill"
            case .metabolism: return "drop.fill"
            }
        }

        var tintHex: UInt32 {
            switch self {
            case .therapies: return 0x9573D9
            case .pending: return 0xD98C59
            case .bloodPressure: return 0x5996D9
            case .cardiology: return 0xE85A5A
            case .gastroenterology: return 0x66BFA6
            case .urology: return 0x40A6BF
            case .metabolism: return 0xF38D73
            }
        }
    }

    struct Input {
        let subjectName: String
        let birthDate: Date?
        let residence: String?
        let profile: KBPediatricProfile?
        let healthSnapshot: KBHealthImportSnapshot?
        let healthSourceLabel: String
        let treatments: [KBTreatment]
        let vaccines: [KBVaccine]
        let visits: [KBMedicalVisit]
        let exams: [KBMedicalExam]
        var documents: [KBDocument] = []
        var extractedValues: [ExtractedMedicalValue] = []
    }

    static func build(input: Input) -> ClinicalRecordReport {
        var extracted = input.extractedValues
        if extracted.isEmpty {
            extracted = ClinicalRecordValueIndex.extractAll(
                exams: input.exams,
                visits: input.visits,
                documents: input.documents
            )
        }
        appendHealthBloodPressure(input.healthSnapshot, label: input.healthSourceLabel, into: &extracted)
        appendHealthCardiovascular(input.healthSnapshot, label: input.healthSourceLabel, into: &extracted)

        let ctx = ClinicalRecordCleanDocumentBuilder.Context(input: input, extracted: extracted)
        let doc = ClinicalRecordCleanDocumentBuilder.buildDocument(ctx)
        let ui = ClinicalRecordCleanDocumentBuilder.buildUIAreas(ctx)
        var headerLines: [String] = []
        for line in doc where !line.hasPrefix("---") {
            headerLines.append(line)
        }

        let report = ClinicalRecordReport(
            generatedAt: Date(),
            source: .native,
            subjectName: input.subjectName,
            headerLines: Array(headerLines),
            areas: ui.areas,
            fullDocumentLines: doc,
            globalSummary: ui.global,
            specialtyTrends: ui.trends
        )
        return ClinicalRecordTextSanitizer.sanitizeReport(report)
    }

    private static func appendHealthBloodPressure(
        _ health: KBHealthImportSnapshot?,
        label: String,
        into extracted: inout [ExtractedMedicalValue]
    ) {
        guard let h = health, let sys = h.bloodPressureSystolic, let dia = h.bloodPressureDiastolic else { return }
        extracted.append(ExtractedMedicalValue(
            kind: .bloodPressure,
            parameterName: "Pressione arteriosa",
            numericValue: sys,
            textValue: String(format: "%.0f/%.0f mmHg", sys, dia),
            unit: "mmHg",
            systolic: Int(sys),
            diastolic: Int(dia),
            lesionType: nil,
            dimensionMm: nil,
            date: h.bloodPressureMeasuredAt ?? h.syncedAt,
            sourceId: "health:\(label)",
            sourceLabel: label
        ))
    }

    private static func appendHealthCardiovascular(
        _ health: KBHealthImportSnapshot?,
        label: String,
        into extracted: inout [ExtractedMedicalValue]
    ) {
        guard let h = health else { return }
        let date = h.heartRateMeasuredAt ?? h.syncedAt
        if let hr = h.heartRateBpm {
            extracted.append(ExtractedMedicalValue(
                kind: .heartRate,
                parameterName: "Frequenza cardiaca",
                numericValue: hr,
                textValue: String(format: "%.0f bpm", hr),
                unit: "bpm",
                systolic: nil,
                diastolic: nil,
                lesionType: nil,
                dimensionMm: nil,
                date: date,
                sourceId: "health:hr:\(label)",
                sourceLabel: label
            ))
        }
        if let rhr = h.restingHeartRateBpm {
            extracted.append(ExtractedMedicalValue(
                kind: .heartRate,
                parameterName: "Frequenza a riposo",
                numericValue: rhr,
                textValue: String(format: "%.0f bpm", rhr),
                unit: "bpm",
                systolic: nil,
                diastolic: nil,
                lesionType: nil,
                dimensionMm: nil,
                date: h.restingHeartRateMeasuredAt ?? h.syncedAt,
                sourceId: "health:rhr:\(label)",
                sourceLabel: label
            ))
        }
    }

    private static func topicBlock(
        from trend: SpecialtyTrendSnapshot,
        chronology: [String]
    ) -> TopicBlock {
        var lines = ["---", trend.specialtyTitle.uppercased(), "", "ANALISI ANDAMENTO:", trend.narrativeAnalysis, ""]
        if !trend.parameters.isEmpty {
            lines.append("PARAMETRI MONITORATI:")
            for p in trend.parameters {
                let series = p.points.map { pt in
                    "\(formatShort(pt.date)): \(pt.displayValue)"
                }.joined(separator: " → ")
                let delta = p.deltaPercent.map { String(format: "%.0f%%", $0) } ?? "—"
                lines.append("• \(p.name): \(series) (trend: \(p.trend.rawValue), Δ \(delta))")
            }
            lines.append("")
        }
        if !chronology.isEmpty {
            lines.append("VISITE E ESAMI:")
            lines.append(contentsOf: chronology.prefix(12))
        }
        let trendText = trend.parameters.map { p in
            let series = p.points.map { "\(Calendar.current.component(.year, from: $0.date)): \($0.displayValue)" }.joined(separator: " → ")
            return "• \(p.name): \(series)"
        }.joined(separator: "\n")

        let bullets = trend.parameters.flatMap(\.points).suffix(3).map { "• \($0.displayValue) (\(formatShort($0.date)))" }
        let area = ClinicalRecordReportArea(
            id: trend.specialtyId,
            title: trend.specialtyTitle,
            summary: trend.parameters.last?.points.last?.displayValue ?? trend.narrativeAnalysis.prefix(60).description,
            narrative: lines.joined(separator: "\n"),
            trendNarrative: trendText.isEmpty ? nil : trendText,
            bullets: Array(bullets),
            overallStatus: trend.overallStatus,
            analisiNarrativa: trend.narrativeAnalysis,
            parameters: trend.parameters
        )
        return TopicBlock(lines: lines, area: area)
    }

    private static func globalSummaryLines(
        _ global: ClinicalRecordGlobalSummary,
        subjectName: String
    ) -> [String] {
        var lines = ["", "SINTESI CLINICA GLOBALE", "━━━━━━━━━━━━━━━━━━━━━━━━"]
        for row in global.statusLines {
            lines.append("\(row.status.emoji) \(row.specialtyTitle) — \(row.status.badgeLabel): \(row.headline)")
        }
        if !global.activeTherapyNames.isEmpty {
            lines.append("TERAPIE ATTIVE: \(global.activeTherapyNames.joined(separator: ", "))")
        }
        if let next = global.nextAppointmentLine {
            lines.append("PROSSIMI ESAMI: \(next)")
        }
        lines.append("Generata per \(subjectName)")
        return lines
    }

    private static func chronologyLines(
        topic: TopicId,
        visits: [KBMedicalVisit],
        exams: [KBMedicalExam]
    ) -> [String] {
        var lines: [String] = []
        let filteredVisits = visits.filter { v in
            let t = (v.reason + " " + (v.diagnosis ?? "") + " " + (v.notes ?? "")).lowercased()
            return matchesTopic(topic, text: t)
        }.sorted { $0.date < $1.date }
        for v in filteredVisits {
            lines.append(visitLine(v))
        }
        let filteredExams = exams.filter { e in
            matchesTopic(topic, text: (e.name + " " + (e.resultText ?? "")).lowercased())
        }.sorted { ($0.resultDate ?? $0.updatedAt) < ($1.resultDate ?? $1.updatedAt) }
        for e in filteredExams {
            lines.append("• \(formatDate(e.resultDate ?? e.updatedAt)) — \(e.name)")
        }
        return lines
    }

    private static func matchesTopic(_ topic: TopicId, text: String) -> Bool {
        switch topic {
        case .bloodPressure: return text.contains("pressione") || text.contains("mmhg") || text.contains("pa ")
        case .cardiology: return matchesCardiology(text)
        case .gastroenterology: return matchesGastro(text)
        case .urology: return matchesUrology(text)
        case .metabolism: return text.contains("glicemia") || text.contains("colester") || text.contains("emocromo") || text.contains("sangue")
        default: return false
        }
    }

    private static func formatShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.dateFormat = "MMM yyyy"
        return f.string(from: date)
    }

    // MARK: - Header & therapies

    private static func buildHeader(_ input: Input) -> (lines: [String], area: ClinicalRecordReportArea) {
        var lines: [String] = ["CARTELLA CLINICA — \(input.subjectName.uppercased())"]
        var bullets: [String] = []
        if let birth = input.birthDate {
            let age = KBHealthAgeFormatting.ageDescription(from: birth)
            let d = formatDate(birth)
            lines.append("Data di nascita: \(d)\(age.isEmpty ? "" : " (\(age))")")
            bullets.append("Nato il \(d)")
        }
        if let res = input.residence, !res.isEmpty {
            lines.append("Residenza: \(res)")
            bullets.append(res)
        }
        profileLine(input.profile).map { lines.append($0) }
        let area = ClinicalRecordReportArea(
            id: "header",
            title: "Intestazione",
            summary: bullets.first ?? input.subjectName,
            narrative: lines.joined(separator: "\n"),
            trendNarrative: nil,
            bullets: bullets
        )
        return (lines, area)
    }

    private static func buildTherapies(_ treatments: [KBTreatment]) -> (lines: [String], area: ClinicalRecordReportArea) {
        var lines = ["---", "TERAPIE IN CORSO", ""]
        var bullets: [String] = []
        if treatments.isEmpty {
            lines.append("Nessuna terapia farmacologica attiva registrata.")
        } else {
            for t in treatments {
                var line = "• \(t.drugName) — \(t.dosageValue, default: "%.0f") \(t.dosageUnit), \(t.frequencyDisplayLabel)"
                if t.isLongTerm { line += " (lungo termine)" }
                else if let end = t.endDate { line += " (fine prevista: \(formatDate(end)))" }
                if let notes = t.notes, !notes.isEmpty { line += " — \(notes)" }
                lines.append(line)
                bullets.append(line)
            }
        }
        let area = ClinicalRecordReportArea(
            id: TopicId.therapies.rawValue,
            title: TopicId.therapies.title,
            summary: treatments.isEmpty ? "Nessuna cura" : "\(treatments.count) in corso",
            narrative: lines.joined(separator: "\n"),
            trendNarrative: nil,
            bullets: bullets
        )
        return (lines, area)
    }

    private static func buildPending(_ exams: [KBMedicalExam]) -> (lines: [String], area: ClinicalRecordReportArea) {
        let pending = exams.filter { $0.status == .pending || $0.status == .booked }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
        guard !pending.isEmpty else {
            return ([], ClinicalRecordReportArea(
                id: TopicId.pending.rawValue, title: TopicId.pending.title,
                summary: "Nessuno", narrative: "", trendNarrative: nil, bullets: []))
        }
        var lines = ["---", "ESAMI IN ATTESA O PRENOTATI", ""]
        var bullets: [String] = []
        for (i, e) in pending.enumerated() {
            var line = "\(i + 1). \(e.name.uppercased())"
            if let d = e.deadline { line += " — \(formatDate(d))" }
            if e.isUrgent { line += " [urgente]" }
            lines.append(line)
            bullets.append(line)
        }
        let area = ClinicalRecordReportArea(
            id: TopicId.pending.rawValue,
            title: TopicId.pending.title,
            summary: "\(pending.count) da eseguire",
            narrative: lines.joined(separator: "\n"),
            trendNarrative: nil,
            bullets: bullets
        )
        return (lines, area)
    }

    // MARK: - Topics

    private struct TopicBlock {
        let lines: [String]
        let area: ClinicalRecordReportArea
        var hasContent: Bool { !area.bullets.isEmpty || !area.narrative.isEmpty }
    }

    private static func buildBloodPressure(
        _ health: KBHealthImportSnapshot?,
        label: String,
        visits: [KBMedicalVisit],
        exams: [KBMedicalExam]
    ) -> TopicBlock {
        var points: [(Date, String, String)] = []
        if let h = health, let sys = h.bloodPressureSystolic, let dia = h.bloodPressureDiastolic {
            let date = h.bloodPressureMeasuredAt ?? h.syncedAt
            points.append((date, String(format: "%.0f/%.0f mmHg", sys, dia), label))
        }
        for e in exams {
            extractBloodPressure(from: e.resultText ?? "", examName: e.name, date: e.resultDate ?? e.updatedAt, into: &points)
        }
        for v in visits {
            let blob = [v.diagnosis, v.recommendations, v.notes, v.reason].compactMap { $0 }.joined(separator: " ")
            extractBloodPressure(from: blob, examName: "Visita", date: v.date, into: &points)
        }
        points.sort { $0.0 < $1.0 }

        var narrative: [String] = ["Monitoraggio pressione arteriosa"]
        var bullets: [String] = []
        if points.isEmpty {
            narrative.append("Nessuna misura registrata in app Salute o nei referti.")
        } else {
            narrative.append("")
            for p in points.suffix(8) {
                let line = "• \(formatDate(p.0)) — \(p.1) (\(p.2))"
                narrative.append(line)
                bullets.append(line)
            }
        }

        let trend = bloodPressureTrend(points)
        let consideration = bloodPressureConsideration(points)
        if let consideration {
            narrative.append("")
            narrative.append("Considerazioni: \(consideration)")
        }

        let area = ClinicalRecordReportArea(
            id: TopicId.bloodPressure.rawValue,
            title: TopicId.bloodPressure.title,
            summary: points.last.map { $0.1 } ?? "Dati non disponibili",
            narrative: narrative.joined(separator: "\n"),
            trendNarrative: trend,
            bullets: Array(bullets.suffix(3))
        )
        return TopicBlock(lines: ["---", TopicId.bloodPressure.title.uppercased(), ""] + narrative, area: area)
    }

    private static func buildCardiology(
        _ visits: [KBMedicalVisit],
        _ exams: [KBMedicalExam],
        trends: [LabMetricFamily: [LabMeasurementPoint]]
    ) -> TopicBlock {
        let cardioVisits = visits.filter { matchesCardiology($0.reason + " " + ($0.diagnosis ?? "") + " " + ($0.notes ?? "")) }
        let cardioExams = exams.filter { matchesCardiology($0.name + " " + ($0.resultText ?? "")) }

        var narrative: [String] = []
        var bullets: [String] = []

        if let lipids = trends[.lipids], !lipids.isEmpty,
           let trendText = ClinicalRecordLabTrends.narrative(for: .lipids, points: lipids) {
            narrative.append(trendText)
            narrative.append("")
        }

        if !cardioExams.isEmpty {
            narrative.append("Esami cardiologici:")
            for e in cardioExams.sorted(by: { ($0.resultDate ?? $0.updatedAt) > ($1.resultDate ?? $1.updatedAt) }).prefix(6) {
                narrative.append("")
                narrative.append("\(e.name) (\(formatDate(e.resultDate ?? e.updatedAt)))")
                bullets.append("\(e.name) — \(formatDate(e.resultDate ?? e.updatedAt))")
                appendResultExcerpt(e.resultText, to: &narrative)
            }
        }

        if !cardioVisits.isEmpty {
            narrative.append("")
            narrative.append("Visite nel tempo:")
            for v in cardioVisits.sorted(by: { $0.date < $1.date }) {
                let line = visitLine(v)
                narrative.append(line)
                bullets.append(clip(line))
            }
        }

        let trendParts = [
            ClinicalRecordLabTrends.narrative(for: .cardiac, points: trends[.cardiac] ?? []),
            ClinicalRecordLabTrends.narrative(for: .lipids, points: trends[.lipids] ?? []),
        ].compactMap { $0 }
        let trend = trendParts.isEmpty ? nil : trendParts.joined(separator: "\n\n")

        let consideration = cardioConsideration(exams: cardioExams, lipids: trends[.lipids] ?? [])
        if let consideration {
            narrative.append("")
            narrative.append("Considerazioni: \(consideration)")
        }

        let area = ClinicalRecordReportArea(
            id: TopicId.cardiology.rawValue,
            title: TopicId.cardiology.title,
            summary: summaryForTopic(examCount: cardioExams.count, visitCount: cardioVisits.count),
            narrative: narrative.joined(separator: "\n"),
            trendNarrative: trend,
            bullets: Array(bullets.prefix(5))
        )
        return TopicBlock(lines: sectionDocLines(area), area: area)
    }

    private static func buildGastroenterology(
        _ visits: [KBMedicalVisit],
        _ exams: [KBMedicalExam],
        trends: [LabMetricFamily: [LabMeasurementPoint]]
    ) -> TopicBlock {
        let gastroVisits = visits.filter { matchesGastro($0.reason + " " + ($0.diagnosis ?? "")) }
        let gastroExams = exams.filter { matchesGastro($0.name + " " + ($0.resultText ?? "")) }

        var narrative: [String] = []
        var bullets: [String] = []

        if let lk = trends[.liverKidney], !lk.isEmpty,
           let t = ClinicalRecordLabTrends.narrative(for: .liverKidney, points: lk) {
            narrative.append(t)
            narrative.append("")
        }

        if !gastroExams.isEmpty {
            narrative.append("Esami e referti:")
            for e in gastroExams.sorted(by: { ($0.resultDate ?? $0.updatedAt) > ($1.resultDate ?? $1.updatedAt) }).prefix(6) {
                narrative.append("")
                narrative.append("\(e.name) (\(formatDate(e.resultDate ?? e.updatedAt)))")
                bullets.append("\(e.name)")
                appendResultExcerpt(e.resultText, to: &narrative)
            }
        }
        if !gastroVisits.isEmpty {
            narrative.append("")
            narrative.append("Visite nel tempo:")
            for v in gastroVisits.sorted(by: { $0.date < $1.date }) {
                narrative.append(visitLine(v))
                bullets.append(clip(visitLine(v)))
            }
        }

        let area = ClinicalRecordReportArea(
            id: TopicId.gastroenterology.rawValue,
            title: TopicId.gastroenterology.title,
            summary: summaryForTopic(examCount: gastroExams.count, visitCount: gastroVisits.count),
            narrative: narrative.joined(separator: "\n"),
            trendNarrative: ClinicalRecordLabTrends.narrative(for: .liverKidney, points: trends[.liverKidney] ?? []),
            bullets: Array(bullets.prefix(5))
        )
        return TopicBlock(lines: sectionDocLines(area), area: area)
    }

    private static func buildUrology(
        _ visits: [KBMedicalVisit],
        _ exams: [KBMedicalExam]
    ) -> TopicBlock {
        let uroVisits = visits.filter { matchesUrology($0.reason + " " + ($0.diagnosis ?? "")) }
        let uroExams = exams.filter { matchesUrology($0.name + " " + ($0.resultText ?? "")) }

        var narrative: [String] = []
        var bullets: [String] = []

        if !uroExams.isEmpty {
            narrative.append("Esami urologici:")
            for e in uroExams.sorted(by: { ($0.resultDate ?? $0.updatedAt) > ($1.resultDate ?? $1.updatedAt) }).prefix(6) {
                narrative.append("")
                narrative.append("\(e.name) (\(formatDate(e.resultDate ?? e.updatedAt)))")
                bullets.append(e.name)
                appendResultExcerpt(e.resultText, to: &narrative)
            }
        }
        if !uroVisits.isEmpty {
            narrative.append("")
            narrative.append("Visite e controlli nel tempo:")
            for v in uroVisits.sorted(by: { $0.date < $1.date }) {
                let line = visitLine(v)
                narrative.append(line)
                bullets.append(clip(line))
            }
        }

        let area = ClinicalRecordReportArea(
            id: TopicId.urology.rawValue,
            title: TopicId.urology.title,
            summary: summaryForTopic(examCount: uroExams.count, visitCount: uroVisits.count),
            narrative: narrative.joined(separator: "\n"),
            trendNarrative: uroVisits.count >= 2
                ? "Confronta le visite urologiche per evidenziare stabilità o nuovi sintomi nel periodo."
                : nil,
            bullets: Array(bullets.prefix(5))
        )
        return TopicBlock(lines: sectionDocLines(area), area: area)
    }

    private static func buildMetabolism(
        _ exams: [KBMedicalExam],
        trends: [LabMetricFamily: [LabMeasurementPoint]]
    ) -> TopicBlock {
        let glycemic = trends[.glycemic] ?? []
        let blood = trends[.bloodCount] ?? []
        guard !glycemic.isEmpty || !blood.isEmpty else {
            return TopicBlock(lines: [], area: ClinicalRecordReportArea(
                id: TopicId.metabolism.rawValue, title: TopicId.metabolism.title,
                summary: "", narrative: "", trendNarrative: nil, bullets: []))
        }

        var narrative: [String] = []
        if let g = ClinicalRecordLabTrends.narrative(for: .glycemic, points: glycemic) { narrative.append(g) }
        if let b = ClinicalRecordLabTrends.narrative(for: .bloodCount, points: blood) {
            if !narrative.isEmpty { narrative.append("") }
            narrative.append(b)
        }

        let bullets = (glycemic + blood).suffix(4).map { p in
            "• \(p.metricLabel): \(p.value)\(p.unit.map { " \($0)" } ?? "") (\(p.year))"
        }

        let area = ClinicalRecordReportArea(
            id: TopicId.metabolism.rawValue,
            title: TopicId.metabolism.title,
            summary: "Parametri ematici monitorati",
            narrative: narrative.joined(separator: "\n"),
            trendNarrative: narrative.joined(separator: "\n\n"),
            bullets: Array(bullets)
        )
        return TopicBlock(lines: sectionDocLines(area), area: area)
    }

    // MARK: - Classification

    private static func matchesCardiology(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("cardio") || t.contains("cuore") || t.contains("colester") || t.contains("ldl") || t.contains("hdl")
            || t.contains("sforzo") || t.contains("ergometria") || t.contains("ecocardio") || t.contains("coronarografia")
            || t.contains("ischem") || t.contains("aritmia")
    }

    private static func matchesGastro(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("gast") || t.contains("colon") || t.contains("epat") || t.contains("milza")
            || t.contains("addome") || t.contains("ernia iatale") || t.contains("egds") || t.contains("gastroscop")
    }

    private static func matchesUrology(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("prostata") || t.contains("ren") || t.contains("urolog") || t.contains("inguin")
            || t.contains("varicocele") || t.contains("psa")
    }

    // MARK: - Helpers

    private static func sectionDocLines(_ area: ClinicalRecordReportArea) -> [String] {
        guard area.hasContent else { return [] }
        return ["---", area.title.uppercased(), "", area.narrative]
    }

    private static func visitLine(_ v: KBMedicalVisit) -> String {
        var line = "• \(formatDate(v.date)) — \(v.reason.isEmpty ? "Visita" : v.reason)"
        if let d = v.diagnosis, !d.isEmpty { line += "\n  Diagnosi: \(clip(d))" }
        if let r = v.recommendations, !r.isEmpty { line += "\n  Indicazioni: \(clip(r))" }
        return line
    }

    private static func appendResultExcerpt(_ resultText: String?, to narrative: inout [String]) {
        guard let r = resultText, !r.isEmpty else { return }
        let clean = HealthAiDocumentText.prepareExtractedTextForAI(r, maxChars: 700)
        for row in clean.split(separator: "\n").prefix(8) {
            let s = String(row).trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { narrative.append("  • \(s)") }
        }
    }

    private static func summaryForTopic(examCount: Int, visitCount: Int) -> String {
        switch (examCount, visitCount) {
        case (0, 0): return "Nessun dato in archivio"
        case (let e, 0): return "\(e) esami documentati"
        case (0, let v): return "\(v) visite nel tempo"
        case (let e, let v): return "\(e) esami · \(v) visite"
        }
    }

    private static func profileLine(_ profile: KBPediatricProfile?) -> String? {
        guard let g = profile?.bloodGroup, !g.isEmpty else { return nil }
        return "Gruppo sanguigno: \(g)"
    }

    private static func extractBloodPressure(
        from text: String,
        examName: String,
        date: Date,
        into points: inout [(Date, String, String)]
    ) {
        let pattern = #"(?i)(?:PA|pressione)[^\d]{0,20}(\d{2,3})\s*/\s*(\d{2,3})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 3,
                  let r1 = Range(match.range(at: 1), in: text),
                  let r2 = Range(match.range(at: 2), in: text) else { return }
            let sys = String(text[r1])
            let dia = String(text[r2])
            points.append((date, "\(sys)/\(dia) mmHg", examName))
        }
    }

    private static func bloodPressureTrend(_ points: [(Date, String, String)]) -> String? {
        guard points.count >= 2 else {
            return points.last.map { "Ultima misura: \($0.1) (\(formatDate($0.0)))" }
        }
        let series = points.map { "\(Calendar.current.component(.year, from: $0.0)): \($0.1)" }.joined(separator: " → ")
        return "Andamento pressione: \(series)"
    }

    private static func bloodPressureConsideration(_ points: [(Date, String, String)]) -> String? {
        guard let last = points.last?.1 else { return nil }
        let nums = last.split(separator: "/").compactMap { Double($0.filter { $0.isNumber }) }
        guard nums.count >= 2 else { return "Verifica le misure con il medico curante." }
        let sys = nums[0]
        if sys >= 140 { return "L'ultima sistolica risulta elevata; utile monitoraggio e valutazione medica." }
        if sys < 90 { return "Pressione bassa nell'ultima rilevazione; se sintomatica, consultare il medico." }
        return "Ultima pressione nei limiti usuali; continua il monitoraggio periodico."
    }

    private static func cardioConsideration(exams: [KBMedicalExam], lipids: [LabMeasurementPoint]) -> String? {
        if exams.contains(where: { ($0.resultText ?? "").lowercased().contains("negativ") && $0.name.lowercased().contains("sforzo") }) {
            return "Prova da sforzo negativa per ischemia nei referti disponibili."
        }
        if let hdl = lipids.last(where: { $0.metricLabel == "HDL" }), let v = Double(hdl.value), v < 35 {
            return "HDL sotto la soglia consigliata: utile discussione con il cardiologo sul profilo lipidico."
        }
        return nil
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }

    private static func clip(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 120 { return t }
        return String(t.prefix(119)) + "…"
    }
}

private extension ClinicalRecordReportArea {
    var hasContent: Bool { !bullets.isEmpty || !narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
