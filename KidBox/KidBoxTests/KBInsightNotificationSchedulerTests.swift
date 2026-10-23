//
//  KBInsightNotificationSchedulerTests.swift
//  KidBox
//

import XCTest
@testable import KidBox

@MainActor
final class KBInsightNotificationSchedulerTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    private func at(_ d: Int, _ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    func testFutureTimeIsKept() {
        let d = KBInsightNotificationScheduler.deliveryDate(
            for: at(24, 9, 0), type: .todoUnassignedDueSoon, now: at(23, 12, 0), calendar: cal)
        XCTAssertEqual(d, at(24, 9, 0))
    }

    func testPastTimeIsDeliveredSoon() {
        let d = KBInsightNotificationScheduler.deliveryDate(
            for: at(22, 9, 0), type: .todoUnassignedDueSoon, now: at(23, 12, 0), calendar: cal)
        XCTAssertEqual(d, at(23, 12, 0).addingTimeInterval(5))
    }

    func testLateEveningMovesToNextMorning() {
        let d = KBInsightNotificationScheduler.deliveryDate(
            for: at(23, 22, 15), type: .todoUnassignedDueSoon, now: at(23, 12, 0), calendar: cal)
        XCTAssertEqual(d, at(24, 8, 0))
    }

    func testEarlyMorningMovesToEight() {
        let d = KBInsightNotificationScheduler.deliveryDate(
            for: at(24, 6, 30), type: .todoUnassignedDueSoon, now: at(23, 12, 0), calendar: cal)
        XCTAssertEqual(d, at(24, 8, 0))
    }

    func testDosesIgnoreQuietHours() {
        let d = KBInsightNotificationScheduler.deliveryDate(
            for: at(23, 22, 15), type: .treatmentDoseMissing, now: at(23, 12, 0), calendar: cal)
        XCTAssertEqual(d, at(23, 22, 15))
    }
}
