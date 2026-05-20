//
//  ClinicalRecordSummary.swift
//  KidBox
//

import Foundation
import SwiftUI

struct ClinicalRecordSnapshot: Equatable {
    let subjectName: String
    let ageDescription: String?
    let refreshedAt: Date
    let sections: [ClinicalRecordSection]
    let reportSource: ClinicalRecordReportSource?
    let globalSummary: ClinicalRecordGlobalSummary?
    var hasAnyData: Bool { sections.contains { !$0.isEmpty } }
}

struct ClinicalRecordSection: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let tintHex: UInt32
    let badgeCount: Int?
    let summary: String
    let highlights: [String]
    let isEmpty: Bool
    let reportAreaId: String?
    let overallStatus: ClinicalOverallStatus?
}

enum ClinicalRecordSummaryBuilder {

    private static let maxHighlights = 3

    /// Ordine sezioni UI.
    private static let topicUIOrder: [String] = [
        ClinicalRecordAppleHealthNarrative.areaId,
        "therapies", "pathologies", "pending", "recent_exams",
        ClinicalRecordTopicBuilder.TopicId.cardiology.rawValue,
        ClinicalRecordTopicBuilder.TopicId.gastroenterology.rawValue,
        ClinicalRecordTopicBuilder.TopicId.urology.rawValue,
        ClinicalRecordTopicBuilder.TopicId.metabolism.rawValue,
    ]

    static func build(
        subjectName: String,
        childBirthDate: Date?,
        profile: KBPediatricProfile?,
        healthSnapshot: KBHealthImportSnapshot?,
        healthSourceLabel: String,
        treatments: [KBTreatment],
        vaccines: [KBVaccine],
        visits: [KBMedicalVisit],
        exams: [KBMedicalExam],
        report: ClinicalRecordReport? = nil
    ) -> ClinicalRecordSnapshot {
        let age = childBirthDate.map { KBHealthAgeFormatting.ageDescription(from: $0) }
            ?? healthSnapshot?.ageDescription

        var sections: [ClinicalRecordSection] = []
        if let report {
            for areaId in topicUIOrder {
                guard ClinicalRecordSectionPolicy.shouldGenerateStandaloneSection(id: areaId) else { continue }
                guard let area = report.areas.first(where: { $0.id == areaId }) else { continue }
                let empty = area.bullets.isEmpty && area.narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if areaId == "therapies" && treatments.isEmpty && empty { continue }
                if areaId == "pending" && empty { continue }
                if empty { continue }
                sections.append(sectionForArea(area))
            }
        }

        if sections.isEmpty {
            sections = fallbackSections(
                treatments: treatments,
                exams: exams,
                report: report
            )
        }

        return ClinicalRecordSnapshot(
            subjectName: subjectName,
            ageDescription: age?.isEmpty == false ? age : nil,
            refreshedAt: report?.generatedAt ?? Date(),
            sections: sections,
            reportSource: report?.source,
            globalSummary: report?.globalSummary
        )
    }

    private static func sectionForArea(_ area: ClinicalRecordReportArea) -> ClinicalRecordSection {
        let topic = ClinicalRecordTopicBuilder.TopicId(rawValue: area.id)
        if let topic {
            return topicSection(topic: topic, area: area)
        }
        let icon: (String, UInt32) = switch area.id {
        case ClinicalRecordAppleHealthNarrative.areaId: ("figure.run", 0x34C759)
        case "pathologies": ("heart.text.square.fill", 0xE85A5A)
        case "recent_exams": ("doc.text.magnifyingglass", 0x40A6BF)
        default: ("folder.fill", 0x5996D9)
        }
        var highlights: [String] = []
        if let narrative = area.analisiNarrativa, !narrative.isEmpty {
            highlights.append(clip(narrative))
        } else if let trend = area.trendNarrative, !trend.isEmpty {
            highlights.append(clip(trend.split(separator: "\n").first.map(String.init) ?? trend))
        }
        highlights.append(contentsOf: area.bullets.prefix(max(0, maxHighlights - highlights.count)))
        return ClinicalRecordSection(
            id: area.id,
            title: area.title,
            systemImage: icon.0,
            tintHex: icon.1,
            badgeCount: area.bullets.isEmpty ? nil : area.bullets.count,
            summary: area.summary,
            highlights: Array(highlights.prefix(maxHighlights)),
            isEmpty: false,
            reportAreaId: area.id,
            overallStatus: area.overallStatus
        )
    }

