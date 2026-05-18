//
//  TravelDateHelpers.swift
//  KidBox
//

import Foundation

extension Date {
    /// Giorni di viaggio inclusivi (stessa data = 1 giorno).
    func kbDayCount(from start: Date) -> Int {
        let cal = Calendar.current
        let from = cal.startOfDay(for: start)
        let to = cal.startOfDay(for: self)
        let days = cal.dateComponents([.day], from: from, to: to).day ?? 0
        return max(days + 1, 1)
    }

    /// Date ISO `yyyy-MM-dd` per ogni giorno del viaggio (partenza inclusa).
    static func kbTripDateStrings(from start: Date, dayCount: Int) -> [String] {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        return (0..<max(dayCount, 1)).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: offset, to: startDay) else { return nil }
            return kbISOString(date)
        }
    }

    static func kbISOString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar.current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}
