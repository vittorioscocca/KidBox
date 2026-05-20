//
//  ClinicalRecordReport.swift
//  KidBox
//

import Foundation

enum ClinicalRecordReportSource: String, Codable {
    case native
    case aiEnhanced
}

struct ClinicalRecordReportArea: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let summary: String
    let narrative: String
    let trendNarrative: String?
    let bullets: [String]
    var overallStatus: ClinicalOverallStatus?
    var analisiNarrativa: String?
    var parameters: [ParameterTrend]?
}

struct ClinicalRecordReport: Equatable, Codable {
    var generatedAt: Date
    var source: ClinicalRecordReportSource
    var subjectName: String
    var headerLines: [String]
    var areas: [ClinicalRecordReportArea]
    var fullDocumentLines: [String]
    var globalSummary: ClinicalRecordGlobalSummary?
    var specialtyTrends: [SpecialtyTrendSnapshot]

    var hasContent: Bool { !fullDocumentLines.isEmpty || !areas.isEmpty }

    init(
        generatedAt: Date = Date(),
        source: ClinicalRecordReportSource = .native,
        subjectName: String,
        headerLines: [String] = [],
        areas: [ClinicalRecordReportArea] = [],
        fullDocumentLines: [String] = [],
        globalSummary: ClinicalRecordGlobalSummary? = nil,
        specialtyTrends: [SpecialtyTrendSnapshot] = []
    ) {
        self.generatedAt = generatedAt
        self.source = source
        self.subjectName = subjectName
        self.headerLines = headerLines
        self.areas = areas
        self.fullDocumentLines = fullDocumentLines
        self.globalSummary = globalSummary
        self.specialtyTrends = specialtyTrends
    }
}
