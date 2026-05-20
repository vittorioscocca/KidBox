//
//  ClinicalRecordAppleHealthNarrative.swift
//  KidBox
//

import Foundation

/// Sezione opzionale Apple Health / wearable (solo se dati disponibili).
enum ClinicalRecordAppleHealthNarrative {

    static let areaId = "apple_health"
    static let sectionTitle = "Apple Health / Wearable"

    private static let disclaimer =
        "I seguenti dati provengono da dispositivo wearable consumer (Apple Watch) e hanno valore indicativo, non diagnostico."

    struct Analysis: Equatable {
        let narrative: String
        let summary: String
        let highlights: [String]
    }

    static func analyze(
        _ snapshot: KBHealthImportSnapshot,
        birthDate: Date?,
        visits: [KBMedicalVisit]
    ) -> Analysis? {
        guard snapshot.hasCardiacOrActivity || snapshot.hasWearableExtendedMetrics else { return nil }

        var parts: [String] = [disclaimer]
        let period = wearablePeriodPhrase(snapshot)
        parts.append("I dati rilevati da Apple Watch \(period) mostrano quanto segue.")

        if let rhr = snapshot.restingHeartRateAvg90d ?? snapshot.restingHeartRateBpm {
            var s = String(format: "La frequenza cardiaca a riposo media è di %.0f bpm", rhr)
            if let visitHR = cardiologistHeartRateHint(from: visits) {
                s += ", coerente con i \(visitHR.bpm) bpm documentati alla visita cardiologica del \(formatShortDate(visitHR.date))"
            }
            s += ", indicativa di buona efficienza cardiovascolare nel contesto consumer."
            parts.append(s)
        }

        if let vo2 = snapshot.vo2MaxRecent ?? snapshot.vo2Max {
            let band = vo2MaxBand(vo2: vo2, birthDate: birthDate)
            parts.append(
                String(
                    format: "Il VO₂ max stimato risulta di %.0f ml/kg/min, collocandosi nella fascia «%@»%@.",
                    vo2,
                    band.label,
                    band.ageContext
                )
            )
        }

        if let weekly = snapshot.weeklyExerciseMinutesAvg, weekly > 0 {
            let oms = weekly >= 150
                ? "superano regolarmente i 150 minuti settimanali raccomandati dall'OMS"
                : "risultano inferiori ai 150 minuti settimanali raccomandati dall'OMS"
            parts.append(
                String(format: "I minuti di attività fisica vigorosa settimanali (media) %@ (circa %.0f min/settimana).", oms, weekly)
            )
        } else if let steps = snapshot.stepsDailyAvg90d ?? averageDailySteps(snapshot) {
            parts.append(
                String(format: "La media di passi giornalieri è di circa %.0f, utile come indice di movimento quotidiano.", steps)
            )
        }

        if let spo2 = snapshot.spo2NightlyAvgPercent {
            parts.append(
                String(
                    format: "La SpO₂ notturna media si mantiene al %.0f%%, escludendo su base indicativa episodi significativi di desaturazione.",
                    spo2
                )
            )
        }

        if let hrv = snapshot.hrvSdnnMsAvg90d {
            parts.append(
                String(format: "La variabilità cardiaca (HRV SDNN) media è di %.0f ms, da interpretare solo come trend benessere.", hrv)
            )
        }

        let activity = classifyActivity(snapshot)
        parts.append(
            "Complessivamente, il profilo da wearable è coerente con \(activity.activityPhrase), pur richiedendo conferma strumentale per qualsiasi valutazione diagnostica."
        )

        let narrative = parts.joined(separator: " ")
        let highlights = buildHighlights(snapshot: snapshot, activity: activity)
        return Analysis(
            narrative: narrative,
            summary: activity.summaryLabel,
            highlights: highlights
        )
    }

    static func documentLines(
        snapshot: KBHealthImportSnapshot,
        sourceLabel: String,
        birthDate: Date?,
        visits: [KBMedicalVisit]
    ) -> [String] {
        guard let analysis = analyze(snapshot, birthDate: birthDate, visits: visits) else { return [] }
        return [
            "---",
            "DATI \(sourceLabel.uppercased()) / WEARABLE",
            "",
            analysis.narrative,
        ]
    }

    static func reportArea(
        snapshot: KBHealthImportSnapshot,
        sourceLabel: String,
        birthDate: Date?,
        visits: [KBMedicalVisit]
    ) -> ClinicalRecordReportArea? {
        guard let analysis = analyze(snapshot, birthDate: birthDate, visits: visits) else { return nil }
        return ClinicalRecordReportArea(
            id: areaId,
            title: sectionTitle,
            summary: analysis.summary,
            narrative: analysis.narrative,
            trendNarrative: nil,
            bullets: analysis.highlights,
            overallStatus: nil,
            analisiNarrativa: analysis.narrative,
            parameters: nil
        )
    }

    static func appendToPrompt(
        _ snapshot: KBHealthImportSnapshot,
        sourceLabel: String,
        birthDate: Date?,
        visits: [KBMedicalVisit],
        into lines: inout [String]
    ) {
        guard let analysis = analyze(snapshot, birthDate: birthDate, visits: visits) else { return }
        lines.append("\n--- \(sourceLabel.uppercased()) / WEARABLE ---")
        lines.append(analysis.narrative)
    }

    // MARK: - Helpers

    private struct ActivityProfile {
        let summaryLabel: String
        let activityPhrase: String
    }

