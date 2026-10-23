//
//  HealthPatternFrequencyTests.swift
//  KidBox
//

import XCTest
@testable import KidBox

final class HealthPatternFrequencyTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testMonthlyKeyMatchesLegacyFormat() {
        XCTAssertEqual(HealthPatternFrequency.monthly.periodKey(for: date(2026, 10, 23), calendar: cal), "2026-10")
        XCTAssertEqual(HealthPatternFrequency.monthly.periodKey(for: date(2026, 1, 1), calendar: cal), "2026-01")
    }

    func testWeeklyKeyIsIsoWeek() {
        XCTAssertEqual(HealthPatternFrequency.weekly.periodKey(for: date(2026, 10, 23), calendar: cal), "2026-W43")
        // Lunedì e domenica della stessa settimana ISO.
        XCTAssertEqual(
            HealthPatternFrequency.weekly.periodKey(for: date(2026, 10, 19), calendar: cal),
            HealthPatternFrequency.weekly.periodKey(for: date(2026, 10, 25), calendar: cal)
        )
    }

    func testWeeklyKeyUsesWeekYearAcrossNewYear() {
        // 1 gennaio 2027 è venerdì: settimana 53 del 2026.
        XCTAssertEqual(HealthPatternFrequency.weekly.periodKey(for: date(2027, 1, 1), calendar: cal), "2026-W53")
    }
}
