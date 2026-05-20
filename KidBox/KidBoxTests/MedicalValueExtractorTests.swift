//
//  MedicalValueExtractorTests.swift
//  KidBoxTests
//

import XCTest
@testable import KidBox

final class MedicalValueExtractorTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_715_000_000)

    func testExtractsBloodPressure() {
        let text = "PA base: 120/80 mmHg, PA max: 160/80 mmHg"
        let values = MedicalValueExtractor.extract(from: text, sourceId: "t1", sourceLabel: "Prova", date: date)
        XCTAssertTrue(values.contains { $0.kind == .bloodPressure && $0.systolic == 120 && $0.diastolic == 80 })
    }

    func testExtractsAngioma14mm() {
        let text = "Agioma di 14 mm sul lobo sx del fegato"
        let values = MedicalValueExtractor.extract(from: text, sourceId: "eco1", sourceLabel: "Eco addome", date: date)
        let lesion = values.first { $0.kind == .lesion }
        XCTAssertNotNil(lesion)
        XCTAssertEqual(lesion?.dimensionMm ?? 0, 14, accuracy: 0.1)
    }

    func testExtractsHeartRateBpm() {
        let text = "Frequenza cardiaca massima: 148 bpm (86% della FCMT)"
        let values = MedicalValueExtractor.extract(from: text, sourceId: "s1", sourceLabel: "Sforzo", date: date)
        XCTAssertTrue(values.contains { $0.kind == .heartRate && ($0.numericValue ?? 0) == 148 })
    }

    func testExtractsStressTestLoad() {
        let text = "Buona capacità funzionale (150 W = 7.3 METS)"
        let values = MedicalValueExtractor.extract(from: text, sourceId: "s1", sourceLabel: "Sforzo", date: date)
        XCTAssertTrue(values.contains { $0.parameterName.contains("Carico") && ($0.numericValue ?? 0) == 150 })
        XCTAssertTrue(values.contains { $0.parameterName == "METS" })
    }

    func testExtractsLDL() {
        let text = "LDL: 97 mg/dl, HDL: 32 mg/dl"
        let values = MedicalValueExtractor.extract(from: text, sourceId: "lab", sourceLabel: "Sangue", date: date)
        XCTAssertTrue(values.contains { $0.parameterName == "LDL" && ($0.numericValue ?? 0) == 97 })
        XCTAssertTrue(values.contains { $0.parameterName == "HDL" && ($0.numericValue ?? 0) == 32 })
    }

    func testExtractsLabWithoutUnitDoesNotCrash() {
        let text = "Glicemia 97\nLDL 110"
        let values = MedicalValueExtractor.extract(from: text, sourceId: "lab", sourceLabel: "Sangue", date: date)
        XCTAssertTrue(values.contains { $0.parameterName == "Glicemia" && ($0.numericValue ?? 0) == 97 })
        XCTAssertTrue(values.contains { $0.parameterName == "LDL" && ($0.numericValue ?? 0) == 110 })
    }

    func testTrendAnalyzerCardiologyIncludesBloodPressure() {
        let values: [ExtractedMedicalValue] = [
            makeBP(sys: 120, dia: 70, year: 2024),
            makeBP(sys: 121, dia: 84, year: 2026),
        ]
        let trend = TrendAnalyzer.buildSpecialtyTrend(
            specialtyId: ClinicalRecordTopicBuilder.TopicId.cardiology.rawValue,
            specialtyTitle: "Cardiologia",
            values: values,
            chronologyLines: []
        )
        XCTAssertNotNil(trend)
        XCTAssertTrue(trend?.narrativeAnalysis.contains("Pressione") ?? false)
    }

    private func makeBP(sys: Int, dia: Int, year: Int) -> ExtractedMedicalValue {
        var comp = DateComponents()
        comp.year = year
        comp.month = 6
        comp.day = 1
        let d = Calendar.current.date(from: comp) ?? date
        return ExtractedMedicalValue(
            kind: .bloodPressure,
            parameterName: "Pressione arteriosa",
            numericValue: Double(sys),
            textValue: "\(sys)/\(dia) mmHg",
            unit: "mmHg",
            systolic: sys,
            diastolic: dia,
            lesionType: nil,
            dimensionMm: nil,
            date: d,
            sourceId: "exam:\(year)",
            sourceLabel: "Visita"
        )
    }
}
