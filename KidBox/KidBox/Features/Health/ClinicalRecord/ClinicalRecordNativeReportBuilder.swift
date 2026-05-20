//
//  ClinicalRecordNativeReportBuilder.swift
//  KidBox
//

import Foundation

enum ClinicalRecordNativeReportBuilder {

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

    static func build(_ input: Input) -> ClinicalRecordReport {
        ClinicalRecordTopicBuilder.build(
            input: ClinicalRecordTopicBuilder.Input(
                subjectName: input.subjectName,
                birthDate: input.birthDate,
                residence: input.residence,
                profile: input.profile,
                healthSnapshot: input.healthSnapshot,
                healthSourceLabel: input.healthSourceLabel,
                treatments: input.treatments,
                vaccines: input.vaccines,
                visits: input.visits,
                exams: input.exams,
                documents: input.documents,
                extractedValues: input.extractedValues
            )
        )
    }
}
