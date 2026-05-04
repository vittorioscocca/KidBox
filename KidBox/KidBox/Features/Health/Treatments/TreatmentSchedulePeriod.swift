//
//  TreatmentSchedulePeriod.swift
//  KidBox
//
//  Fascia oraria per etichettatura assunzioni (allineato ad Android).
//  06:00–11:59 Mattina, 12:00–15:59 Pranzo, 16:00–21:59 Sera, 22:00–05:59 Notte.
//

import Foundation
import SwiftUI

enum TreatmentSchedulePeriod: Int, CaseIterable {
    case mattina
    case pranzo
    case sera
    case notte

    var labelIt: String {
        switch self {
        case .mattina: return "Mattina"
        case .pranzo: return "Pranzo"
        case .sera: return "Sera"
        case .notte: return "Notte"
        }
    }

    /// Ordine lista giornaliera: Mattina → Pranzo → Sera → Notte.
    var sortOrdinal: Int { rawValue }

    static func from(hour: Int, minute: Int) -> TreatmentSchedulePeriod {
        let h = ((hour % 24) + 24) % 24
        let m = min(max(minute, 0), 59)
        let total = h * 60 + m
        switch total {
        case 360 ..< 720: return .mattina
        case 720 ..< 960: return .pranzo
        case 960 ..< 1320: return .sera
        default: return .notte
        }
    }

    static func from(date: Date, calendar: Calendar = .current) -> TreatmentSchedulePeriod {
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        return from(hour: h, minute: m)
    }

    static func parseScheduleTimeToMinutesOfDay(_ time: String) -> Int? {
        let normalized = time.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: ":")
            .replacingOccurrences(of: ",", with: ":")
        let parts = normalized.split(separator: ":")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = parts.first, let h = Int(first), (0 ... 23).contains(h) else { return nil }
        let minutePart = parts.count > 1 ? parts[1] : "0"
        let digits = minutePart.filter { $0.isNumber }
        let m: Int
        if digits.isEmpty {
            m = Int(minutePart) ?? 0
        } else {
            m = Int(String(digits.prefix(2))) ?? 0
        }
        return h * 60 + min(max(m, 0), 59)
    }

    static func from(scheduleTime: String) -> TreatmentSchedulePeriod? {
        guard let mins = parseScheduleTimeToMinutesOfDay(scheduleTime) else { return nil }
        return from(hour: mins / 60, minute: mins % 60)
    }

    /// Indici slot ordinati per fascia e orario (Notte post-mezzanotte dopo la sera).
    static func sortedSlotIndices(times: [String]) -> [Int] {
        times.indices.sorted {
            let o0 = schedulePeriodForTime(times[$0], slotIndexFallback: $0)?.sortOrdinal ?? Int.max
            let o1 = schedulePeriodForTime(times[$1], slotIndexFallback: $1)?.sortOrdinal ?? Int.max
            if o0 != o1 { return o0 < o1 }
            let m0 = sortMinutesWithinDay(times[$0], slotIndex: $0)
            let m1 = sortMinutesWithinDay(times[$1], slotIndex: $1)
            if m0 != m1 { return m0 < m1 }
            return $0 < $1
        }
    }

    private static func sortMinutesWithinDay(_ time: String, slotIndex: Int) -> Int {
        guard let mins = parseScheduleTimeToMinutesOfDay(time) else { return Int.max }
        let p = schedulePeriodForTime(time, slotIndexFallback: slotIndex)
            ?? from(scheduleTime: time)
            ?? .notte
        if p == .notte, mins < 6 * 60 { return mins + 24 * 60 }
        return mins
    }
}

private func treatmentSlotLabelFor(index: Int) -> String {
    let labels = ["Mattina", "Pranzo", "Sera", "Notte"]
    if index < labels.count { return labels[index] }
    return "Dose \(index + 1)"
}

func schedulePeriodForTime(_ scheduledTime: String, slotIndexFallback: Int = 0) -> TreatmentSchedulePeriod? {
    TreatmentSchedulePeriod.from(scheduleTime: scheduledTime)
        ?? {
            switch slotIndexFallback {
            case 0: return .mattina
            case 1: return .pranzo
            case 2: return .sera
            case 3: return .notte
            default: return nil
            }
        }()
}

func schedulePeriodLabel(_ scheduledTime: String, slotIndexFallback: Int = 0) -> String {
    TreatmentSchedulePeriod.from(scheduleTime: scheduledTime)?.labelIt
        ?? treatmentSlotLabelFor(index: slotIndexFallback)
}

// MARK: - Badge (Material-style chip)

private extension TreatmentSchedulePeriod {
    var badgeBackground: Color {
        switch self {
        case .mattina: return Color(red: 0.99, green: 0.98, blue: 0.76)
        case .pranzo: return Color(red: 0.86, green: 0.92, blue: 1.0)
        case .sera: return Color(red: 1.0, green: 0.93, blue: 0.84)
        case .notte: return Color(red: 0.91, green: 0.84, blue: 1.0)
        }
    }

    var badgeForeground: Color {
        switch self {
        case .mattina: return Color(red: 0.52, green: 0.30, blue: 0.05)
        case .pranzo: return Color(red: 0.12, green: 0.25, blue: 0.69)
        case .sera: return Color(red: 0.76, green: 0.25, blue: 0.05)
        case .notte: return Color(red: 0.35, green: 0.11, blue: 0.53)
        }
    }
}

struct TreatmentPeriodBadge: View {
    let period: TreatmentSchedulePeriod

    var body: some View {
        Text(period.labelIt)
            .font(.caption.weight(.semibold))
            .foregroundStyle(period.badgeForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(period.badgeBackground))
    }
}

struct NeutralPeriodBadge: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(KBTheme.primaryText(colorScheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(KBTheme.secondaryBackground(colorScheme).opacity(0.9)))
    }
}
