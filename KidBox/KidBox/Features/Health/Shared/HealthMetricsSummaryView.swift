//
//  HealthMetricsSummaryView.swift
//  KidBox
//

import SwiftUI

struct HealthMetricsSummaryView: View {
    let snapshot: KBHealthImportSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let steps = snapshot.stepsToday, steps > 0 {
                Label("Passi oggi: \(steps)", systemImage: "figure.walk")
                    .font(.subheadline)
            }
            if let bpm = snapshot.heartRateBpm {
                Label(String(format: "Battiti: %.0f bpm", bpm), systemImage: "heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(.pink)
            }
            if let resting = snapshot.restingHeartRateBpm {
                Label(String(format: "FC a riposo: %.0f bpm", resting), systemImage: "heart.circle")
                    .font(.subheadline)
            }
            if let bp = snapshot.bloodPressureDescription {
                Label("Pressione: \(bp) mmHg", systemImage: "heart.text.square")
                    .font(.subheadline)
            }
            if let spo2 = snapshot.oxygenSaturationPercent {
                Label(String(format: "Ossigeno: %.0f%%", spo2), systemImage: "lungs")
                    .font(.subheadline)
            }
            if let vo2 = snapshot.vo2Max {
                Label(String(format: "VO₂ max: %.1f", vo2), systemImage: "bolt.heart")
                    .font(.subheadline)
            }
            if let kcal = snapshot.activeEnergyKcal, kcal > 0 {
                Label(String(format: "Energia attiva: %.0f kcal", kcal), systemImage: "flame.fill")
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}
