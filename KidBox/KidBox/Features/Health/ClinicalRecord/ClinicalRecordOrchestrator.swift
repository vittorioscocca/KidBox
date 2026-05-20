//
//  ClinicalRecordOrchestrator.swift
//  KidBox
//

import Foundation
import SwiftData
import FirebaseAuth

enum ClinicalRecordOrchestrator {

    struct Bundle: Equatable {
        let report: ClinicalRecordReport
        let snapshot: ClinicalRecordSnapshot
        let exportLines: [String]
        let aiUsage: ClinicalRecordAIUsageInfo?
    }

    @MainActor
    static func build(
        modelContext: ModelContext,
        familyId: String,
        childId: String,
        subjectName: String,
        childBirthDate: Date?,
        treatments: [KBTreatment],
        vaccines: [KBVaccine],
        visits: [KBMedicalVisit],
        exams: [KBMedicalExam],
        useAI: Bool = true
    ) async throws -> Bundle {
        let profile = fetchProfile(modelContext: modelContext, childId: childId)
        let health = KBHealthLinkStore.load(childId: childId)
        let residence = resolveResidence(modelContext: modelContext, childId: childId)

        let (byExam, byVisit, byTreatment) = fetchHealthDocuments(
            modelContext: modelContext,
            familyId: familyId,
            childId: childId
        )
        let allDocs = Set(byExam.values.flatMap { $0 } + byVisit.values.flatMap { $0 } + byTreatment.values.flatMap { $0 })
        let extracted = ClinicalRecordValueIndex.extractAll(
            exams: exams,
            visits: visits,
            documents: Array(allDocs)
        )

        let input = ClinicalRecordNativeReportBuilder.Input(
            subjectName: subjectName,
            birthDate: childBirthDate,
            residence: residence,
            profile: profile,
            healthSnapshot: health,
            healthSourceLabel: "Apple Salute",
            treatments: treatments,
            vaccines: vaccines,
            visits: visits,
            exams: exams,
            documents: Array(allDocs),
            extractedValues: extracted
        )

        var report = filterExcludedStandaloneAreas(ClinicalRecordNativeReportBuilder.build(input))
        var aiUsage: ClinicalRecordAIUsageInfo?

        if useAI {
            let healthContext = HealthContextBuilder.buildSystemPrompt(
                subjectName: subjectName,
                subjectId: childId,
                exams: exams,
                visits: visits,
                treatments: treatments.filter { $0.petId.isEmpty },
                vaccines: vaccines,
                documentsByExamId: byExam,
                documentsByVisitId: byVisit,
                documentsByTreatmentId: byTreatment,
                refertoMaxChars: 2_500,
                healthSnapshot: health,
                subjectBirthDate: childBirthDate,
                visitsForWearableContext: visits,
                purpose: .clinicalRecord
            )
            let enhanced = try await ClinicalRecordAISynthesizer.enhance(
                nativeReport: report,
                healthContext: healthContext
            )
            aiUsage = enhanced.usage
            report = filterExcludedStandaloneAreas(ClinicalRecordReport(
                generatedAt: enhanced.report.generatedAt,
                source: .aiEnhanced,
                subjectName: enhanced.report.subjectName,
                headerLines: enhanced.report.headerLines,
                areas: report.areas,
                fullDocumentLines: enhanced.report.fullDocumentLines,
                globalSummary: report.globalSummary,
                specialtyTrends: report.specialtyTrends
            ))
        }

        ClinicalRecordStore.saveReport(report, childId: childId)

        syncExtractedValuesToFirestore(
            familyId: familyId,
            documents: Array(allDocs)
        )

        let snapshot = ClinicalRecordSummaryBuilder.build(
            subjectName: subjectName,
            childBirthDate: childBirthDate,
            profile: profile,
            healthSnapshot: health,
            healthSourceLabel: "Apple Salute",
            treatments: treatments,
            vaccines: vaccines,
            visits: visits,
            exams: exams,
            report: report
        )

        return Bundle(
            report: report,
            snapshot: snapshot,
            exportLines: report.fullDocumentLines,
            aiUsage: aiUsage
        )
    }

