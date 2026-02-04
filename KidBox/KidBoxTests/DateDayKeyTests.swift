//
//  DateDayKeyTests.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import XCTest
@testable import KidBox

final class DateDayKeyTests: XCTestCase {
    
    func testDayKeySameDayReturnsSameKey() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        
        // 2026-02-04 09:00
        let d1 = cal.date(from: DateComponents(year: 2026, month: 2, day: 4, hour: 9, minute: 0))!
        // 2026-02-04 23:59
        let d2 = cal.date(from: DateComponents(year: 2026, month: 2, day: 4, hour: 23, minute: 59))!
        
        XCTAssertEqual(d1.kbDayKey(calendar: cal), d2.kbDayKey(calendar: cal))
        XCTAssertEqual(d1.kbDayKey(calendar: cal), "2026-02-04")
    }
    
    func testDayKeyDifferentDaysReturnsDifferentKeys() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        
        let d1 = cal.date(from: DateComponents(year: 2026, month: 2, day: 4, hour: 23, minute: 59))!
        let d2 = cal.date(from: DateComponents(year: 2026, month: 2, day: 5, hour: 0, minute: 1))!
        
        XCTAssertNotEqual(d1.kbDayKey(calendar: cal), d2.kbDayKey(calendar: cal))
        XCTAssertEqual(d2.kbDayKey(calendar: cal), "2026-02-05")
    }
}
