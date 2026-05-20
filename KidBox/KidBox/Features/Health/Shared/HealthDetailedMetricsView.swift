//
//  HealthDetailedMetricsView.swift
//  KidBox
//

import SwiftUI

struct HealthDetailedMetricsView: View {
    let snapshot: KBHealthImportSnapshot
    /// Se false, gli allenamenti sono già mostrati nella dashboard principale.
    var includeWorkouts: Bool = false

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if includeWorkouts {
                workoutsSection
            }
            heartRatesSection
            dailyActivitySection
            ecgSection
        }
    }

    @ViewBuilder
    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Allenamenti")
                .font(.headline)
            if snapshot.recentWorkouts.isEmpty {
                Text("Nessun allenamento negli ultimi 12 mesi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.recentWorkouts) { workout in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(workout.title, systemImage: "figure.run")
                            .font(.subheadline)
                        HStack(spacing: 8) {
                            Text(Self.dayFormatter.string(from: workout.startedAt))
                            if let min = workout.durationMinutes, min > 0 {
                                Text("· \(min) min")
                            }
                            if let kcal = workout.activeEnergyKcal, kcal > 0 {
                                Text(String(format: "· %.0f kcal", kcal))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var heartRatesSection: some View {
        if !snapshot.recentHeartRates.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ultimi battiti")
                    .font(.headline)
                ForEach(snapshot.recentHeartRates) { reading in
                    HStack {
                        Label(
                            String(format: "%.0f bpm", reading.bpm),
                            systemImage: "heart.fill"
                        )
                        .foregroundStyle(.pink)
                        Spacer()
                        Text(Self.timeFormatter.string(from: reading.measuredAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dailyActivitySection: some View {
        let days = snapshot.recentDailyActivity.filter {
            ($0.steps ?? 0) > 0 || ($0.activeEnergyKcal ?? 0) > 0
        }
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Passi e energia (7 giorni)")
                    .font(.headline)
                ForEach(days) { day in
                    HStack {
                        Text(Self.dayFormatter.string(from: day.day))
                            .font(.subheadline)
                        Spacer()
                        if let steps = day.steps, steps > 0 {
                            Text("\(steps) passi")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let kcal = day.activeEnergyKcal, kcal > 0 {
                            Text(String(format: "%.0f kcal", kcal))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var ecgSection: some View {
        if !snapshot.recentECGs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("ECG")
                    .font(.headline)
                ForEach(snapshot.recentECGs) { ecg in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(ecg.classificationLabel, systemImage: "waveform.path.ecg")
                            .font(.subheadline)
                        HStack(spacing: 8) {
                            Text(Self.dayFormatter.string(from: ecg.recordedAt))
                            Text(Self.timeFormatter.string(from: ecg.recordedAt))
                            if let bpm = ecg.averageHeartRateBpm {
                                Text(String(format: "· %.0f bpm", bpm))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
