//
//  KBHealthImportSnapshot.swift
//  KidBox
//

import Foundation

struct KBHealthHeartRateReading: Sendable, Equatable, Codable, Identifiable {
    var id: String
    var bpm: Double
    var measuredAt: Date
}

struct KBHealthDailyActivity: Sendable, Equatable, Codable, Identifiable {
    var id: String
    var day: Date
    var steps: Int?
    var activeEnergyKcal: Double?
}

struct KBHealthWorkoutEntry: Sendable, Equatable, Codable, Identifiable {
    var id: String
    var title: String
    var startedAt: Date
    var durationMinutes: Int?
    var activeEnergyKcal: Double?
}

struct KBHealthECGEntry: Sendable, Equatable, Codable, Identifiable {
    var id: String
    var recordedAt: Date
    var classificationLabel: String
    var averageHeartRateBpm: Double?
}

/// Dati letti dall'app Salute (HealthKit) per un profilo bambino.
struct KBHealthImportSnapshot: Sendable, Equatable, Codable {
    /// Data di nascita letta da Apple Salute (profilo Salute su iPhone) o modificata in scheda.
    var birthDate: Date?
    var weightKg: Double?
    var weightMeasuredAt: Date?
    var bloodGroup: String?
    var heartRateBpm: Double?
    var heartRateMeasuredAt: Date?
    var restingHeartRateBpm: Double?
    var restingHeartRateMeasuredAt: Date?
    var bloodPressureSystolic: Double?
    var bloodPressureDiastolic: Double?
    var bloodPressureMeasuredAt: Date?
    var oxygenSaturationPercent: Double?
    var oxygenMeasuredAt: Date?
    var vo2Max: Double?
    var vo2MaxMeasuredAt: Date?
    var stepsToday: Int?
    var activeEnergyKcal: Double?
    var recentHeartRates: [KBHealthHeartRateReading] = []
    var recentDailyActivity: [KBHealthDailyActivity] = []
    var recentWorkouts: [KBHealthWorkoutEntry] = []
    var recentECGs: [KBHealthECGEntry] = []
    var syncedAt: Date = Date()

    // Medie / wearable (ultimi ~90 giorni, da HealthKit)
    var restingHeartRateAvg90d: Double?
    var vo2MaxRecent: Double?
    var weeklyExerciseMinutesAvg: Double?
    var spo2NightlyAvgPercent: Double?
    var stepsDailyAvg90d: Double?
    var hrvSdnnMsAvg90d: Double?
    var wearablePeriodStart: Date?
    var wearablePeriodEnd: Date?

    var hasCardiacOrActivity: Bool {
        heartRateBpm != nil
            || restingHeartRateBpm != nil
            || bloodPressureSystolic != nil
            || oxygenSaturationPercent != nil
            || vo2Max != nil
            || !recentHeartRates.isEmpty
            || (stepsToday ?? 0) > 0
            || activeEnergyKcal != nil
            || recentDailyActivity.contains { ($0.steps ?? 0) > 0 || ($0.activeEnergyKcal ?? 0) > 0 }
            || !recentWorkouts.isEmpty
            || !recentECGs.isEmpty
            || hasWearableExtendedMetrics
    }

    var hasWearableExtendedMetrics: Bool {
        restingHeartRateAvg90d != nil
            || vo2MaxRecent != nil
            || weeklyExerciseMinutesAvg != nil
            || spo2NightlyAvgPercent != nil
            || stepsDailyAvg90d != nil
            || hrvSdnnMsAvg90d != nil
    }

    var hasProfileFields: Bool {
        birthDate != nil || weightKg != nil || !(bloodGroup?.isEmpty ?? true)
    }

    var ageDescription: String? {
        guard let birthDate else { return nil }
        return KBHealthAgeFormatting.ageDescription(from: birthDate)
    }

    var bloodPressureDescription: String? {
        guard let sys = bloodPressureSystolic, let dia = bloodPressureDiastolic else { return nil }
        return String(format: "%.0f/%.0f", sys, dia)
    }
}
