//
//  ClinicalRecordCleanDocumentBuilder.swift
//  KidBox
//

import Foundation

/// Documento cartella clinica in formato pulito (intestazione, patologie per area, esami, andamenti sintetici).
enum ClinicalRecordCleanDocumentBuilder {

    struct Context {
        let input: ClinicalRecordTopicBuilder.Input
        let extracted: [ExtractedMedicalValue]
    }

    static func buildDocument(_ ctx: Context) -> [String] {
        var lines: [String] = []
        lines += buildHeader(ctx.input)
        if let health = ctx.input.healthSnapshot {
            let wearableLines = ClinicalRecordAppleHealthNarrative.documentLines(
                snapshot: health,
                sourceLabel: ctx.input.healthSourceLabel,
                birthDate: ctx.input.birthDate,
                visits: ctx.input.visits
            )
            if !wearableLines.isEmpty {
                lines += [""]
                lines += wearableLines
            }
        }
        lines += [""]
        lines += buildTherapiesSection(ctx.input.treatments)
        lines += [""]
        lines += buildPathologiesSection(ctx)
        let pending = buildPendingSection(ctx.input.exams)
        if !pending.isEmpty {
            lines += [""]
            lines += pending
        }
        let recent = buildRecentExamsSection(ctx)
        if !recent.isEmpty {
            lines += [""]
            lines += recent
        }
        return ClinicalRecordTextSanitizer.sanitizeLines(lines)
    }

    /// Aree UI allineate al documento (tap → dettaglio con trend).
    static func buildUIAreas(_ ctx: Context) -> (
        areas: [ClinicalRecordReportArea],
        trends: [SpecialtyTrendSnapshot],
        global: ClinicalRecordGlobalSummary
    ) {
        var areas: [ClinicalRecordReportArea] = []
        var trends: [SpecialtyTrendSnapshot] = []

        let header = buildHeaderArea(ctx.input)
        areas.append(header)

        if let health = ctx.input.healthSnapshot,
           let appleArea = ClinicalRecordAppleHealthNarrative.reportArea(
               snapshot: health,
               sourceLabel: ctx.input.healthSourceLabel,
               birthDate: ctx.input.birthDate,
               visits: ctx.input.visits
           ) {
            areas.append(appleArea)
        }

        let therapies = therapyArea(ctx.input.treatments)
        areas.append(therapies)

        let path = pathologyArea(ctx)
        if !path.bullets.isEmpty || !path.narrative.isEmpty { areas.append(path) }

        let pending = pendingArea(ctx.input.exams)
        if !pending.bullets.isEmpty { areas.append(pending) }

        for topic in ClinicalRecordSectionPolicy.dynamicSpecialtyTopics {
            let chronology = chronologyFor(topic, ctx: ctx)
            guard let trend = TrendAnalyzer.buildSpecialtyTrend(
                specialtyId: topic.rawValue,
                specialtyTitle: topic.title,
                values: ctx.extracted,
                chronologyLines: chronology
            ) else { continue }
            trends.append(trend)
            areas.append(areaFromTrend(trend, chronology: chronology, ctx: ctx))
        }

        let recent = recentExamsArea(ctx)
        if !recent.bullets.isEmpty || !recent.narrative.isEmpty { areas.append(recent) }

        let therapyNames = ctx.input.treatments.map(\.drugName)
        let nextPending = ctx.input.exams
            .filter { $0.status == .pending || $0.status == .booked }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            .first
        let nextLine = nextPending.map { e in
            e.deadline.map { "\(e.name) — \(formatDate($0))" } ?? e.name
        }
        let global = TrendAnalyzer.buildGlobalSummary(trends: trends, therapyNames: therapyNames, nextAppointment: nextLine)
        return (areas, trends, global)
    }

    // MARK: - Document sections

    private static func buildHeader(_ input: ClinicalRecordTopicBuilder.Input) -> [String] {
        var lines = ["CARTELLA CLINICA — \(input.subjectName.uppercased())"]
        if let birth = input.birthDate {
            let age = KBHealthAgeFormatting.ageDescription(from: birth)
            lines.append("Data di nascita: \(formatDate(birth))\(age.isEmpty ? "" : " (\(age))")")
        }
        if let res = input.residence, !res.isEmpty {
            lines.append("Residenza: \(res)")
        }
        if let g = input.profile?.bloodGroup, !g.isEmpty {
            lines.append("Gruppo sanguigno: \(g)")
        }
        return lines
    }

