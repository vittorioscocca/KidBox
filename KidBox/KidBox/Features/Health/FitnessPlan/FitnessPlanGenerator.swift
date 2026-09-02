//
//  FitnessPlanGenerator.swift
//  KidBox
//
//  Generazione del Piano Fitness via Cloud Function `askAI`:
//  - `purpose: "fitnessPlan"` per il piano mensile (JSON, max_tokens esteso);
//  - `purpose: "fitnessAdjust"` per lo spostamento di una seduta e per la
//    proposta di adeguamento settimanale (payload piccolo, 1 messaggio).
//

import FirebaseFunctions
import Foundation
import SwiftData

enum FitnessPlanGenerator {

    /// Overhead delle regole aggiunte lato server (`FITNESS_PLAN_SYSTEM_RULES` in index.js).
    private static let serverRulesOverheadChars = 900

    struct Estimate: Equatable {
        let totalChars: Int
        let messageUnits: Int
    }

    struct Payload {
        let systemPrompt: String
        let userContent: String
        let profileSummary: [String]
        let healthContext: String
        let startDate: Date
        let hasWeight: Bool
        let hasHeight: Bool
    }

    // MARK: - Date del piano

    /// Il piano parte da oggi: le settimane sono blocchi scorrevoli di 7 giorni,
    /// così la prima settimana non nasce già a metà.
    static func planStartDate(from date: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// Offset (giorni dall'inizio) delle giornate in cui l'utente si allena.
    static func allowedDayOffsets(input: FitnessPlanInput, startDate: Date) -> [Int] {
        let cal = Calendar.current
        let totalDays = FitnessPlanPromptBuilder.planWeeks * 7
        return (0..<totalDays).filter { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: startDate) else { return false }
            return input.trainingWeekdays.contains(cal.component(.weekday, from: day))
        }
    }

    // MARK: - Payload

    @MainActor
    static func buildPayload(
        modelContext: ModelContext,
        familyId: String,
        childId: String,
        subjectName: String,
        birthDate: Date?,
        input: FitnessPlanInput,
        treatments: [KBTreatment],
        vaccines: [KBVaccine],
        visits: [KBMedicalVisit],
        exams: [KBMedicalExam],
        startDate: Date = planStartDate()
    ) -> Payload {
        let snapshot = KBHealthLinkStore.load(childId: childId)
        let profile = fetchProfile(modelContext: modelContext, childId: childId)
        let documents = fetchHealthDocuments(
            modelContext: modelContext,
            familyId: familyId,
            childId: childId
        )

        let healthContext = HealthContextBuilder.buildSystemPrompt(
            subjectName: subjectName,
            subjectId: childId,
            exams: exams,
            visits: visits,
            treatments: treatments,
            vaccines: vaccines,
            documentsByExamId: documents.byExam,
            documentsByVisitId: documents.byVisit,
            documentsByTreatmentId: documents.byTreatment,
            refertoMaxChars: FitnessPlanPromptBuilder.refertoMaxChars,
            healthSnapshot: snapshot,
            subjectBirthDate: birthDate ?? snapshot?.birthDate,
            visitsForWearableContext: visits,
            purpose: .clinicalRecord
        )

        let profileSummary = FitnessPlanPromptBuilder.profileSummaryLines(
            birthDate: birthDate,
            snapshot: snapshot,
            profile: profile,
            input: input
        )

        return Payload(
            systemPrompt: FitnessPlanPromptBuilder.systemPrompt(
                responseLanguage: FitnessPlanPromptBuilder.responseLanguageName()
            ),
            userContent: FitnessPlanPromptBuilder.userContent(
                subjectName: subjectName,
                input: input,
                startDate: startDate,
                allowedDayOffsets: allowedDayOffsets(input: input, startDate: startDate),
                profileSummary: profileSummary,
                healthContext: healthContext
            ),
            profileSummary: profileSummary,
            healthContext: healthContext,
            startDate: startDate,
            hasWeight: snapshot?.weightKg != nil || input.manualWeightValue != nil,
            hasHeight: snapshot?.heightCm != nil || input.manualHeightValue != nil
        )
    }

