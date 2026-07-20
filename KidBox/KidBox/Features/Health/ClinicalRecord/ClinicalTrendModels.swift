//
//  ClinicalTrendModels.swift
//  KidBox
//

import Foundation

enum ClinicalTrendDirection: String, Codable, Equatable {
    case stabile
    case inAumento
    case inDiminuzione
}

enum ClinicalOverallStatus: String, Codable, Equatable {
    case stabile
    case migliorato
    case peggiorato
    case daMonitorare
    case attenzione

    /// `String` (non `LocalizedStringKey`): interpolato in stringhe di contesto/report
    /// (es. `ClinicalRecordTopicBuilder`), quindi passa da NSLocalizedString.
    var badgeLabel: String {
        switch self {
        case .stabile: return NSLocalizedString("Stabile", comment: "Clinical status: stable")
        case .migliorato: return NSLocalizedString("Migliorato", comment: "Clinical status: improved")
        case .peggiorato: return NSLocalizedString("Attenzione", comment: "Clinical status: attention")
        case .daMonitorare: return NSLocalizedString("Da monitorare", comment: "Clinical status: to monitor")
        case .attenzione: return NSLocalizedString("Attenzione", comment: "Clinical status: attention")
        }
    }

    var emoji: String {
        switch self {
        case .stabile: return "🟢"
        case .migliorato: return "🔵"
        case .peggiorato, .attenzione: return "🔴"
        case .daMonitorare: return "🟡"
        }
    }
}

enum ExtractedValueKind: String, Codable, Equatable {
    case bloodPressure
    case lesion
    case lab
    case heartRate
    case weight
    case stressTest
    case generic
}

struct ExtractedMedicalValue: Codable, Equatable, Identifiable {
    var id: String { "\(sourceId)-\(kind.rawValue)-\(parameterName)-\(date.timeIntervalSince1970)" }
    let kind: ExtractedValueKind
    let parameterName: String
    let numericValue: Double?
    let textValue: String?
    let unit: String?
    let systolic: Int?
    let diastolic: Int?
    let lesionType: String?
    let dimensionMm: Double?
    let date: Date
    let sourceId: String
    let sourceLabel: String
}

struct ParameterTrendPoint: Codable, Equatable {
    let date: Date
    let displayValue: String
    let numericValue: Double?
    let source: String
}

struct ParameterTrend: Codable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let points: [ParameterTrendPoint]
    let trend: ClinicalTrendDirection
    let deltaPercent: Double?
    let clinicalNote: String?
}

struct SpecialtyTrendSnapshot: Codable, Equatable, Identifiable {
    var id: String { specialtyId }
    let specialtyId: String
    let specialtyTitle: String
    let parameters: [ParameterTrend]
    let narrativeAnalysis: String
    let overallStatus: ClinicalOverallStatus
    let lastUpdated: Date
}

struct GlobalStatusLine: Codable, Equatable, Identifiable {
    var id: String { specialtyTitle }
    let specialtyTitle: String
    let status: ClinicalOverallStatus
    let headline: String
}

struct ClinicalRecordGlobalSummary: Codable, Equatable {
    let monitoredSpecialtiesCount: Int
    let attentionCount: Int
    let lastUpdated: Date
    let activeTherapyNames: [String]
    let nextAppointmentLine: String?
    let statusLines: [GlobalStatusLine]
}
