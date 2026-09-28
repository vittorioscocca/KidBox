//
//  FitnessPlanParser.swift
//  KidBox
//
//  Legge il JSON prodotto dall'AI e lo trasforma in `FitnessPlanDocument`.
//
//  Il modello a volte incornicia il JSON con una frase o con un blocco di
//  codice Markdown, nonostante il prompt lo vieti: qui isoliamo l'oggetto tra
//  la prima graffa aperta e l'ultima chiusa invece di fallire.
//

import Foundation

enum FitnessPlanParser {

    // MARK: - Piano completo

    static func parsePlan(
        _ raw: String,
        subjectName: String,
        input: FitnessPlanInput,
        startDate: Date,
        messageUnitsConsumed: Int
    ) throws -> FitnessPlanDocument {
        guard let object = jsonObject(from: raw) else {
            KBLog.ai.kbError("FitnessPlanParser: nessun JSON riconoscibile nella risposta")
            throw FitnessPlanAIError.invalidPlanFormat
        }

        let summary = (object["summary"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let safetyNotes = (object["safetyNotes"] as? [Any])?
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        let rawWeeks = object["weeks"] as? [[String: Any]] ?? []
        var weeks: [FitnessWeek] = []

        for (position, rawWeek) in rawWeeks.enumerated() {
            let index = intValue(rawWeek["index"]) ?? (position + 1)
            let focus = (rawWeek["focus"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rawSessions = rawWeek["sessions"] as? [[String: Any]] ?? []
            let sessions = rawSessions.compactMap {
                session(from: $0, weekIndex: index, startDate: startDate)
            }
            guard !sessions.isEmpty else { continue }
            weeks.append(
                FitnessWeek(
                    index: index,
                    focus: focus,
                    sessions: sessions.sorted { $0.date < $1.date }
                )
            )
        }

        weeks = oneSessionPerDay(weeks)

        guard !weeks.isEmpty else {
            KBLog.ai.kbError("FitnessPlanParser: JSON senza settimane utilizzabili")
            throw FitnessPlanAIError.invalidPlanFormat
        }

        return FitnessPlanDocument(
            subjectName: subjectName,
            input: input,
            startDate: startDate,
            summary: summary,
            safetyNotes: safetyNotes,
            weeks: weeks.sorted { $0.index < $1.index },
            generatedAt: Date(),
            messageUnitsConsumed: messageUnitsConsumed
        )
    }

    /// Una seduta per giorno, anche quando l'AI ne mette due sullo stesso
    /// `dayOffset` (è successo nel settembre 2026: lunedì e mercoledì doppi
    /// nella settimana 4, mai chiesti). Il doppione non si vede sul calendario
    /// ma pesa nel report: resta la seduta più lunga, che è quella principale.
    static func oneSessionPerDay(_ weeks: [FitnessWeek]) -> [FitnessWeek] {
        let cal = Calendar.current
        var keptByDay: [Date: String] = [:]
        for session in weeks.flatMap(\.sessions) {
            let day = cal.startOfDay(for: session.date)
            if let keptId = keptByDay[day],
               let kept = weeks.lazy.flatMap(\.sessions).first(where: { $0.id == keptId }),
               kept.durationMinutes >= session.durationMinutes {
                continue
            }
            keptByDay[day] = session.id
        }
        let keep = Set(keptByDay.values)
        let dropped = weeks.reduce(0) { $0 + $1.sessions.count } - keep.count
        if dropped > 0 {
            KBLog.ai.kbError("FitnessPlanParser: scartate \(dropped) sedute doppie sullo stesso giorno")
        }
        return weeks
            .map { week in
                var week = week
                week.sessions = week.sessions.filter { keep.contains($0.id) }
                return week
            }
            .filter { !$0.sessions.isEmpty }
    }

    // MARK: - Aggiornamento parziale (Sposta / adeguamento settimanale)

    struct SessionUpdates {
        let rationale: String
        let changes: [String]
        /// Sessioni riscritte, con l'id di quelle esistenti quando l'AI lo rispetta.
        let sessions: [FitnessSession]
    }

    static func parseSessionUpdates(
        _ raw: String,
        startDate: Date,
        fallbackWeekIndex: Int
    ) throws -> SessionUpdates {
        guard let object = jsonObject(from: raw) else {
            throw FitnessPlanAIError.invalidPlanFormat
        }
        let rationale = (object["rationale"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let changes = (object["changes"] as? [Any])?
            .compactMap { $0 as? String }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
        let rawSessions = object["sessions"] as? [[String: Any]] ?? []
        let sessions = rawSessions.compactMap {
            session(from: $0, weekIndex: fallbackWeekIndex, startDate: startDate)
        }
        return SessionUpdates(rationale: rationale, changes: changes, sessions: sessions)
    }

    // MARK: - Sessione

    private static func session(
        from raw: [String: Any],
        weekIndex: Int,
        startDate: Date
    ) -> FitnessSession? {
        guard let dayOffset = intValue(raw["dayOffset"]) else { return nil }
        let cal = Calendar.current
        guard let date = cal.date(
            byAdding: .day,
            value: dayOffset,
            to: cal.startOfDay(for: startDate)
        ) else { return nil }

        let title = (raw["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activityType = (raw["activityType"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty || !activityType.isEmpty else { return nil }

        let exercises = (raw["exercises"] as? [[String: Any]] ?? []).compactMap { item -> FitnessExercise? in
            guard let name = (item["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
            else { return nil }
            return FitnessExercise(
                name: name,
                detail: (item["detail"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                notes: (item["notes"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
            )
        }

        let targets = (raw["targets"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // L'id lo decide l'AI solo negli aggiornamenti parziali; alla prima
        // generazione lo assegniamo noi, così resta stabile tra i salvataggi.
        let id = (raw["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        return FitnessSession(
            id: (id?.isEmpty == false) ? id! : UUID().uuidString,
            date: date,
            weekIndex: weekIndex,
            title: title.isEmpty ? activityType : title,
            activityType: activityType.isEmpty ? title : activityType,
            durationMinutes: intValue(raw["durationMinutes"]) ?? 40,
            intensity: (raw["intensity"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            exercises: exercises,
            targets: targets,
            targetKcal: intValue(raw["targetKcal"]),
            notes: (raw["notes"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        )
    }

    // MARK: - JSON grezzo

    /// Isola l'oggetto JSON dalla risposta, tollerando testo o ``` attorno.
    static func jsonObject(from raw: String) -> [String: Any]? {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        guard
            let start = cleaned.firstIndex(of: "{"),
            let end = cleaned.lastIndex(of: "}"),
            start < end
        else { return nil }
        let slice = String(cleaned[start...end])
        guard let data = slice.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let value as Int: return value
        case let value as Double: return Int(value.rounded())
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
}
