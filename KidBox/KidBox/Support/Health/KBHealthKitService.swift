//
//  KBHealthKitService.swift
//  KidBox
//

import Foundation
import HealthKit

enum KBHealthKitError: LocalizedError {
    case notAvailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Salute non è disponibile su questo dispositivo."
        case .authorizationDenied:
            return "Per importare i dati, consenti l'accesso ad Apple Salute nelle impostazioni."
        }
    }
}

@MainActor
final class KBHealthKitService {

    static let shared = KBHealthKitService()

    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let heart = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(heart) }
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        if let weight = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(weight) }
        if let blood = HKObjectType.characteristicType(forIdentifier: .bloodType) { types.insert(blood) }
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(dob) }
        if let sys = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic) { types.insert(sys) }
        if let dia = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) { types.insert(dia) }
        if let spo2 = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) { types.insert(spo2) }
        if let resting = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) { types.insert(resting) }
        if let vo2 = HKQuantityType.quantityType(forIdentifier: .vo2Max) { types.insert(vo2) }
        if let exercise = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) { types.insert(exercise) }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        types.insert(HKObjectType.workoutType())
        if #available(iOS 14.0, *) {
            types.insert(HKObjectType.electrocardiogramType())
        }
        return types
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { throw KBHealthKitError.notAvailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchSnapshot() async throws -> KBHealthImportSnapshot {
        guard isAvailable else { throw KBHealthKitError.notAvailable }

        let heartType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let mmHg = HKUnit.millimeterOfMercury()
        let percent = HKUnit.percent()
        let vo2Unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: .gramUnit(with: .kilo))
            .unitDivided(by: .minute())

        async let heartRates = recentHeartRates(type: heartType, unit: bpmUnit, limit: 15)
        async let weight = latestQuantitySample(type: weightType, unit: .gramUnit(with: .kilo))
        async let steps = stepsToday(type: stepsType)
        async let energy = sumToday(type: energyType, unit: .kilocalorie())
        async let daily = dailyActivityLastDays(days: 7, stepsType: stepsType, energyType: energyType)
        async let workouts = recentWorkouts(limit: 25)
        async let ecgs = recentECGs(limit: 10)
        async let resting = latestQuantityOptional(
            identifier: .restingHeartRate, unit: bpmUnit
        )
        async let spo2 = latestQuantityOptional(
            identifier: .oxygenSaturation, unit: percent
        )
        async let vo2 = latestQuantityOptional(
            identifier: .vo2Max, unit: vo2Unit
        )
        async let bp = latestBloodPressure()
        async let restingAvg90 = averageQuantityOverDays(identifier: .restingHeartRate, unit: bpmUnit, days: 90)
        async let vo2Avg90 = averageQuantityOverDays(identifier: .vo2Max, unit: vo2Unit, days: 90)
        async let hrvAvg90 = averageQuantityOverDays(identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), days: 90)
        async let nightlySpO2 = averageNightlySpO2Percent(days: 90)
        async let daily90 = dailyActivityLastDays(days: 90, stepsType: stepsType, energyType: energyType)
        async let weeklyExercise = averageWeeklyExerciseMinutes(days: 90)

        let (
            heartList,
            weightSample,
            stepsCount,
            energySum,
            dailyList,
            workoutList,
            ecgList,
            restingSample,
            spo2Sample,
            vo2Sample,
            bpSample,
            restingAvg90Val,
            vo2Avg90Val,
            hrvAvg90Val,
            nightlySpO2Val,
            daily90List,
            weeklyExerciseVal
        ) = try await (
            heartRates, weight, steps, energy, daily, workouts, ecgs, resting, spo2, vo2, bp,
            restingAvg90, vo2Avg90, hrvAvg90, nightlySpO2, daily90, weeklyExercise
        )

        let latestHeart = heartList.first

        var snapshot = KBHealthImportSnapshot(
            weightKg: weightSample?.value,
            weightMeasuredAt: weightSample?.date,
            heartRateBpm: latestHeart?.bpm,
            heartRateMeasuredAt: latestHeart?.measuredAt,
            restingHeartRateBpm: restingSample?.value,
            restingHeartRateMeasuredAt: restingSample?.date,
            bloodPressureSystolic: bpSample?.systolic,
            bloodPressureDiastolic: bpSample?.diastolic,
            bloodPressureMeasuredAt: bpSample?.date,
            oxygenSaturationPercent: spo2Sample.map { $0.value * 100 },
            oxygenMeasuredAt: spo2Sample?.date,
            vo2Max: vo2Sample?.value,
            vo2MaxMeasuredAt: vo2Sample?.date,
            stepsToday: stepsCount,
            activeEnergyKcal: energySum,
            recentHeartRates: heartList,
            recentDailyActivity: dailyList,
            recentWorkouts: workoutList,
            recentECGs: ecgList,
            syncedAt: Date(),
            restingHeartRateAvg90d: restingAvg90Val ?? restingSample?.value,
            vo2MaxRecent: vo2Avg90Val ?? vo2Sample?.value,
            weeklyExerciseMinutesAvg: weeklyExerciseVal,
            spo2NightlyAvgPercent: nightlySpO2Val ?? spo2Sample.map { $0.value * 100 },
            stepsDailyAvg90d: averageSteps(from: daily90List.isEmpty ? dailyList : daily90List),
            hrvSdnnMsAvg90d: hrvAvg90Val,
            wearablePeriodStart: Calendar.current.date(byAdding: .day, value: -90, to: Date()),
            wearablePeriodEnd: Date()
        )

        if let bloodObject = try? store.bloodType(),
           let mapped = Self.mapBloodType(bloodObject.bloodType) {
            snapshot.bloodGroup = mapped
        }

        if let comps = try? store.dateOfBirthComponents(),
           let dob = Calendar.current.date(from: comps) {
            snapshot.birthDate = dob
        }

        return snapshot
    }

    private struct BloodPressurePoint {
        let systolic: Double
        let diastolic: Double
        let date: Date
    }

    private func latestQuantityOptional(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async throws -> QuantityPoint? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        return try await latestQuantitySample(type: type, unit: unit)
    }

    private func latestBloodPressure() async throws -> BloodPressurePoint? {
        guard let sysType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diaType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else {
            return nil
        }
        let mmHg = HKUnit.millimeterOfMercury()
        async let sys = latestQuantitySample(type: sysType, unit: mmHg, lookbackDays: 90)
        async let dia = latestQuantitySample(type: diaType, unit: mmHg, lookbackDays: 90)
        let (s, d) = try await (sys, dia)
        guard let s, let d else { return nil }
        return BloodPressurePoint(
            systolic: s.value,
            diastolic: d.value,
            date: max(s.date, d.date)
        )
    }

    // MARK: - Queries

    private struct QuantityPoint {
        let value: Double
        let date: Date
    }

    private func recentHeartRates(
        type: HKQuantityType,
        unit: HKUnit,
        limit: Int
    ) async throws -> [KBHealthHeartRateReading] {
        let points = try await recentQuantitySamples(type: type, unit: unit, limit: limit)
        return points.map { point in
            KBHealthHeartRateReading(
                id: String(point.date.timeIntervalSince1970),
                bpm: point.value,
                measuredAt: point.date
            )
        }
    }

    private func recentQuantitySamples(
        type: HKQuantityType,
        unit: HKUnit,
        limit: Int,
        lookbackDays: Int = 30
    ) async throws -> [QuantityPoint] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let points = (samples as? [HKQuantitySample] ?? []).map { sample in
                    QuantityPoint(
                        value: sample.quantity.doubleValue(for: unit),
                        date: sample.endDate
                    )
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    private func latestQuantitySample(
        type: HKQuantityType,
        unit: HKUnit,
        lookbackDays: Int = 30
    ) async throws -> QuantityPoint? {
        try await recentQuantitySamples(type: type, unit: unit, limit: 1, lookbackDays: lookbackDays).first
    }

    private func dailyActivityLastDays(
        days: Int,
        stepsType: HKQuantityType,
        energyType: HKQuantityType
    ) async throws -> [KBHealthDailyActivity] {
        let cal = Calendar.current
        var entries: [KBHealthDailyActivity] = []

        for offset in 0..<days {
            guard let dayStart = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date())),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            async let stepCount = sumBetween(type: stepsType, unit: .count(), start: dayStart, end: dayEnd)
            async let kcal = sumBetween(type: energyType, unit: .kilocalorie(), start: dayStart, end: dayEnd)
            let (steps, energy) = try await (stepCount, kcal)

            let id = ISO8601DateFormatter().string(from: dayStart)
            entries.append(KBHealthDailyActivity(
                id: id,
                day: dayStart,
                steps: steps.map { Int($0) },
                activeEnergyKcal: energy
            ))
        }

        return entries.filter { ($0.steps ?? 0) > 0 || ($0.activeEnergyKcal ?? 0) > 0 }
    }

    private func sumBetween(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let qty = stats?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: qty.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Non blocca l'import se Salute nega o non ci sono allenamenti.
    private func recentWorkouts(limit: Int) async -> [KBHealthWorkoutEntry] {
        do {
            return try await fetchRecentWorkouts(limit: limit)
        } catch {
            KBLog.sync.kbError("recentWorkouts FAIL err=\(error.localizedDescription)")
            return []
        }
    }

    private func fetchRecentWorkouts(limit: Int) async throws -> [KBHealthWorkoutEntry] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -365, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: limit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout] ?? []).map { workout -> KBHealthWorkoutEntry in
                    let minutes = max(1, Int(round(workout.duration / 60)))
                    let kcal = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    return KBHealthWorkoutEntry(
                        id: workout.uuid.uuidString,
                        title: Self.workoutTitle(workout.workoutActivityType),
                        startedAt: workout.startDate,
                        durationMinutes: minutes,
                        activeEnergyKcal: kcal
                    )
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    @available(iOS 14.0, *)
    private func fetchRecentECGs(limit: Int) async throws -> [KBHealthECGEntry] {
        let ecgType = HKObjectType.electrocardiogramType()

        let end = Date()
        let start = Calendar.current.date(byAdding: .year, value: -2, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: ecgType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let entries = (samples as? [HKElectrocardiogram] ?? []).map { ecg -> KBHealthECGEntry in
                    let avg = ecg.averageHeartRate?.doubleValue(for: bpmUnit)
                    return KBHealthECGEntry(
                        id: ecg.uuid.uuidString,
                        recordedAt: ecg.startDate,
                        classificationLabel: Self.mapECGClassification(ecg.classification),
                        averageHeartRateBpm: avg
                    )
                }
                continuation.resume(returning: entries)
            }
            store.execute(query)
        }
    }

    private func recentECGs(limit: Int) async throws -> [KBHealthECGEntry] {
        if #available(iOS 14.0, *) {
            return try await fetchRecentECGs(limit: limit)
        }
        return []
    }

    private func averageSteps(from daily: [KBHealthDailyActivity]) -> Double? {
        let vals = daily.compactMap(\.steps).filter { $0 > 0 }
        guard !vals.isEmpty else { return nil }
        return Double(vals.reduce(0, +)) / Double(vals.count)
    }

    private func averageQuantityOverDays(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int
    ) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let avg = stats?.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: avg.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func averageNightlySpO2Percent(days: Int) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return nil }
        let samples = try await recentQuantitySamples(
            type: type,
            unit: .percent(),
            limit: 800,
            lookbackDays: days
        )
        let cal = Calendar.current
        let nightly = samples.filter {
            let h = cal.component(.hour, from: $0.date)
            return h >= 22 || h < 8
        }
        let pool = nightly.isEmpty ? samples : nightly
        guard !pool.isEmpty else { return nil }
        let avg = pool.map(\.value).reduce(0, +) / Double(pool.count)
        return avg * 100
    }

    private func averageWeeklyExerciseMinutes(days: Int) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else { return nil }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let cal = Calendar.current
        var weekTotals: [Int: Double] = [:]

        var cursor = start
        while cursor < end {
            guard let dayEnd = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            let minutes = try await sumBetween(type: type, unit: .minute(), start: cursor, end: min(dayEnd, end))
            if let minutes, minutes > 0 {
                let week = cal.component(.weekOfYear, from: cursor)
                let year = cal.component(.yearForWeekOfYear, from: cursor)
                let key = year * 100 + week
                weekTotals[key, default: 0] += minutes
            }
            cursor = dayEnd
        }
        let totals = Array(weekTotals.values)
        guard !totals.isEmpty else { return nil }
        return totals.reduce(0, +) / Double(totals.count)
    }

    private func stepsToday(type: HKQuantityType) async throws -> Int? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let value = try await sumBetween(type: type, unit: .count(), start: start, end: Date())
        return value.map { Int($0) }
    }

    private func sumToday(type: HKQuantityType, unit: HKUnit) async throws -> Double? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return try await sumBetween(type: type, unit: unit, start: start, end: Date())
    }

    // MARK: - Labels

    static func workoutTitle(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Corsa"
        case .walking: return "Camminata"
        case .cycling: return "Ciclismo"
        case .swimming: return "Nuoto"
        case .hiking: return "Escursionismo"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "Forza"
        case .highIntensityIntervalTraining: return "HIIT"
        case .dance: return "Danza"
        case .elliptical: return "Ellittica"
        case .stairClimbing: return "Scale"
        case .rowing: return "Remo"
        case .mindAndBody: return "Mente e corpo"
        case .mixedCardio: return "Cardio misto"
        case .coreTraining: return "Core"
        case .flexibility: return "Flessibilità"
        case .cooldown: return "Defaticamento"
        case .preparationAndRecovery: return "Recupero"
        case .crossTraining: return "Cross training"
        case .soccer: return "Calcio"
        case .tennis: return "Tennis"
        case .basketball: return "Basket"
        case .other: return "Allenamento"
        @unknown default: return "Allenamento"
        }
    }

    @available(iOS 14.0, *)
    static func mapECGClassification(_ classification: HKElectrocardiogram.Classification) -> String {
        switch classification {
        case .sinusRhythm: return "Ritmo sinusale"
        case .atrialFibrillation: return "Fibrillazione atriale"
        case .inconclusiveHighHeartRate: return "Inconclusivo (frequenza alta)"
        case .inconclusiveLowHeartRate: return "Inconclusivo (frequenza bassa)"
        case .inconclusivePoorReading: return "Inconclusivo (lettura scarsa)"
        case .unrecognized: return "Non riconosciuto"
        case .notSet: return "Non impostato"
        @unknown default: return "Sconosciuto"
        }
    }

    // MARK: - Blood type

    static func mapBloodType(_ type: HKBloodType) -> String? {
        switch type {
        case .aPositive:  return "A+"
        case .aNegative:  return "A-"
        case .bPositive:  return "B+"
        case .bNegative:  return "B-"
        case .abPositive: return "AB+"
        case .abNegative: return "AB-"
        case .oPositive:  return "O+"
        case .oNegative:  return "O-"
        case .notSet:
            return nil
        @unknown default:
            return nil
        }
    }
}
