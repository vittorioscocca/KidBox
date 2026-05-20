//
//  ClinicalRecordValueIndex.swift
//  KidBox
//

import Foundation

/// Indicizza valori estratti da esami, visite e documenti allegati.
enum ClinicalRecordValueIndex {

    static func extractAll(
        exams: [KBMedicalExam],
        visits: [KBMedicalVisit],
        documents: [KBDocument]
    ) -> [ExtractedMedicalValue] {
        var all: [ExtractedMedicalValue] = []

        for exam in exams {
            let text = [exam.name, exam.resultText ?? ""].joined(separator: "\n")
            let date = exam.resultDate ?? exam.deadline ?? exam.updatedAt
            all.append(contentsOf: MedicalValueExtractor.extract(
                from: text,
                sourceId: "exam:\(exam.id)",
                sourceLabel: exam.name,
                date: date
            ))
        }

        for visit in visits {
            let text = [visit.reason, visit.diagnosis, visit.recommendations, visit.notes]
                .compactMap { $0 }
                .joined(separator: "\n")
            all.append(contentsOf: MedicalValueExtractor.extract(
                from: text,
                sourceId: "visit:\(visit.id)",
                sourceLabel: visit.reason.isEmpty ? "Visita" : visit.reason,
                date: visit.date
            ))
        }

        for doc in documents where doc.hasExtractedText || doc.extractionStatus == .completed {
            let text = doc.extractedText ?? ""
            all.append(contentsOf: MedicalValueExtractor.extract(
                from: text,
                sourceId: "doc:\(doc.id)",
                sourceLabel: doc.title,
                date: doc.extractedTextUpdatedAt ?? doc.updatedAt
            ))
        }

        return all.sorted { $0.date < $1.date }
    }
}
