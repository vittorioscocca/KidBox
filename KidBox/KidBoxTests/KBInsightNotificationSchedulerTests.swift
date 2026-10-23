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

    // MARK: - Preferenze

    func testCustomQuietWindowWithinTheDay() {
        var prefs = KBInsightPreferences()
        prefs.quietStartMinutes = 13 * 60
        prefs.quietEndMinutes = 15 * 60
        let d = KBInsightNotificationScheduler.deliveryDate(
            for: at(24, 14, 0), type: .todoUnassignedDueSoon, now: at(23, 12, 0), prefs: prefs, calendar: cal)
        XCTAssertEqual(d, at(24, 15, 0))
        XCTAssertEqual(
            KBInsightNotificationScheduler.outsideQuietHours(at(24, 22, 0), prefs: prefs, calendar: cal),
            at(24, 22, 0)
        )
    }

    func testNoQuietWhenStartEqualsEnd() {
        var prefs = KBInsightPreferences()
        prefs.quietStartMinutes = 0
        prefs.quietEndMinutes = 0
        XCTAssertFalse(prefs.isQuiet(minutes: 23 * 60))
    }

    func testDigestIsTodayAtSevenOrTomorrow() {
        let prefs = KBInsightPreferences()
        XCTAssertEqual(KBInsightNotificationScheduler.nextDigest(after: at(23, 12, 0), prefs: prefs, calendar: cal), at(23, 19, 0))
        XCTAssertEqual(KBInsightNotificationScheduler.nextDigest(after: at(23, 20, 0), prefs: prefs, calendar: cal), at(24, 19, 0))
    }

    func testDigestMovesOutOfCustomQuietHours() {
        var prefs = KBInsightPreferences()
        prefs.quietStartMinutes = 18 * 60
        prefs.quietEndMinutes = 7 * 60
        XCTAssertEqual(KBInsightNotificationScheduler.nextDigest(after: at(23, 12, 0), prefs: prefs, calendar: cal), at(24, 7, 0))
    }

    func testPreferencesFirestoreRoundTrip() {
        var prefs = KBInsightPreferences()
        prefs.delivery = .eveningDigest
        prefs.quietStartMinutes = 22 * 60
        prefs.quietEndMinutes = 7 * 60 + 30
        prefs.mutedTypes = [.treatmentDoseMissing]
        prefs.delegateAsk = true
        XCTAssertEqual(KBInsightPreferences(firestore: prefs.firestoreValue), prefs)
    }

    func testLocalCopyWithoutDelegateKeepsOtherChoices() throws {
        let old = #"{"delivery":"eveningDigest","quietStartMinutes":1320,"quietEndMinutes":420,"mutedTypes":[]}"#
        let p = try JSONDecoder().decode(KBInsightPreferences.self, from: Data(old.utf8))
        XCTAssertEqual(p.delivery, .eveningDigest)
        XCTAssertEqual(p.quietStartMinutes, 1320)
        XCTAssertFalse(p.delegateAsk)
    }

    func testPreferencesIgnoreBadRemoteValues() {
        let p = KBInsightPreferences(firestore: [
            "delivery": "sometimes", "quietStart": 5000, "mutedTypes": ["future_type", "grocery_stale"],
        ])
        XCTAssertEqual(p.delivery, .immediate)
        XCTAssertEqual(p.quietStartMinutes, 21 * 60 + 30)
        XCTAssertEqual(p.mutedTypes, [.groceryStale])
    }
}