    private static func buildTherapiesSection(_ treatments: [KBTreatment]) -> [String] {
        var lines = ["---", "STATO ATTUALE DELLE CURE", ""]
        if treatments.isEmpty {
            lines.append("Nessuna terapia farmacologica attiva registrata.")
            return lines
        }
        lines.append("TERAPIE IN CORSO (\(treatments.count))")
        lines.append("")
        for t in treatments {
            var line = "• \(t.drugName) — \(t.dosageValue, default: "%.0f") \(t.dosageUnit), \(t.frequencyDisplayLabel)"
            if t.isLongTerm {
                line += " (terapia a lungo termine"
                if let notes = t.notes, !notes.isEmpty { line += " per \(notes)" }
                line += ")"
            } else if let end = t.endDate {
                line += " (termine previsto: \(formatDate(end)))"
            } else if let notes = t.notes, !notes.isEmpty {
                line += " — \(notes)"
            }
            lines.append(line)
        }
        return lines
    }

    private static func buildPathologiesSection(_ ctx: Context) -> [String] {
        var buckets: [String: [String]] = [
            "Cardiovascolare": [],
            "Gastroenterologica": [],
            "Urologica": [],
            "Altro": [],
        ]

        func classify(_ text: String) -> String {
            let t = text.lowercased()
            if t.contains("cuore") || t.contains("cardio") || t.contains("colester") || t.contains("ischem")
                || t.contains("coronar") || t.contains("sforzo") || t.contains("ecocardio") || t.contains("pressione") {
                return "Cardiovascolare"
            }
            if t.contains("gast") || t.contains("colon") || t.contains("epat") || t.contains("milza")
                || t.contains("ernia iatale") || t.contains("addome") || t.contains("angiom") || t.contains("agiom") {
                return "Gastroenterologica"
            }
            if t.contains("prostata") || t.contains("ren") || t.contains("urolog") || t.contains("inguin")
                || t.contains("varicocele") || t.contains("cisti ren") {
                return "Urologica"
            }
            return "Altro"
        }

        func addUnique(_ bucket: String, _ line: String) {
            guard !line.isEmpty, !(buckets[bucket]?.contains(line) ?? false) else { return }
            buckets[bucket, default: []].append(line)
        }

        for t in ctx.input.treatments where t.isLongTerm {
            let line = "• Terapia: \(t.drugName)\(t.notes.map { " — \($0)" } ?? "")"
            addUnique(classify(t.drugName + " " + (t.notes ?? "")), line)
        }

        for v in ctx.input.visits {
            let dateStr = formatMonthYear(v.date)
            for part in [v.diagnosis, v.reason, v.recommendations].compactMap({ $0 }).filter({ !$0.isEmpty }) {
                let line = "• \(clip(part)) (\(dateStr))"
                addUnique(classify(part), line)
            }
        }

        for e in ctx.input.exams where e.status == .resultIn || e.status == .done {
            let text = e.name + " " + (e.resultText ?? "")
            let dateStr = formatMonthYear(e.resultDate ?? e.updatedAt)
            let lower = text.lowercased()
            if lower.contains("negativ") || lower.contains("normale") || lower.contains("nei limiti") || lower.contains("stabile") {
                let line = "• \(e.name): esito nei limiti (\(dateStr))"
                addUnique(classify(text), line)
            }
            for lesion in ctx.extracted.filter({ $0.kind == .lesion && ($0.sourceId == "exam:\(e.id)" || $0.sourceLabel == e.name) }) {
                let line = "• \(lesion.lesionType ?? "Lesione") \(Int(lesion.dimensionMm ?? 0)) mm (\(dateStr))"
                addUnique("Gastroenterologica", line)
            }
        }

        var lines = ["---", "PRINCIPALI PATOLOGIE E CONDIZIONI", ""]
        var any = false
        for title in ["Cardiovascolare", "Gastroenterologica", "Urologica", "Altro"] {
            guard let items = buckets[title], !items.isEmpty else { continue }
            any = true
            lines.append(title)
            lines.append("")
            lines += items.prefix(8)
            lines.append("")
        }
        if !any {
            lines.append("Nessuna condizione strutturata dalle visite e dai referti in archivio.")
        }
        return lines
    }

    private static func buildPendingSection(_ exams: [KBMedicalExam]) -> [String] {
        let pending = exams.filter { $0.status == .pending || $0.status == .booked }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
        guard !pending.isEmpty else { return [] }
        var lines = ["---", "ESAMI IN ATTESA/PRENOTATI (\(pending.count))", ""]
        for (i, e) in pending.enumerated() {
            var line = "\(i + 1). \(e.name.uppercased())"
            if let d = e.deadline { line += " — \(formatDate(d))" }
            if let prep = e.preparation, !prep.isEmpty { line += " (\(clip(prep)))" }
            lines.append(line)
        }
        return lines
    }