    static func estimate(payload: Payload) -> Estimate {
        let base = AIAskAIPayload.totalChars(
            systemPrompt: payload.systemPrompt,
            messages: [KBAIMessage(role: .user, content: payload.userContent)]
        )
        let total = base + serverRulesOverheadChars
        return Estimate(
            totalChars: total,
            messageUnits: AIAskAIPayload.fitnessPlanMessageUnits(totalChars: total)
        )
    }

    // MARK: - Generazione del piano

    @MainActor
    static func generate(
        payload: Payload,
        subjectName: String,
        input: FitnessPlanInput
    ) async throws -> (document: FitnessPlanDocument, usage: FitnessPlanAIUsageInfo) {

        // Feature dei soli piani a pagamento: il gate vero è lato server, questo
        // evita di bruciare una chiamata e dà subito il messaggio giusto.
        guard KBSubscriptionManager.shared.currentPlan != .free else {
            throw FitnessPlanAIError.planNotIncluded
        }
        guard input.isComplete else {
            throw FitnessPlanAIError.incompleteSetup
        }
        guard payload.hasWeight, payload.hasHeight else {
            throw FitnessPlanAIError.missingHealthData
        }

        let estimate = estimate(payload: payload)
        if estimate.totalChars > AIAskAIPayload.absoluteMaxChars {
            throw FitnessPlanAIError.payloadTooLarge(
                chars: estimate.totalChars,
                maxChars: AIAskAIPayload.absoluteMaxChars
            )
        }
        try await assertQuota(units: estimate.messageUnits)

        KBLog.ai.kbInfo(
            "FitnessPlanGenerator: request chars=\(estimate.totalChars) units=\(estimate.messageUnits)"
        )

        let response = try await send(
            userContent: payload.userContent,
            systemPrompt: payload.systemPrompt,
            purpose: "fitnessPlan"
        )

        let document = try FitnessPlanParser.parsePlan(
            response.reply,
            subjectName: subjectName,
            input: input,
            startDate: payload.startDate,
            messageUnitsConsumed: response.messageUnitsConsumed
        )
        let usage = FitnessPlanAIUsageInfo(
            messageUnitsConsumed: response.messageUnitsConsumed,
            usageToday: response.usageToday,
            dailyLimit: response.dailyLimit,
            totalPayloadChars: response.totalPayloadChars ?? estimate.totalChars
        )
        KBLog.ai.kbInfo(
            "FitnessPlanGenerator: done weeks=\(document.weeks.count) sessions=\(document.allSessions.count) usage=\(usage.usageSummary)"
        )
        return (document, usage)
    }

    // MARK: - Sposta una seduta

    struct RescheduleOutcome {
        let plan: FitnessPlanDocument
        let rationale: String
        let usage: FitnessPlanAIUsageInfo
    }

    /// Riorganizza i giorni rimanenti della settimana dopo uno spostamento.
    ///
    /// Costa poco perché il payload non contiene il contesto clinico completo:
    /// vanno solo le sedute della settimana e le note di sicurezza già calcolate
    /// alla generazione del piano.
    @MainActor
    static func reschedule(
        plan: FitnessPlanDocument,
        sessionId: String,
        newDate: Date
    ) async throws -> RescheduleOutcome {
        guard KBSubscriptionManager.shared.currentPlan != .free else {
            throw FitnessPlanAIError.planNotIncluded
        }
        guard let session = plan.session(id: sessionId) else {
            throw FitnessPlanAIError.invalidPlanFormat
        }

        let weekIndex = session.weekIndex
        let systemPrompt = FitnessPlanPromptBuilder.rescheduleSystemPrompt(
            responseLanguage: FitnessPlanPromptBuilder.responseLanguageName()
        )
        let userContent = rescheduleUserContent(
            plan: plan,
            movedSession: session,
            newDate: newDate,
            weekIndex: weekIndex
        )

        try await assertQuota(
            units: AIAskAIPayload.messageUnits(
                totalChars: AIAskAIPayload.totalChars(
                    systemPrompt: systemPrompt,
                    messages: [KBAIMessage(role: .user, content: userContent)]
                )
            )
        )

        let response = try await send(
            userContent: userContent,
            systemPrompt: systemPrompt,
            purpose: "fitnessAdjust"
        )

        let updates = try FitnessPlanParser.parseSessionUpdates(
            response.reply,
            startDate: plan.startDate,
            fallbackWeekIndex: weekIndex
        )

        var updated = plan
        // Lo spostamento vero lo applica il client: l'AI riorganizza il resto,
        // ma la data scelta dall'utente non è negoziabile.
        updated.updateSession(id: sessionId) { moved in
            moved.originalDate = moved.originalDate ?? moved.date
            moved.date = Calendar.current.startOfDay(for: newDate)
            moved.status = .planned
        }
        updated = apply(updates.sessions, to: updated, skipping: [sessionId])

        return RescheduleOutcome(
            plan: updated,
            rationale: updates.rationale,
            usage: FitnessPlanAIUsageInfo(
                messageUnitsConsumed: response.messageUnitsConsumed,
                usageToday: response.usageToday,
                dailyLimit: response.dailyLimit,
                totalPayloadChars: response.totalPayloadChars ?? 0
            )
        )
    }

