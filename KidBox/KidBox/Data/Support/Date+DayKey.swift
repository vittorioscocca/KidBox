//
//  Date+DayKey.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation

/// Date utilities used across KidBox.
extension Date {
    
    /// Returns a stable day key in the user's current calendar and timezone.
    ///
    /// The returned format is `YYYY-MM-DD` and is used to group daily events
    /// such as routine completions.
    ///
    /// - Important: The day key is computed at creation time to ensure
    ///   consistent behavior in offline and sync scenarios.
    func kbDayKey(calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: self)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