    private static func buildRecentExamsSection(_ ctx: Context) -> [String] {
        let withResult = ctx.input.exams
            .filter { ($0.resultText?.isEmpty == false) || $0.status == .resultIn }
            .sorted { ($0.resultDate ?? $0.updatedAt) > ($1.resultDate ?? $1.updatedAt) }

        guard !withResult.isEmpty else { return [] }

        var lines = ["---", "ULTIMI ESAMI SIGNIFICATIVI", ""]

        let labExams = withResult.filter { isLabLike($0) }
        if !labExams.isEmpty {
            lines += buildBloodWorkBlock(labExams, extracted: ctx.extracted)
            lines.append("")
        }

        let nonLab = withResult.filter { !isLabLike($0) }
        for e in nonLab.prefix(8) {
            lines.append("\(e.name) (\(formatMonthYear(e.resultDate ?? e.updatedAt)))")
            lines.append("")
            lines += bulletLinesFromExam(e, extracted: ctx.extracted)
            lines.append("")
        }

        return lines
    }

    private static func buildBloodWorkBlock(_ exams: [KBMedicalExam], extracted: [ExtractedMedicalValue]) -> [String] {
        let latest = exams.first
        let date = latest?.resultDate ?? latest?.updatedAt ?? Date()
        var lines = ["Esami del sangue (\(formatMonthYear(date))) — più recenti", ""]

        let labLabels = ["Colesterolo totale", "LDL", "HDL", "Trigliceridi", "Glicemia", "GOT", "GPT", "PSA", "Creatinina", "Emoglobina"]
        for label in labLabels {
            let points = extracted.filter { $0.kind == .lab && $0.parameterName == label }.sorted { $0.date < $1.date }
            guard let last = points.last else { continue }
            let qual = labQualitative(label: label, value: last.numericValue ?? 0)
            lines.append("• \(label): \(last.textValue ?? formatNum(last.numericValue ?? 0)) (\(qual))")
        }

        if let trendBlock = compactLabTrend(extracted: extracted) {
            lines.append("")
            lines.append("Andamento nel tempo:")
            lines.append(trendBlock)
        }
        return lines
    }

