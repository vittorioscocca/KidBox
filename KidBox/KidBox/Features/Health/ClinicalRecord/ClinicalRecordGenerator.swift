//
//  ClinicalRecordGenerator.swift
//  KidBox
//

import Foundation
import SwiftData

enum ClinicalRecordGenerator {

    @MainActor
    static func buildContent(
        modelContext: ModelContext,
        familyId: String,
        childId: String,
        subjectName: String,
        childBirthDate: Date?,
        treatments: [KBTreatment],
        vaccines: [KBVaccine],
        visits: [KBMedicalVisit],
        exams: [KBMedicalExam]
    ) -> [String] {
        let profile = fetchProfile(modelContext: modelContext, childId: childId)
        let healthSnapshot = KBHealthLinkStore.load(childId: childId)
        let (byExam, byVisit, byTreatment) = fetchHealthDocuments(
            modelContext: modelContext,
            familyId: familyId,
            childId: childId
        )
        return ClinicalRecordBuilder.buildLines(
            subjectName: subjectName,
            childBirthDate: childBirthDate,
            profile: profile,
            healthSnapshot: healthSnapshot,
            healthSourceLabel: "Apple Salute",
            treatments: treatments,
            vaccines: vaccines,
            visits: visits,
            exams: exams,
            documentsByExamId: byExam,
            documentsByVisitId: byVisit,
            documentsByTreatmentId: byTreatment
        )
    }

    @MainActor
    static func exportPDF(report: ClinicalRecordReport?, lines: [String], childId: String) throws -> URL {
        let data: Data
        if let report, report.globalSummary != nil || !report.specialtyTrends.isEmpty {
            data = ClinicalRecordStructuredPDF.render(report: report)
        } else {
            data = ClinicalRecordPDFService.renderPDF(lines: lines)
        }
        let url = ClinicalRecordStore.pdfURL(childId: childId)
        try data.write(to: url, options: .atomic)
        KBLog.persistence.kbInfo("ClinicalRecord PDF exported childId=\(childId) bytes=\(data.count)")
        return url
    }

    @MainActor
    static func generate(
        modelContext: ModelContext,
        familyId: String,
        childId: String,
        subjectName: String,
        childBirthDate: Date?,
        treatments: [KBTreatment],
        vaccines: [KBVaccine],
        visits: [KBMedicalVisit],
        exams: [KBMedicalExam]
    ) throws -> URL {
        let lines = buildContent(
            modelContext: modelContext,
            familyId: familyId,
            childId: childId,
            subjectName: subjectName,
            childBirthDate: childBirthDate,
            treatments: treatments,
            vaccines: vaccines,
            visits: visits,
            exams: exams
        )
        return try exportPDF(report: nil, lines: lines, childId: childId)
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
                let id = String(tag.dropFirst(5))
                byExam[id, default: []].append(doc)
            } else if tag.hasPrefix("visit:") {
                let id = String(tag.dropFirst(6))
                byVisit[id, default: []].append(doc)
            } else if tag.hasPrefix("treatment:") {
                let id = String(tag.dropFirst(10))
                byTreatment[id, default: []].append(doc)
            }
        }
        return (byExam, byVisit, byTreatment)
    }
}