    private static func topicSection(
        topic: ClinicalRecordTopicBuilder.TopicId,
        area: ClinicalRecordReportArea
    ) -> ClinicalRecordSection {
        var highlights: [String] = []
        if let narrative = area.analisiNarrativa, !narrative.isEmpty {
            highlights.append(clip(narrative))
        } else if let trend = area.trendNarrative, !trend.isEmpty {
            let firstTrendLine = trend.split(separator: "\n").first.map(String.init) ?? trend
            highlights.append(clip(firstTrendLine))
        }
        highlights.append(contentsOf: area.bullets.prefix(max(0, maxHighlights - highlights.count)))
        return ClinicalRecordSection(
            id: topic.rawValue,
            title: topic.title,
            systemImage: topic.systemImage,
            tintHex: topic.tintHex,
            badgeCount: area.bullets.isEmpty ? nil : area.bullets.count,
            summary: area.summary,
            highlights: Array(highlights.prefix(maxHighlights)),
            isEmpty: false,
            reportAreaId: topic.rawValue,
            overallStatus: area.overallStatus
        )
    }

    /// Se il report non è ancora stato generato, mostra almeno terapie e attesa.
    private static func fallbackSections(
        treatments: [KBTreatment],
        exams: [KBMedicalExam],
        report: ClinicalRecordReport?
    ) -> [ClinicalRecordSection] {
        var out: [ClinicalRecordSection] = []
        if !treatments.isEmpty {
            out.append(ClinicalRecordSection(
                id: ClinicalRecordTopicBuilder.TopicId.therapies.rawValue,
                title: ClinicalRecordTopicBuilder.TopicId.therapies.title,
                systemImage: ClinicalRecordTopicBuilder.TopicId.therapies.systemImage,
                tintHex: ClinicalRecordTopicBuilder.TopicId.therapies.tintHex,
                badgeCount: treatments.count,
                summary: "\(treatments.count) in corso",
                highlights: treatments.prefix(3).map { "\($0.drugName) · \($0.dosageValue, default: "%.0f") \($0.dosageUnit)" },
                isEmpty: false,
                reportAreaId: ClinicalRecordTopicBuilder.TopicId.therapies.rawValue,
                overallStatus: nil
            ))
        }
        let pending = exams.filter { $0.status == .pending || $0.status == .booked }
        if !pending.isEmpty {
            out.append(ClinicalRecordSection(
                id: ClinicalRecordTopicBuilder.TopicId.pending.rawValue,
                title: ClinicalRecordTopicBuilder.TopicId.pending.title,
                systemImage: ClinicalRecordTopicBuilder.TopicId.pending.systemImage,
                tintHex: ClinicalRecordTopicBuilder.TopicId.pending.tintHex,
                badgeCount: pending.count,
                summary: "\(pending.count) da eseguire",
                highlights: pending.prefix(3).map { $0.name },
                isEmpty: false,
                reportAreaId: ClinicalRecordTopicBuilder.TopicId.pending.rawValue,
                overallStatus: .daMonitorare
            ))
        }
        return out
    }

    private static func clip(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 72 { return t }
        return String(t.prefix(71)) + "…"
    }
}

extension ClinicalRecordSection {
    var tintColor: Color {
        Color(
            red: Double((tintHex >> 16) & 0xFF) / 255,
            green: Double((tintHex >> 8) & 0xFF) / 255,
            blue: Double(tintHex & 0xFF) / 255
        )
    }
}