    private static func compactLabTrend(extracted: [ExtractedMedicalValue]) -> String? {
        let lipids = ["Colesterolo totale", "LDL", "HDL"]
        var parts: [String] = []
        for label in lipids {
            let pts = extracted.filter { $0.parameterName == label }.sorted { $0.date < $1.date }
            guard pts.count >= 2, let first = pts.first?.numericValue, let last = pts.last?.numericValue else { continue }
            let y1 = year(pts.first!.date)
            let y2 = year(pts.last!.date)
            let dir = last > first + 5 ? "in aumento" : (last < first - 5 ? "in diminuzione" : "stabile")
            parts.append("\(label) \(dir) tra \(y1) (\(Int(first)) mg/dL) e \(y2) (\(Int(last)) mg/dL)")
        }
        let bp = extracted.filter { $0.kind == .bloodPressure }.sorted { $0.date < $1.date }
        if bp.count >= 2 {
            parts.append("Pressione \(bpTrendPhrase(bp))")
        }
        let lesions = extracted.filter { $0.kind == .lesion && $0.dimensionMm != nil }.sorted { $0.date < $1.date }
        if lesions.count >= 2, let f = lesions.first?.dimensionMm, let l = lesions.last?.dimensionMm {
            let dir = l > f + 1 ? "aumentata" : (l < f - 1 ? "diminuita" : "stabile")
            parts.append("Lesione focali: dimensione \(dir) (\(Int(f)) mm → \(Int(l)) mm)")
        } else if let one = lesions.last, let mm = one.dimensionMm {
            parts.append("Lesione rilevata: \(Int(mm)) mm (\(year(one.date))) — confrontare con controlli successivi")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ") + "."
    }

    private static func bpTrendPhrase(_ points: [ExtractedMedicalValue]) -> String {
        let trendPoints = points.map { v in
            ParameterTrendPoint(
                date: v.date,
                displayValue: v.textValue ?? "",
                numericValue: v.numericValue,
                source: v.sourceLabel
            )
        }
        if let summary = ClinicalRecordMeasurementSummary.bloodPressureYearSummary(points: trendPoints) {
            return summary.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        let series = points.map { "\(year($0.date)): \($0.textValue ?? "")" }.joined(separator: " → ")
        return "sostanzialmente stabile (\(series))"
    }

    private static func bulletLinesFromExam(_ exam: KBMedicalExam, extracted: [ExtractedMedicalValue]) -> [String] {
        var bullets: [String] = []
        let examExtracted = extracted.filter { $0.sourceId == "exam:\(exam.id)" || $0.sourceLabel == exam.name }
        if !examExtracted.isEmpty {
            for v in examExtracted.prefix(10) {
                if v.kind == .bloodPressure {
                    bullets.append("• Profilo pressorio: \(v.textValue ?? "")")
                } else if v.kind == .stressTest {
                    bullets.append("• \(v.parameterName): \(v.textValue ?? "")")
                } else if v.kind == .heartRate {
                    bullets.append("• Frequenza cardiaca massima: \(v.textValue ?? "")")
                } else if v.kind == .lesion, let mm = v.dimensionMm {
                    bullets.append("• \(v.lesionType ?? "Lesione"): \(Int(mm)) mm")
                } else if v.kind == .lab {
                    bullets.append("• \(v.parameterName): \(v.textValue ?? "")")
                }
            }
        }
        if bullets.isEmpty, let text = exam.resultText, !text.isEmpty {
            let clean = HealthAiDocumentText.prepareExtractedTextForAI(text, maxChars: 900)
            for row in clean.split(separator: "\n").prefix(10) {
                let s = String(row).trimmingCharacters(in: .whitespaces)
                if s.isEmpty { continue }
                if s.count > 100 { bullets.append("• \(String(s.prefix(99)))…") }
                else { bullets.append("• \(s)") }
            }
        }
        return bullets
    }

    // MARK: - UI areas

    private static func buildHeaderArea(_ input: ClinicalRecordTopicBuilder.Input) -> ClinicalRecordReportArea {
        ClinicalRecordReportArea(
            id: "header",
            title: "Intestazione",
            summary: input.subjectName,
            narrative: buildHeader(input).joined(separator: "\n"),
            trendNarrative: nil,
            bullets: []
        )
    }

    private static func therapyArea(_ treatments: [KBTreatment]) -> ClinicalRecordReportArea {
        let lines = buildTherapiesSection(treatments)
        return ClinicalRecordReportArea(
            id: ClinicalRecordTopicBuilder.TopicId.therapies.rawValue,
            title: "Terapie in corso",
            summary: treatments.isEmpty ? "Nessuna cura" : "\(treatments.count) in corso",
            narrative: lines.joined(separator: "\n"),
            trendNarrative: nil,
            bullets: lines.filter { $0.hasPrefix("•") }
        )
    }

    private static func pathologyArea(_ ctx: Context) -> ClinicalRecordReportArea {
        let lines = buildPathologiesSection(ctx)
        let bullets = lines.filter { $0.hasPrefix("•") }
        return ClinicalRecordReportArea(
            id: "pathologies",
            title: "Patologie e condizioni",
            summary: bullets.isEmpty ? "Da referti" : "\(bullets.count) elementi",
            narrative: lines.joined(separator: "\n"),
            trendNarrative: compactLabTrend(extracted: ctx.extracted),
            bullets: Array(bullets.prefix(5)),
            overallStatus: .daMonitorare
        )
    }

    private static func pendingArea(_ exams: [KBMedicalExam]) -> ClinicalRecordReportArea {
        let lines = buildPendingSection(exams)
        return ClinicalRecordReportArea(
            id: ClinicalRecordTopicBuilder.TopicId.pending.rawValue,
            title: "Esami in attesa",
            summary: lines.isEmpty ? "Nessuno" : "Prenotati",
            narrative: lines.joined(separator: "\n"),
            trendNarrative: nil,
            bullets: lines.filter { $0.first?.isNumber == true }
        )
    }

    private static func recentExamsArea(_ ctx: Context) -> ClinicalRecordReportArea {
        let lines = buildRecentExamsSection(ctx)
        return ClinicalRecordReportArea(
            id: "recent_exams",
            title: "Ultimi esami",
            summary: "Referti recenti",
            narrative: lines.joined(separator: "\n"),
            trendNarrative: compactLabTrend(extracted: ctx.extracted),
            bullets: lines.filter { $0.hasPrefix("•") }.prefix(5).map { String($0) },
            overallStatus: nil
        )
    }

    private static func areaFromTrend(
        _ trend: SpecialtyTrendSnapshot,
        chronology: [String],
        ctx: Context
    ) -> ClinicalRecordReportArea {
        let trendText = trend.parameters.map { p in
            let series = p.points.map { "\(year($0.date)): \($0.displayValue)" }.joined(separator: " → ")
            return "• \(p.name): \(series)"
        }.joined(separator: "\n")

        var analisi = trend.narrativeAnalysis
        var narrative = trend.narrativeAnalysis
        var bullets = trend.parameters.prefix(3).map { "• \($0.name): \($0.points.last?.displayValue ?? "")" }
        var summary = String(trend.narrativeAnalysis.prefix(72))

        if let topic = ClinicalRecordTopicBuilder.TopicId(rawValue: trend.specialtyId),
           topic == .cardiology || topic == .urology,
           let syn = ClinicalRecordSpecialtyRefertoSynthesis.synthesize(
               specialty: topic,
               exams: ctx.input.exams,
               visits: ctx.input.visits,
               parameters: trend.parameters
           ) {
            analisi = syn.synthesisParagraph
            narrative = syn.timelineDetail.isEmpty
                ? chronology.prefix(8).joined(separator: "\n")
                : syn.timelineDetail
            if !syn.highlights.isEmpty {
                bullets = syn.highlights.map { "• \($0)" }
            }
            summary = String(syn.synthesisParagraph.prefix(72))
        } else if !chronology.isEmpty {
            narrative += "\n\n" + chronology.prefix(6).joined(separator: "\n")
        }

        return ClinicalRecordReportArea(
            id: trend.specialtyId,
            title: trend.specialtyTitle,
            summary: summary,
            narrative: narrative,
            trendNarrative: trendText.isEmpty ? nil : trendText,
            bullets: Array(bullets),
            overallStatus: trend.overallStatus,
            analisiNarrativa: analisi,
            parameters: trend.parameters
        )
    }

    private static func chronologyFor(_ topic: ClinicalRecordTopicBuilder.TopicId, ctx: Context) -> [String] {
        var lines: [String] = []
        for v in ctx.input.visits {
            let t = (v.reason + " " + (v.diagnosis ?? "")).lowercased()
            guard matchesTopic(topic, t) else { continue }
            lines.append("• \(formatMonthYear(v.date)) — \(v.reason)")
        }
        for e in ctx.input.exams {
            let t = (e.name + " " + (e.resultText ?? "")).lowercased()
            guard matchesTopic(topic, t) else { continue }
            lines.append("• \(formatMonthYear(e.resultDate ?? e.updatedAt)) — \(e.name)")
        }
        return lines
    }

    private static func matchesTopic(_ topic: ClinicalRecordTopicBuilder.TopicId, _ text: String) -> Bool {
        switch topic {
        case .bloodPressure: return text.contains("pressione") || text.contains("mmhg")
        case .cardiology:
            return text.contains("cardio") || text.contains("sforzo") || text.contains("colester")
                || text.contains("ecocardio") || text.contains("coronar") || text.contains("ergometr")
        case .gastroenterology: return text.contains("gast") || text.contains("colon") || text.contains("epat") || text.contains("angiom")
        case .urology:
            return text.contains("prostata") || text.contains("ren") || text.contains("urolog")
                || text.contains("psa") || text.contains("varicocele") || text.contains("cisti ren")
        case .metabolism: return text.contains("glicemia") || text.contains("emocromo") || text.contains("sangue")
        default: return false
        }
    }

    // MARK: - Helpers

    private static func isLabLike(_ exam: KBMedicalExam) -> Bool {
        let n = exam.name.lowercased()
        let t = (exam.resultText ?? "").lowercased()
        return n.contains("sangue") || n.contains("emocromo") || n.contains("lipid") || n.contains("colester")
            || t.contains("ldl") || t.contains("hdl") || t.contains("glicemia") || t.contains("creatinina")
    }

    private static func labQualitative(label: String, value: Double) -> String {
        switch label {
        case "LDL":
            if value < 100 { return "ottimale" }
            if value < 130 { return "nei limiti" }
            return "da valutare"
        case "HDL":
            if value < 35 { return "alto rischio, < 35" }
            if value < 40 { return "basso" }
            return "nei limiti"
        case "Colesterolo totale":
            if value < 200 { return "normale" }
            return "da valutare"
        case "Glicemia":
            if value >= 70 && value <= 100 { return "normale" }
            return "da valutare"
        case "PSA", "GOT", "GPT", "Creatinina", "Emoglobina":
            return "nei limiti"
        default:
            return "nei limiti"
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
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

    private static func formatNum(_ v: Double) -> String {
        v == floor(v) ? String(Int(v)) : String(format: "%.1f", v)
    }

    private static func clip(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= 120 ? t : String(t.prefix(119)) + "…"
    }
}