    // MARK: - Proposta di adeguamento settimanale

    @MainActor
    static func weeklyAdjustment(
        plan: FitnessPlanDocument,
        report: FitnessWeeklyReport
    ) async throws -> (proposal: FitnessAdjustmentProposal, usage: FitnessPlanAIUsageInfo) {
        guard KBSubscriptionManager.shared.currentPlan != .free else {
            throw FitnessPlanAIError.planNotIncluded
        }
        let nextWeekIndex = report.weekIndex + 1
        guard plan.weeks.contains(where: { $0.index == nextWeekIndex }) else {
            throw FitnessPlanAIError.invalidPlanFormat
        }

        let systemPrompt = FitnessPlanPromptBuilder.weeklyAdjustSystemPrompt(
            responseLanguage: FitnessPlanPromptBuilder.responseLanguageName()
        )
        let userContent = weeklyAdjustUserContent(
            plan: plan,
            report: report,
            nextWeekIndex: nextWeekIndex
        )

        try await assertQuota(
            units: AIAskAIPayload.messageUnits(
                totalChars: AIAskAIPayload.totalChars(
                    systemPrompt: systemPrompt,
                    messages: [KBAIMessage(role: .user, content: userContent)]
                )
            )
        )

        let response = try await send(
            userContent: userContent,
            systemPrompt: systemPrompt,
            purpose: "fitnessAdjust"
        )

        let updates = try FitnessPlanParser.parseSessionUpdates(
            response.reply,
            startDate: plan.startDate,
            fallbackWeekIndex: nextWeekIndex
        )

        let proposal = FitnessAdjustmentProposal(
            rationale: updates.rationale,
            changes: updates.changes,
            updatedSessions: updates.sessions,
            generatedAt: Date(),
            weekIndex: nextWeekIndex
        )
        let usage = FitnessPlanAIUsageInfo(
            messageUnitsConsumed: response.messageUnitsConsumed,
            usageToday: response.usageToday,
            dailyLimit: response.dailyLimit,
            totalPayloadChars: response.totalPayloadChars ?? 0
        )
        return (proposal, usage)
    }

    /// Applica al piano le sedute riscritte da una proposta accettata.
    static func apply(
        _ sessions: [FitnessSession],
        to plan: FitnessPlanDocument,
        skipping skipped: Set<String> = []
    ) -> FitnessPlanDocument {
        var updated = plan
        for incoming in sessions where !skipped.contains(incoming.id) {
            guard let existing = updated.session(id: incoming.id) else { continue }
            // Una seduta già chiusa non si riscrive: il resoconto della settimana
            // deve restare quello che è successo davvero.
            guard existing.status != .done else { continue }
            updated.updateSession(id: incoming.id) { session in
                if !Calendar.current.isDate(session.date, inSameDayAs: incoming.date) {
                    session.originalDate = session.originalDate ?? session.date
                }
                session.date = incoming.date
                session.title = incoming.title
                session.activityType = incoming.activityType
                session.durationMinutes = incoming.durationMinutes
                session.intensity = incoming.intensity
                session.exercises = incoming.exercises
                session.targets = incoming.targets
                session.targetKcal = incoming.targetKcal
                session.notes = incoming.notes
                session.status = .planned
            }
        }
        // Le date sono cambiate: ogni settimana va riordinata.
        for weekIndex in updated.weeks.indices {
            updated.weeks[weekIndex].sessions.sort { $0.date < $1.date }
        }
        return updated
    }