    /// Stima messaggi AI prima di «Aggiorna» (parity con askAI).
    @MainActor
    static func estimateAIMessageUnits(
        modelContext: ModelContext,
        familyId: String,
        childId: String,
        subjectName: String,
        childBirthDate: Date?,
        treatments: [KBTreatment],
        vaccines: [KBVaccine],
        visits: [KBMedicalVisit],
        exams: [KBMedicalExam]
    ) -> (messageUnits: Int, isLargeContext: Bool)? {
        guard AISettings.shared.isEnabled, KBSubscriptionManager.shared.currentPlan.includesAI else {
            return nil
        }
        let profile = fetchProfile(modelContext: modelContext, childId: childId)
        let health = KBHealthLinkStore.load(childId: childId)
        let residence = resolveResidence(modelContext: modelContext, childId: childId)
        let (byExam, byVisit, byTreatment) = fetchHealthDocuments(
            modelContext: modelContext, familyId: familyId, childId: childId
        )
        let allDocs = Set(byExam.values.flatMap { $0 } + byVisit.values.flatMap { $0 } + byTreatment.values.flatMap { $0 })
        let extracted = ClinicalRecordValueIndex.extractAll(
            exams: exams, visits: visits, documents: Array(allDocs)
        )
        let input = ClinicalRecordNativeReportBuilder.Input(
            subjectName: subjectName,
            birthDate: childBirthDate,
            residence: residence,
            profile: profile,
            healthSnapshot: health,
            healthSourceLabel: "Apple Salute",
            treatments: treatments,
            vaccines: vaccines,
            visits: visits,
            exams: exams,
            documents: Array(allDocs),
            extractedValues: extracted
        )
        let native = ClinicalRecordNativeReportBuilder.build(input)
        let healthContext = HealthContextBuilder.buildSystemPrompt(
            subjectName: subjectName,
            subjectId: childId,
            exams: exams,
            visits: visits,
            treatments: treatments.filter { $0.petId.isEmpty },
            vaccines: vaccines,
            documentsByExamId: byExam,
            documentsByVisitId: byVisit,
            documentsByTreatmentId: byTreatment,
            refertoMaxChars: 2_500,
            healthSnapshot: health,
            subjectBirthDate: childBirthDate,
            visitsForWearableContext: visits,
            purpose: .clinicalRecord
        )
        let est = ClinicalRecordAISynthesizer.estimatePayload(
            nativeReport: native,
            healthContext: healthContext
        )
        return (est.messageUnits, est.isLargeContext)
    }

    @MainActor
    private static func resolveResidence(modelContext: ModelContext, childId: String) -> String? {
        guard let uid = Auth.auth().currentUser?.uid, uid == childId else { return nil }
        var desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
        desc.fetchLimit = 1
        return try? modelContext.fetch(desc).first?.familyAddress
    }

    @MainActor
    private static func fetchProfile(
        modelContext: ModelContext,
        childId: String
    ) -> KBPediatricProfile? {
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
    ) -> (
        [String: [KBDocument]],
        [String: [KBDocument]],
        [String: [KBDocument]]
    ) {
        let fid = familyId
        let cid = childId
        var descriptor = FetchDescriptor<KBDocument>(
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

    private static func filterExcludedStandaloneAreas(_ report: ClinicalRecordReport) -> ClinicalRecordReport {
        var filtered = report
        filtered.areas = report.areas.filter {
            ClinicalRecordSectionPolicy.shouldGenerateStandaloneSection(id: $0.id)
        }
        return filtered
    }

    /// Sincronizza valori laboratorio su Firestore solo per referti con OCR e valori estratti (dopo AI, per non competere con askAI).
    private static func syncExtractedValuesToFirestore(
        familyId: String,
        documents: [KBDocument]
    ) {
        Task.detached(priority: .utility) {
            for doc in documents {
                let text = doc.extractedText ?? ""
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let values = MedicalValueExtractor.extract(
                    from: text,
                    sourceId: "doc:\(doc.id)",
                    sourceLabel: doc.title,
                    date: doc.extractedTextUpdatedAt ?? doc.updatedAt
                )
                guard !values.isEmpty else { continue }
                await ClinicalExtractedValuesRemoteStore.replaceForDocument(
                    familyId: familyId,
                    documentId: doc.id,
                    values: values
                )
            }
        }
    }
}
