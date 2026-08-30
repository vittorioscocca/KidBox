//
//  MealPlanGenerator.swift
//  KidBox
//
//  Generazione del piano alimentare via Cloud Function `askAI` con
//  `purpose: "mealPlan"` (Anthropic Haiku lato server, max_tokens esteso).
//

import FirebaseFunctions
import Foundation
import SwiftData

enum MealPlanGenerator {

    /// Overhead delle regole aggiunte lato server (`MEAL_PLAN_SYSTEM_RULES` in index.js).
    private static let serverRulesOverheadChars = 900

    struct Estimate: Equatable {
        let totalChars: Int
        let messageUnits: Int
    }

    struct Payload {
        let systemPrompt: String
        let userContent: String
        let profileSummary: [String]
        let hasWeight: Bool
        let hasHeight: Bool
    }

    // MARK: - Payload

    @MainActor
    static func buildPayload(
        modelContext: ModelContext,
        familyId: String,
        childId: String,
        subjectName: String,
        birthDate: Date?,
        input: MealPlanInput,
        treatments: [KBTreatment],
        vaccines: [KBVaccine],
        visits: [KBMedicalVisit],
        exams: [KBMedicalExam]
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
            refertoMaxChars: MealPlanPromptBuilder.refertoMaxChars,
            healthSnapshot: snapshot,
            subjectBirthDate: birthDate ?? snapshot?.birthDate,
            visitsForWearableContext: visits,
            purpose: .clinicalRecord
        )

        let profileSummary = MealPlanPromptBuilder.profileSummaryLines(
            birthDate: birthDate,
            snapshot: snapshot,
            profile: profile,
            input: input
        )

        return Payload(
            systemPrompt: MealPlanPromptBuilder.systemPrompt(
                responseLanguage: MealPlanPromptBuilder.responseLanguageName()
            ),
            userContent: MealPlanPromptBuilder.userContent(
                subjectName: subjectName,
                input: input,
                profileSummary: profileSummary,
                healthContext: healthContext
            ),
            profileSummary: profileSummary,
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
            messageUnits: AIAskAIPayload.mealPlanMessageUnits(totalChars: total)
        )
    }

    // MARK: - Generazione

    @MainActor
    static func generate(
        payload: Payload,
        subjectName: String,
        input: MealPlanInput
    ) async throws -> (document: MealPlanDocument, usage: MealPlanAIUsageInfo) {

        // Feature dei soli piani a pagamento (il server rifiuta comunque i Free).
        guard KBSubscriptionManager.shared.currentPlan != .free else {
            throw MealPlanAIError.planNotIncluded
        }
        guard payload.hasWeight, payload.hasHeight else {
            throw MealPlanAIError.missingHealthData
        }

        let estimate = estimate(payload: payload)
        if estimate.totalChars > AIAskAIPayload.absoluteMaxChars {
            throw MealPlanAIError.payloadTooLarge(
                chars: estimate.totalChars,
                maxChars: AIAskAIPayload.absoluteMaxChars
            )
        }

        if let current = try? await AIService.shared.fetchUsage() {
            let remaining = max(0, current.dailyLimit - current.usageToday)
            if estimate.messageUnits > remaining {
                throw MealPlanAIError.quotaWouldExceed(
                    needed: estimate.messageUnits,
                    remaining: remaining,
                    dailyLimit: current.dailyLimit
                )
            }
        }

        KBLog.ai.kbInfo(
            "MealPlanGenerator: request chars=\(estimate.totalChars) units=\(estimate.messageUnits)"
        )

        let response: AIResponse
        do {
            response = try await AIService.shared.sendMessage(
                messages: [KBAIMessage(role: .user, content: payload.userContent)],
                systemPrompt: payload.systemPrompt,
                purpose: "mealPlan"
            )
        } catch {
            // La callable scade con `deadlineExceeded`: senza questo caso l'utente
            // vedeva l'errore grezzo di Firebase.
            if (error as NSError).code == FunctionsErrorCode.deadlineExceeded.rawValue {
                throw MealPlanAIError.timedOut
            }
            throw error
        }

        let cleaned = sanitize(response.reply)
        let document = MealPlanDocument(
            subjectName: subjectName,
            input: input,
            text: cleaned,
            generatedAt: Date(),
            messageUnitsConsumed: response.messageUnitsConsumed
        )
        let usage = MealPlanAIUsageInfo(
            messageUnitsConsumed: response.messageUnitsConsumed,
            usageToday: response.usageToday,
            dailyLimit: response.dailyLimit,
            totalPayloadChars: response.totalPayloadChars ?? estimate.totalChars
        )
        KBLog.ai.kbInfo("MealPlanGenerator: done chars=\(cleaned.count) usage=\(usage.usageSummary)")
        return (document, usage)
    }

    /// Rimuove il Markdown residuo: la view rende testo semplice.
    private static func sanitize(_ text: String) -> String {
        var cleaned = text
        for token in ["**", "##", "###", "`"] {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
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