    // MARK: - Chiamata

    @MainActor
    private static func send(
        userContent: String,
        systemPrompt: String,
        purpose: String
    ) async throws -> AIResponse {
        do {
            return try await AIService.shared.sendMessage(
                messages: [KBAIMessage(role: .user, content: userContent)],
                systemPrompt: systemPrompt,
                purpose: purpose
            )
        } catch {
            // La callable scade con `deadlineExceeded`: senza questo caso
            // l'utente vedrebbe l'errore grezzo di Firebase.
            if (error as NSError).code == FunctionsErrorCode.deadlineExceeded.rawValue {
                throw FitnessPlanAIError.timedOut
            }
            throw error
        }
    }

    private static func assertQuota(units: Int) async throws {
        guard let current = try? await AIService.shared.fetchUsage() else { return }
        let remaining = max(0, current.dailyLimit - current.usageToday)
        guard units > remaining else { return }
        throw FitnessPlanAIError.quotaWouldExceed(
            needed: units,
            remaining: remaining,
            dailyLimit: current.dailyLimit
        )
    }

    // MARK: - Contenuti dei prompt brevi

    private static func rescheduleUserContent(
        plan: FitnessPlanDocument,
        movedSession: FitnessSession,
        newDate: Date,
        weekIndex: Int
    ) -> String {
        var lines: [String] = []
        lines.append("L'utente ha spostato una seduta e serve riorganizzare la settimana \(weekIndex).")
        lines.append("Obiettivo del piano: \(plan.input.goal.promptLabel)")
        lines.append("Giorni disponibili: \(FitnessPlanPromptBuilder.weekdayNames(plan.input.sortedWeekdays))")
        lines.append("Inizio del piano (dayOffset 0): \(shortDate(plan.startDate))")
        lines.append(
            "Seduta spostata: \"\(movedSession.title)\" da \(shortDate(movedSession.date)) "
            + "a \(shortDate(newDate)) (dayOffset \(dayOffset(of: newDate, from: plan.startDate)))"
        )
        if !plan.safetyNotes.isEmpty {
            lines.append("")
            lines.append("--- VINCOLI CLINICI GIÀ STABILITI (da rispettare) ---")
            lines.append(contentsOf: plan.safetyNotes.map { "• \($0)" })
        }
        lines.append("")
        lines.append("--- SEDUTE DELLA SETTIMANA \(weekIndex) ---")
        lines.append(contentsOf: sessionLines(
            plan.weeks.first { $0.index == weekIndex }?.sessions ?? [],
            startDate: plan.startDate
        ))
        return lines.joined(separator: "\n")
    }

