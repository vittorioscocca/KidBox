//
//  AppleHealthDashboardView.swift
//  KidBox
//

import SwiftUI

/// Dashboard metriche Apple Salute (griglia + allenamenti; cronologia al tap).
struct AppleHealthDashboardView: View {
    let snapshot: KBHealthImportSnapshot
    let childAgeDescription: String?
    let childWeightKg: Double?
    @Environment(\.colorScheme) private var colorScheme
    @State private var showHistorySheet = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let childAgeDescription, !childAgeDescription.isEmpty {
                profileBanner(age: childAgeDescription)
            }

            if snapshot.hasCardiacOrActivity || snapshot.hasProfileFields {
                Text("Metriche")
                    .font(.headline)
                    .foregroundStyle(KBTheme.primaryText(colorScheme))

                LazyVGrid(columns: columns, spacing: 12) {
                    metricTile(
                        title: "Passi oggi",
                        value: snapshot.stepsToday.map { "\($0)" } ?? "—",
                        subtitle: "Attività",
                        systemImage: "figure.walk",
                        tint: Color(red: 0.2, green: 0.75, blue: 0.45)
                    )
                    metricTile(
                        title: "Allenamenti",
                        value: workoutsSummaryValue,
                        subtitle: workoutsSummarySubtitle,
                        systemImage: "figure.run",
                        tint: Color(red: 0.55, green: 0.4, blue: 0.95)
                    )
                    metricTile(
                        title: "Peso",
                        value: weightValue,
                        subtitle: "Corpo",
                        systemImage: "scalemass.fill",
                        tint: Color(red: 0.35, green: 0.55, blue: 0.95)
                    )
                    metricTile(
                        title: "Battiti",
                        value: bpm(snapshot.heartRateBpm),
                        subtitle: "Ultima FC",
                        systemImage: "heart.fill",
                        tint: Color(red: 0.95, green: 0.3, blue: 0.45)
                    )
                    metricTile(
                        title: "FC a riposo",
                        value: bpm(snapshot.restingHeartRateBpm),
                        subtitle: "Cardiaca",
                        systemImage: "heart.circle.fill",
                        tint: Color(red: 0.85, green: 0.25, blue: 0.5)
                    )
                    metricTile(
                        title: "Pressione",
                        value: snapshot.bloodPressureDescription ?? "—",
                        subtitle: "mmHg",
                        systemImage: "heart.text.square.fill",
                        tint: Color(red: 0.55, green: 0.35, blue: 0.85)
                    )
                    metricTile(
                        title: "Ossigeno",
                        value: spo2(snapshot.oxygenSaturationPercent),
                        subtitle: "SpO₂",
                        systemImage: "lungs.fill",
                        tint: Color(red: 0.25, green: 0.65, blue: 0.9)
                    )
                    metricTile(
                        title: "Tono cardiovascolare",
                        value: vo2(snapshot.vo2Max),
                        subtitle: "VO₂ max",
                        systemImage: "bolt.heart.fill",
                        tint: Color(red: 0.9, green: 0.45, blue: 0.2)
                    )
                    metricTile(
                        title: "Energia",
                        value: snapshot.activeEnergyKcal.map { String(format: "%.0f kcal", $0) } ?? "—",
                        subtitle: "Oggi",
                        systemImage: "flame.fill",
                        tint: Color(red: 1.0, green: 0.55, blue: 0.15)
                    )
                }

                workoutsSection

                if hasExpandableHistory {
                    historyTapRow
                }

                if let bg = snapshot.bloodGroup, !bg.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(Color.red.opacity(0.85))
                        Text("Gruppo sanguigno (Salute iPhone): \(bg)")
                            .font(.subheadline)
                            .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardFill)
                }

                syncFooter
            } else {
                emptyMetricsCard
            }
        }
        .sheet(isPresented: $showHistorySheet) {
            AppleHealthHistorySheet(snapshot: snapshot)
        }
    }

    private var workoutsSummaryValue: String {
        let count = snapshot.recentWorkouts.count
        if count == 0 { return "—" }
        return "\(count)"
    }

    private var workoutsSummarySubtitle: String {
        guard let last = snapshot.recentWorkouts.first else { return "12 mesi" }
        return last.title
    }

    private var hasExpandableHistory: Bool {
        !snapshot.recentHeartRates.isEmpty
            || !snapshot.recentECGs.isEmpty
            || snapshot.recentDailyActivity.contains { ($0.steps ?? 0) > 0 || ($0.activeEnergyKcal ?? 0) > 0 }
            || snapshot.recentWorkouts.count > 5
    }

    private var weightValue: String {
        let kg = childWeightKg ?? snapshot.weightKg
        guard let kg else { return "—" }
        return String(format: "%.1f kg", kg)
    }

    @ViewBuilder
    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allenamenti")
                .font(.headline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))

            if snapshot.recentWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nessun allenamento importato")
                        .font(.subheadline.weight(.medium))
                    Text("In Salute → Condivisione dati → KidBox attiva «Allenamento», poi tocca Aggiorna dati.")
                        .font(.caption)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardFill)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.recentWorkouts.prefix(5).enumerated()), id: \.element.id) { index, workout in
                        workoutRow(workout)
                        if index < min(4, snapshot.recentWorkouts.count - 1) {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(cardFill)

                if snapshot.recentWorkouts.count > 5 {
                    Button {
                        showHistorySheet = true
                    } label: {
                        Text("Altri \(snapshot.recentWorkouts.count - 5) allenamenti — vedi cronologia")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func workoutRow(_ workout: KBHealthWorkoutEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "figure.run")
                .font(.body)
                .foregroundStyle(Color(red: 0.55, green: 0.4, blue: 0.95))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                HStack(spacing: 6) {
                    Text(Self.dayFormatter.string(from: workout.startedAt))
                    if let min = workout.durationMinutes, min > 0 {
                        Text("· \(min) min")
                    }
                    if let kcal = workout.activeEnergyKcal, kcal > 0 {
                        Text(String(format: "· %.0f kcal", kcal))
                    }
                }
                .font(.caption)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var historyTapRow: some View {
        Button {
            showHistorySheet = true
        } label: {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                Text("Cronologia battiti, ECG e passi")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(KBTheme.primaryText(colorScheme))
            .padding(14)
            .background(cardFill)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func profileBanner(age: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.95, green: 0.35, blue: 0.45).opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.45))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Età (da Apple Salute)")
                    .font(.caption)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                Text(age)
                    .font(.title2.bold())
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
            }
            Spacer()
        }
        .padding(16)
        .background(cardFill)
    }

    private func metricTile(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(cardFill)
    }

    private var cardFill: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(KBTheme.cardBackground(colorScheme))
            .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
    }

    private var syncFooter: some View {
        Text("Aggiornato \(snapshot.syncedAt.formatted(.dateTime.day().month().hour().minute())) · dati da Salute su questo iPhone")
            .font(.caption2)
            .foregroundStyle(KBTheme.secondaryText(colorScheme))
    }

    private var emptyMetricsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Nessuna metrica in Salute")
                .font(.subheadline.weight(.semibold))
            Text("Collega Apple Salute e consenti l'accesso a passi, cuore, pressione e ossigeno.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(cardFill)
    }

    private func bpm(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f bpm", value)
    }

    private func spo2(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    private func vo2(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }
}

// MARK: - Cronologia (solo al tap)

private struct AppleHealthHistorySheet: View {
    let snapshot: KBHealthImportSnapshot
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                HealthDetailedMetricsView(snapshot: snapshot, includeWorkouts: true)
                    .padding(18)
            }
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle("Cronologia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}