    private struct Vo2Band {
        let label: String
        let ageContext: String
    }

    private static func classifyActivity(_ s: KBHealthImportSnapshot) -> ActivityProfile {
        let workouts14 = workoutsInLastDays(s, days: 14)
        let workoutMinutes = workouts14.compactMap(\.durationMinutes).reduce(0, +)
        let avgSteps = s.stepsDailyAvg90d ?? averageDailySteps(s) ?? Double(s.stepsToday ?? 0)
        let weekly = s.weeklyExerciseMinutesAvg ?? 0

        if workouts14.count >= 4 || workoutMinutes >= 120 || weekly >= 150 {
            return ActivityProfile(
                summaryLabel: "Pratica sportiva regolare",
                activityPhrase: "uno stile di vita attivo e un buon compenso cardiovascolare"
            )
        }
        if workouts14.count >= 2 || avgSteps >= 9_000 || weekly >= 90 {
            return ActivityProfile(
                summaryLabel: "Attività fisica regolare",
                activityPhrase: "un'attività fisica regolare"
            )
        }
        if workouts14.count >= 1 || avgSteps >= 6_000 || weekly >= 45 {
            return ActivityProfile(
                summaryLabel: "Attività moderata",
                activityPhrase: "un'attività fisica moderata"
            )
        }
        if avgSteps >= 3_500 {
            return ActivityProfile(
                summaryLabel: "Attività leggera",
                activityPhrase: "un'attività quotidiana leggera"
            )
        }
        return ActivityProfile(
            summaryLabel: "Vita prevalentemente sedentaria",
            activityPhrase: "uno stile di vita prevalentemente sedentario"
        )
    }

    private static func buildHighlights(snapshot: KBHealthImportSnapshot, activity: ActivityProfile) -> [String] {
        var h: [String] = [activity.summaryLabel]
        if let rhr = snapshot.restingHeartRateAvg90d ?? snapshot.restingHeartRateBpm {
            h.append(String(format: "FC a riposo media: %.0f bpm", rhr))
        }
        if let vo2 = snapshot.vo2MaxRecent ?? snapshot.vo2Max {
            h.append(String(format: "VO₂ max: %.0f ml/kg/min", vo2))
        }
        if let steps = snapshot.stepsDailyAvg90d {
            h.append(String(format: "Passi medi/die: %.0f", steps))
        }
        return h
    }

    private static func vo2MaxBand(vo2: Double, birthDate: Date?) -> Vo2Band {
        let age = birthDate.map { Calendar.current.dateComponents([.year], from: $0, to: Date()).year ?? 40 } ?? 40
        let ageCtx = birthDate != nil ? " per l'età di circa \(age) anni" : ""
        // Fasce indicative AHA-style (uomo adulto; senza sesso usiamo soglie medie)
        let label: String
        switch age {
        case ..<30:
            label = vo2 >= 48 ? "Eccellente" : (vo2 >= 42 ? "Buono" : (vo2 >= 36 ? "Discreto" : "Da migliorare"))
        case 30..<40:
            label = vo2 >= 44 ? "Eccellente" : (vo2 >= 40 ? "Buono" : (vo2 >= 34 ? "Discreto" : "Da migliorare"))
        case 40..<50:
            label = vo2 >= 40 ? "Eccellente" : (vo2 >= 36 ? "Buono" : (vo2 >= 30 ? "Discreto" : "Da migliorare"))
        case 50..<60:
            label = vo2 >= 36 ? "Eccellente" : (vo2 >= 32 ? "Buono" : (vo2 >= 26 ? "Discreto" : "Da migliorare"))
        default:
            label = vo2 >= 32 ? "Buono" : (vo2 >= 26 ? "Discreto" : "Da migliorare")
        }
        return Vo2Band(label: label, ageContext: ageCtx)
    }

    private static func cardiologistHeartRateHint(from visits: [KBMedicalVisit]) -> (bpm: Int, date: Date)? {
        let pattern = #"(?i)(?:FC|frequenza cardiaca|polso)[^\d]{0,20}(\d{2,3})\s*bpm"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for v in visits.sorted(by: { $0.date > $1.date }) {
            let blob = [v.diagnosis, v.notes, v.recommendations, v.reason].compactMap { $0 }.joined(separator: " ")
            let range = NSRange(blob.startIndex..<blob.endIndex, in: blob)
            guard let m = regex.firstMatch(in: blob, range: range),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: blob),
                  let bpm = Int(blob[r]), bpm >= 40, bpm <= 220 else { continue }
            return (bpm, v.date)
        }
        return nil
    }

    private static func wearablePeriodPhrase(_ s: KBHealthImportSnapshot) -> String {
        if let start = s.wearablePeriodStart, let end = s.wearablePeriodEnd {
            return "nel periodo \(formatShortDate(start))–\(formatShortDate(end))"
        }
        return "negli ultimi tre mesi"
    }

    private static func averageDailySteps(_ s: KBHealthImportSnapshot) -> Double? {
        let vals = s.recentDailyActivity.compactMap(\.steps).filter { $0 > 0 }
        guard !vals.isEmpty else { return nil }
        return Double(vals.reduce(0, +)) / Double(vals.count)
    }

    private static func workoutsInLastDays(_ s: KBHealthImportSnapshot, days: Int) -> [KBHealthWorkoutEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return s.recentWorkouts.filter { $0.startedAt >= cutoff }
    }

    private static func formatShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: date)
    }
}