    private static func weeklyAdjustUserContent(
        plan: FitnessPlanDocument,
        report: FitnessWeeklyReport,
        nextWeekIndex: Int
    ) -> String {
        var lines: [String] = []
        lines.append("Analizza la settimana \(report.weekIndex) e proponi come impostare la settimana \(nextWeekIndex).")
        lines.append("Obiettivo del piano: \(plan.input.goal.promptLabel)")
        lines.append("Giorni disponibili: \(FitnessPlanPromptBuilder.weekdayNames(plan.input.sortedWeekdays))")
        lines.append("Inizio del piano (dayOffset 0): \(shortDate(plan.startDate))")
        lines.append("")
        lines.append("--- ANDAMENTO DELLA SETTIMANA \(report.weekIndex) ---")
        lines.append("Sedute previste: \(report.plannedSessions)")
        lines.append("Sedute completate: \(report.completedSessions) (\(report.completionPercent)%)")
        lines.append("Sedute saltate: \(report.skippedSessions)")
        if report.substitutedSessions > 0 {
            lines.append(
                "Sedute svolte con un'attività diversa da quella programmata: "
                + "\(report.substitutedSessions). Tienine conto: il volume è stato rispettato, "
                + "il contenuto no."
            )
        }
        lines.append("Minuti totali di attività: \(report.totalMinutes)")
        if report.totalKcal > 0 {
            lines.append("Calorie attive stimate: \(report.totalKcal)")
        }
        if !report.chronicallySkippedWeekdays.isEmpty {
            lines.append(
                "Giorni saltati in modo ricorrente: "
                + FitnessPlanPromptBuilder.weekdayNames(report.chronicallySkippedWeekdays)
            )
        }
        if !plan.safetyNotes.isEmpty {
            lines.append("")
            lines.append("--- VINCOLI CLINICI GIÀ STABILITI (da rispettare) ---")
            lines.append(contentsOf: plan.safetyNotes.map { "• \($0)" })
        }
        lines.append("")
        lines.append("--- SEDUTE DELLA SETTIMANA \(nextWeekIndex), COSÌ COME SONO ORA ---")
        lines.append(contentsOf: sessionLines(
            plan.weeks.first { $0.index == nextWeekIndex }?.sessions ?? [],
            startDate: plan.startDate
        ))
        return lines.joined(separator: "\n")
    }

    /// Righe compatte di una seduta: id, data, contenuto e stato.
    static func sessionLines(_ sessions: [FitnessSession], startDate: Date) -> [String] {
        guard !sessions.isEmpty else { return ["Nessuna seduta."] }
        return sessions.map { session in
            var line = "id=\(session.id) | dayOffset=\(dayOffset(of: session.date, from: startDate))"
            line += " | \(shortDate(session.date)) | \(session.title)"
            line += " | \(session.activityType), \(session.durationMinutes) min, intensità \(session.intensity)"
            line += " | stato: \(statusLabel(session.status))"
            if !session.exercises.isEmpty {
                let detail = session.exercises.map { "\($0.name) (\($0.detail))" }.joined(separator: "; ")
                line += " | esercizi: \(detail)"
            }
            if !session.targets.isEmpty {
                line += " | obiettivi: \(session.targets.joined(separator: "; "))"
            }
            return line
        }
    }

    private static func statusLabel(_ status: FitnessSessionStatus) -> String {
        switch status {
        case .planned: return "da fare"
        case .done:    return "completata"
        case .skipped: return "saltata"
        case .moved:   return "spostata"
        }
    }

    static func dayOffset(of date: Date, from startDate: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: startDate),
            to: cal.startOfDay(for: date)
        ).day ?? 0
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Fetch

    @MainActor
    private static func fetchProfile(modelContext: ModelContext, childId: String) -> KBPediatricProfile? {
        var descriptor = FetchDescriptor<KBPediatricProfile>(
            predicate: #Predicate { $0.childId == childId }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    @MainActor
    private static func fetchHealthDocuments(
        modelContext: ModelContext,
        familyId: String,
        childId: String
    ) -> (byExam: [String: [KBDocument]], byVisit: [String: [KBDocument]], byTreatment: [String: [KBDocument]]) {
        let fid = familyId
        let cid = childId
        let descriptor = FetchDescriptor<KBDocument>(
            predicate: #Predicate {
                $0.familyId == fid && $0.isDeleted == false
                    && ($0.childId == cid || $0.childId == nil)
            }
        )
        let docs = (try? modelContext.fetch(descriptor)) ?? []

        var byExam: [String: [KBDocument]] = [:]
        var byVisit: [String: [KBDocument]] = [:]
        var byTreatment: [String: [KBDocument]] = [:]

        for doc in docs {
            guard let tag = doc.notes else { continue }
            if tag.hasPrefix("exam:") {
                byExam[String(tag.dropFirst(5)), default: []].append(doc)
            } else if tag.hasPrefix("visit:") {
                byVisit[String(tag.dropFirst(6)), default: []].append(doc)
            } else if tag.hasPrefix("treatment:") {
                byTreatment[String(tag.dropFirst(10)), default: []].append(doc)
            }
        }
        return (byExam, byVisit, byTreatment)
    }
}
