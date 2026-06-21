//
//  HealthPatternAnalyzerService.swift
//  KidBox
//
//  Analisi mensile silenziosa della storia sanitaria dei figli → insight AI
//  e notifica locale proattiva (pattern speculare a WeeklySummaryService).
//

import Foundation
import UserNotifications
import SwiftData

@MainActor
final class HealthPatternAnalyzerService {

    static let shared = HealthPatternAnalyzerService()

    static let lastMonthKey = "kb_healthPattern_lastMonth"
    static let lastText     = "kb_healthPattern_lastText"
    static let enabled      = "kb_healthPatternEnabled"
    static let notifId      = "kb_healthPattern_notifId"

    private init() {}

    // MARK: - Public API

    func analyzeIfNeeded(
        familyId: String,
        familyName: String,
        children: [KBChild],
        modelContext: ModelContext
    ) async {
        guard isEnabled else {
            KBLog.ai.kbDebug("HealthPatternAnalyzer: disabled by user preference")
            return
        }
        guard AISettings.shared.isEnabled else {
            KBLog.ai.kbDebug("HealthPatternAnalyzer: AI globally disabled")
            return
        }

        let month = currentMonthKey()
        let lastMonth = UserDefaults.standard.string(forKey: Self.lastMonthKey) ?? ""

        guard month != lastMonth else {
            KBLog.ai.kbDebug("HealthPatternAnalyzer: already analyzed for month \(month)")
            if let text = lastInsightText {
                await scheduleLocalNotification(insightText: text, familyName: familyName, monthKey: month, familyId: familyId)
            }
            return
        }

        let familyChildren = children.filter { $0.familyId == familyId }
        guard !familyChildren.isEmpty else {
            KBLog.ai.kbDebug("HealthPatternAnalyzer: no children for familyId=\(familyId)")
            return
        }

        KBLog.ai.kbInfo("HealthPatternAnalyzer: starting analysis for month \(month) family=\(familyName)")

        let healthData = fetchHealthData(
            familyId: familyId,
            children: familyChildren,
            modelContext: modelContext
        )

        let userMessage = buildHealthDataMessage(
            familyName: familyName,
            children: familyChildren,
            data: healthData
        )

        let systemPrompt = buildAnalysisSystemPrompt(familyName: familyName)
        let aiMessages = [KBAIMessage(role: .user, content: userMessage)]

        do {
            let response = try await AIService.shared.sendMessage(
                messages: aiMessages,
                systemPrompt: systemPrompt
            )
            let text = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)

            let normalized = text.uppercased()
            if normalized == "NESSUN_PATTERN" || normalized.hasPrefix("NESSUN_PATTERN\n") {
                KBLog.ai.kbInfo("HealthPatternAnalyzer: NESSUN_PATTERN for month \(month)")
                UserDefaults.standard.set(month, forKey: Self.lastMonthKey)
                UserDefaults.standard.removeObject(forKey: Self.lastText)
                return
            }

            KBLog.ai.kbInfo("HealthPatternAnalyzer: generated chars=\(text.count)")

            persistInsight(
                familyId: familyId,
                fullText: text,
                monthKey: month,
                modelContext: modelContext
            )

            UserDefaults.standard.set(month, forKey: Self.lastMonthKey)
            UserDefaults.standard.set(text, forKey: Self.lastText)

            await scheduleLocalNotification(
                insightText: text,
                familyName: familyName,
                monthKey: month,
                familyId: familyId
            )
        } catch {
            KBLog.ai.kbError("HealthPatternAnalyzer: analysis failed \(error.localizedDescription)")
        }
    }

    var lastInsightText: String? {
        UserDefaults.standard.string(forKey: Self.lastText)
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabled) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabled)
            if !newValue {
                UNUserNotificationCenter.current()
                    .removePendingNotificationRequests(withIdentifiers: ["kb-health-pattern"])
                if let oldId = UserDefaults.standard.string(forKey: Self.notifId) {
                    UNUserNotificationCenter.current()
                        .removePendingNotificationRequests(withIdentifiers: [oldId])
                }
                KBLog.ai.kbInfo("HealthPatternAnalyzer: disabled, notifications removed")
            }
        }
    }

    /// Insight non letto (ultime 24h) da mostrare in PlanningAIChatView; segna `isRead = true`.
    func consumeUnreadInsightIfNeeded(
        familyId: String,
        modelContext: ModelContext
    ) -> String? {
        guard !familyId.isEmpty else { return nil }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let fid = familyId
        var descriptor = FetchDescriptor<KBHealthInsight>(
            predicate: #Predicate { insight in
                insight.familyId == fid && insight.isRead == false && insight.createdAt >= cutoff
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        do {
            guard let insight = try modelContext.fetch(descriptor).first else { return nil }
            let text = insight.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            insight.isRead = true
            try? modelContext.save()
            KBLog.ai.kbInfo("HealthPatternAnalyzer: consumed unread insight id=\(insight.id)")
            return text
        } catch {
            KBLog.ai.kbError("HealthPatternAnalyzer: fetch unread insight failed \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Health data bundle

    private struct ChildHealthData {
        var visits: [KBMedicalVisit]
        var treatments: [KBTreatment]
        var vaccines: [KBVaccine]
        var exams: [KBMedicalExam]
        var profile: KBPediatricProfile?
    }

    private struct FamilyHealthData {
        var byChildId: [String: ChildHealthData]
    }

    private func fetchHealthData(
        familyId: String,
        children: [KBChild],
        modelContext: ModelContext
    ) -> FamilyHealthData {
        let childIds = Set(children.map(\.id))
        var result = FamilyHealthData(byChildId: [:])
        for child in children {
            result.byChildId[child.id] = ChildHealthData(
                visits: [],
                treatments: [],
                vaccines: [],
                exams: [],
                profile: nil
            )
        }

        let fid = familyId

        if let visits = try? modelContext.fetch(
            FetchDescriptor<KBMedicalVisit>(
                predicate: #Predicate { v in
                    v.familyId == fid && v.isDeleted == false
                },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        ) {
            for visit in visits where childIds.contains(visit.childId) {
                var bucket = result.byChildId[visit.childId] ?? ChildHealthData(
                    visits: [], treatments: [], vaccines: [], exams: [], profile: nil
                )
                bucket.visits.append(visit)
                result.byChildId[visit.childId] = bucket
            }
        }

        if let treatments = try? modelContext.fetch(
            FetchDescriptor<KBTreatment>(
                predicate: #Predicate { t in
                    t.familyId == fid && t.isDeleted == false
                },
                sortBy: [SortDescriptor(\.startDate, order: .forward)]
            )
        ) {
            for treatment in treatments where childIds.contains(treatment.childId) && treatment.petId.isEmpty {
                var bucket = result.byChildId[treatment.childId] ?? ChildHealthData(
                    visits: [], treatments: [], vaccines: [], exams: [], profile: nil
                )
                bucket.treatments.append(treatment)
                result.byChildId[treatment.childId] = bucket
            }
        }

        if let vaccines = try? modelContext.fetch(
            FetchDescriptor<KBVaccine>(
                predicate: #Predicate { v in v.familyId == fid },
                sortBy: [SortDescriptor(\.scheduledDate, order: .forward)]
            )
        ) {
            for vaccine in vaccines where childIds.contains(vaccine.childId) {
                var bucket = result.byChildId[vaccine.childId] ?? ChildHealthData(
                    visits: [], treatments: [], vaccines: [], exams: [], profile: nil
                )
                bucket.vaccines.append(vaccine)
                result.byChildId[vaccine.childId] = bucket
            }
        }

        if let exams = try? modelContext.fetch(
            FetchDescriptor<KBMedicalExam>(
                predicate: #Predicate { e in
                    e.familyId == fid && e.isDeleted == false
                },
                sortBy: [SortDescriptor(\.deadline, order: .forward)]
            )
        ) {
            for exam in exams where childIds.contains(exam.childId) {
                var bucket = result.byChildId[exam.childId] ?? ChildHealthData(
                    visits: [], treatments: [], vaccines: [], exams: [], profile: nil
                )
                bucket.exams.append(exam)
                result.byChildId[exam.childId] = bucket
            }
        }

        if let profiles = try? modelContext.fetch(
            FetchDescriptor<KBPediatricProfile>(
                predicate: #Predicate { p in p.familyId == fid }
            )
        ) {
            for profile in profiles where childIds.contains(profile.childId) {
                var bucket = result.byChildId[profile.childId] ?? ChildHealthData(
                    visits: [], treatments: [], vaccines: [], exams: [], profile: nil
                )
                bucket.profile = profile
                result.byChildId[profile.childId] = bucket
            }
        }

        return result
    }

    // MARK: - Data message

    private func buildHealthDataMessage(
        familyName: String,
        children: [KBChild],
        data: FamilyHealthData
    ) -> String {
        var lines: [String] = []
        let fmt = DateFormatter()
        fmt.locale = kbDeviceLocale()
        fmt.dateStyle = .long
        fmt.timeStyle = .none

        let today = fmt.string(from: Date())
        lines.append("STORIA SANITARIA FAMIGLIA \(familyName) — analisi al \(today)")
        lines.append("")

        for child in children.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let childData = data.byChildId[child.id] ?? ChildHealthData(
                visits: [], treatments: [], vaccines: [], exams: [], profile: nil
            )

            let birthStr: String
            if let bd = child.birthDate {
                birthStr = fmt.string(from: bd)
            } else {
                birthStr = "N/D"
            }
            let ageLabel = child.ageYears.map { "\($0) anni" } ?? child.ageDescription

            lines.append("=== \(child.name) — nato il \(birthStr) (\(ageLabel)) ===")
            lines.append("")

            let profile = childData.profile
            let blood = profile?.bloodGroup?.trimmingCharacters(in: .whitespacesAndNewlines)
            let allergies = profile?.allergies?.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("PROFILO: gruppo sanguigno: \(blood?.isEmpty == false ? blood! : "N/D"), allergie: \(allergies?.isEmpty == false ? allergies! : "nessuna")")

            if let w = child.weightKg, let h = child.heightCm {
                lines.append("ANTROPOMETRIA: peso \(String(format: "%.1f", w)) kg, altezza \(Int(h)) cm")
            } else if let w = child.weightKg {
                lines.append("ANTROPOMETRIA: peso \(String(format: "%.1f", w)) kg")
            } else if let h = child.heightCm {
                lines.append("ANTROPOMETRIA: altezza \(Int(h)) cm")
            }

            if let notes = profile?.medicalNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                lines.append("NOTE MEDICHE: \(notes)")
            }
            lines.append("")

            let visits = childData.visits
            lines.append("VISITE (\(visits.count) totali):")
            if visits.isEmpty {
                lines.append("  (nessuna)")
            } else {
                for visit in visits.prefix(30) {
                    let diag = visit.diagnosis?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let diagLabel = (diag?.isEmpty == false) ? diag! : "nessuna diagnosi"
                    let spec = visit.doctorSpecialization?.rawValue
                        ?? visit.doctorSpecializationRaw
                        ?? "generico"
                    lines.append("  • \(fmt.string(from: visit.date)): \(visit.reason) — \(diagLabel) [\(spec)]")
                }
            }
            lines.append("")

            let treatments = childData.treatments
            lines.append("FARMACI (\(treatments.count) totali):")
            if treatments.isEmpty {
                lines.append("  (nessuno)")
            } else {
                for t in treatments {
                    let chronic = t.isLongTerm ? "cronico" : ""
                    let chronicSuffix = chronic.isEmpty ? "" : " [\(chronic)]"
                    lines.append("  • \(fmt.string(from: t.startDate)): \(t.drugName) (\(t.durationDays)gg)\(chronicSuffix)")
                }
            }
            lines.append("")

            let vaccines = childData.vaccines.sorted {
                vaccineSortDate($0) < vaccineSortDate($1)
            }
            lines.append("VACCINI:")
            if vaccines.isEmpty {
                lines.append("  (nessuno)")
            } else {
                for v in vaccines {
                    let statusLabel: String
                    switch v.status {
                    case .administered: statusLabel = "somministrato"
                    case .scheduled:    statusLabel = "programmato"
                    case .planned:      statusLabel = "da programmare"
                    }
                    let date = v.administeredDate ?? v.scheduledDate
                    let dateStr = date.map { fmt.string(from: $0) } ?? "data N/D"
                    lines.append("  • \(v.vaccineType.displayName): \(statusLabel) — \(dateStr)")
                }
            }
            lines.append("")

            let exams = childData.exams
            lines.append("ESAMI:")
            if exams.isEmpty {
                lines.append("  (nessuno)")
            } else {
                for exam in exams {
                    let deadlineStr = exam.deadline.map { fmt.string(from: $0) } ?? "nessuna"
                    lines.append("  • \(exam.name): \(exam.status.rawValue) — scadenza: \(deadlineStr)")
                }
            }
            lines.append("")
            lines.append("---")
            lines.append("")
        }

        lines.append("Cerca pattern che un genitore non noterebbe guardando i singoli eventi.")
        return lines.joined(separator: "\n")
    }

    private func vaccineSortDate(_ vaccine: KBVaccine) -> Date {
        vaccine.scheduledDate ?? vaccine.administeredDate ?? .distantPast
    }

    // MARK: - System prompt

    private func buildAnalysisSystemPrompt(familyName: String) -> String {
        """
        Sei un assistente sanitario AI per la famiglia \(familyName) su KidBox.
        Hai accesso alla storia sanitaria completa di tutti i figli negli anni.

        Il tuo compito è individuare PATTERN RICORRENTI e ANOMALIE rilevanti —
        cose che un genitore non riesce a vedere guardando i singoli eventi ma
        che emergono guardando la storia completa.

        REGOLE TASSATIVE:
        - Scrivi in italiano, tono caldo ma diretto, come un pediatra di fiducia.
        - Max 4 insight, ognuno su una riga che inizia con "• ".
        - Ogni insight: max 25 parole, specifica sempre il nome del bambino.
        - Ogni insight DEVE essere azionabile (suggerisci sempre cosa fare).
        - INCLUDI solo: ricorrenze stagionali (stessa malattia/tipo cura in stesso
          periodo su anni diversi), uso frequente antibiotici (4+ volte in 6 mesi),
          visite specialistiche mancanti da oltre 12 mesi, esami prescritti mai
          eseguiti da oltre 3 mesi, vaccini pianificati con data passata non
          somministrati, pattern peso/altezza se disponibili.
        - IGNORA: eventi isolati, dati già gestiti da reminder attivi, osservazioni
          ovvie (es. "ha avuto la febbre").
        - Se non trovi pattern rilevanti: rispondi NESSUN_PATTERN
        - NON inventare, NON speculare oltre i dati, NON spaventare.

        Termina con una riga vuota e poi: "Vuoi approfondire uno di questi?"
        """
    }

    // MARK: - Persistence

    private func persistInsight(
        familyId: String,
        fullText: String,
        monthKey: String,
        modelContext: ModelContext
    ) {
        let insightId = "health-insight-\(familyId)-\(monthKey)"
        let existing: KBHealthInsight? = {
            guard let rows = try? modelContext.fetch(
                FetchDescriptor<KBHealthInsight>(
                    predicate: #Predicate { $0.id == insightId }
                )
            ) else { return nil }
            return rows.first
        }()

        if let existing {
            existing.fullText = fullText
            existing.monthKey = monthKey
            existing.createdAt = Date()
            existing.isRead = false
        } else {
            let insight = KBHealthInsight(
                id: insightId,
                familyId: familyId,
                fullText: fullText,
                monthKey: monthKey,
                createdAt: Date(),
                isRead: false
            )
            modelContext.insert(insight)
        }
        try? modelContext.save()
        KBLog.ai.kbInfo("HealthPatternAnalyzer: saved insight id=\(insightId)")
    }

    // MARK: - Local notification

    private func scheduleLocalNotification(
        insightText: String,
        familyName: String,
        monthKey: String,
        familyId: String
    ) async {
        let center = UNUserNotificationCenter.current()

        if let oldId = UserDefaults.standard.string(forKey: Self.notifId) {
            center.removePendingNotificationRequests(withIdentifiers: [oldId])
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            KBLog.ai.kbDebug("HealthPatternAnalyzer: no notification permission")
            return
        }

        let firstLine = insightText
            .components(separatedBy: "\n")
            .first { line in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !t.isEmpty && t.hasPrefix("•")
            }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? insightText
                .components(separatedBy: "\n")
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? "Nuovi pattern salute da rivedere."

        let content = UNMutableNotificationContent()
        content.title = "🔍 Pattern salute · \(familyName)"
        content.body = firstLine
        content.sound = .default
        var info: [String: Any] = [
            "type": "health_pattern",
            "fullText": String(insightText.prefix(500)),
        ]
        if !familyId.isEmpty { info["familyId"] = familyId }
        content.userInfo = info

        var dc = DateComponents()
        dc.day = 1
        dc.hour = 9
        dc.minute = 0
        dc.second = 0
        // `repeats: false`: l'insight scatta una sola volta. Con `repeats: true`
        // si ripeteva ogni mese (giorno 1) riproponendo il `fullText` del mese in cui
        // era stato generato → al tap la chat apriva un insight datato. Viene
        // rigenerato ogni mese (vedi `analyzeIfNeeded`), che rimuove la richiesta
        // pendente precedente e ne schedula una fresca.
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)

        let notifId = "kb-health-pattern-\(monthKey)"
        let request = UNNotificationRequest(
            identifier: notifId,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            UserDefaults.standard.set(notifId, forKey: Self.notifId)
            KBLog.ai.kbInfo("HealthPatternAnalyzer: notification scheduled id=\(notifId)")
        } catch {
            KBLog.ai.kbError("HealthPatternAnalyzer: schedule failed \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func currentMonthKey() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: Date())
    }
}
