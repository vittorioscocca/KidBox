//
//  FitnessSessionsView.swift
//  KidBox
//
//  Storico delle sedute del Piano Fitness segnate come fatte: elenco per mese,
//  dalla più recente, con il riepilogo del mese in testa (quante sedute, quanto
//  tempo, quante calorie — totale e media).
//
//  Mostra solo le sedute con stato `.done`: qui si guarda ciò che è stato
//  davvero svolto, non il calendario di quello che resta da fare — per quello
//  c'è la dashboard.
//

import SwiftUI

struct FitnessSessionsView: View {

    let plan: FitnessPlanDocument

    @Environment(\.colorScheme) private var colorScheme

    private let tint = FitnessPlanTheme.tint

    /// Sedute fatte, dalla più recente. La data che conta è quella di
    /// completamento quando c'è: una seduta spostata è stata svolta il giorno in
    /// cui è stata chiusa, non quello in cui era stata programmata.
    private var doneSessions: [FitnessSession] {
        plan.allSessions
            .filter { $0.status == .done }
            .sorted { performedDate($0) > performedDate($1) }
    }

    /// Mesi con almeno una seduta fatta, dal più recente.
    private var months: [Date] {
        var seen: [Date] = []
        for session in doneSessions {
            let month = startOfMonth(performedDate(session))
            if !seen.contains(month) { seen.append(month) }
        }
        return seen
    }

    var body: some View {
        ScrollView {
            if doneSessions.isEmpty {
                emptyState
                    .padding(.horizontal, 16)
                    .padding(.top, 60)
            } else {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(months, id: \.self) { month in
                        monthSection(month)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Sessioni")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Mese

    @ViewBuilder
    private func monthSection(_ month: Date) -> some View {
        let sessions = doneSessions.filter { startOfMonth(performedDate($0)) == month }

        VStack(alignment: .leading, spacing: 12) {
            Text(monthTitle(month))
                .font(.title2.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))

            monthSummary(sessions)

            VStack(spacing: 10) {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
            }
        }
    }

    /// Riepilogo del mese: totale e media di sedute, tempo e calorie.
    /// Le calorie compaiono solo se almeno una seduta le ha: una media
    /// calcolata su zero dati sarebbe un numero inventato.
    private func monthSummary(_ sessions: [FitnessSession]) -> some View {
        let count = sessions.count
        let minutes = sessions.reduce(0) { $0 + performedMinutes($1) }
        let kcalSessions = sessions.filter { $0.actualKcal != nil }
        let kcal = kcalSessions.reduce(0) { $0 + ($1.actualKcal ?? 0) }
        let distanceSessions = sessions.filter { ($0.actualDistanceMeters ?? 0) >= 10 }
        let meters = distanceSessions.reduce(0.0) { $0 + ($1.actualDistanceMeters ?? 0) }

        return VStack(spacing: 6) {
            HStack {
                Spacer(minLength: 0)
                Text("Totale")
                    .frame(width: 96, alignment: .leading)
                Text("Media")
                    .frame(width: 96, alignment: .leading)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(KBTheme.secondaryText(colorScheme))

            summaryRow(
                label: "Sessioni",
                total: "\(count)",
                average: nil,
                color: KBTheme.primaryText(colorScheme)
            )
            summaryRow(
                label: "Tempo",
                total: durationText(minutes),
                average: count > 0 ? durationText(minutes / count) : nil,
                color: tint
            )
            // Sempre presente, anche a zero: una metrica di salute che sparisce
            // quando il dato manca rende il permesso indimostrabile.
            summaryRow(
                label: "Distanza",
                total: FitnessDistanceFormatter.kilometers(meters) ?? "—",
                average: distanceSessions.isEmpty
                    ? nil
                    : FitnessDistanceFormatter.kilometers(
                        meters / Double(distanceSessions.count)
                    ),
                color: FitnessSessionStatus.done.tint
            )
            if !kcalSessions.isEmpty {
                summaryRow(
                    label: "Calorie",
                    total: kcalText(kcal),
                    average: kcalText(kcal / kcalSessions.count),
                    color: Color(red: 0.90, green: 0.42, blue: 0.35)
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(KBTheme.secondaryText(colorScheme).opacity(0.06))
        )
    }

    private func summaryRow(
        label: LocalizedStringKey,
        total: String,
        average: String?,
        color: Color
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            Spacer(minLength: 8)
            Text(total)
                .frame(width: 96, alignment: .leading)
            Text(average ?? "—")
                .frame(width: 96, alignment: .leading)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
        .monospacedDigit()
    }

    // MARK: - Riga seduta

    private func sessionRow(_ session: FitnessSession) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: session.systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(session))
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    .lineLimit(1)
                Text(headlineMetric(session))
                    .font(.title2.bold())
                    .foregroundStyle(tint)
                if let detail = rowDetail(session) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(dayLabel(performedDate(session)))
                    .font(.footnote)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                if session.completionSource == .healthKit {
                    Image(systemName: "applewatch")
                        .font(.footnote)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(KBTheme.secondaryText(colorScheme).opacity(0.06))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 44))
                .foregroundStyle(tint.opacity(0.6))
            Text("Nessuna seduta registrata")
                .font(.headline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text("Le sedute segnate come fatte, a mano o da Apple Salute, compaiono qui.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Testi

    /// Titolo della riga: l'attività svolta se è stata registrata, altrimenti
    /// quella programmata.
    private func rowTitle(_ session: FitnessSession) -> String {
        if let actual = session.actualActivityTitle, !actual.isEmpty { return actual }
        return session.title
    }

    /// Numero in evidenza: i chilometri per le discipline che ne hanno, poi le
    /// calorie, e come ultima risorsa i minuti — l'ordine con cui l'attività si
    /// riconosce a colpo d'occhio.
    private func headlineMetric(_ session: FitnessSession) -> String {
        if let km = FitnessDistanceFormatter.kilometers(session.actualDistanceMeters) {
            return km.uppercased()
        }
        if let kcal = session.actualKcal {
            return String(
                format: NSLocalizedString("%d KCAL", comment: "Session calories, sessions list"),
                kcal
            )
        }
        return String(
            format: NSLocalizedString("%d MIN", comment: "Session minutes, sessions list"),
            performedMinutes(session)
        )
    }

    /// Riga di contorno: gli altri numeri della seduta, più il titolo previsto
    /// quando l'attività svolta era un'altra.
    private func rowDetail(_ session: FitnessSession) -> String? {
        var parts: [String] = []
        let hasDistance = FitnessDistanceFormatter.kilometers(session.actualDistanceMeters) != nil
        if hasDistance || session.actualKcal != nil {
            parts.append(
                String(
                    format: NSLocalizedString("%d min", comment: "Session duration in minutes"),
                    performedMinutes(session)
                )
            )
        }
        if hasDistance, let kcal = session.actualKcal { parts.append(kcalText(kcal)) }
        if let bpm = session.actualHeartRateBpm { parts.append("\(bpm) bpm") }
        if session.wasSubstituted {
            parts.append(
                String(
                    format: NSLocalizedString(
                        "Previsto: %@",
                        comment: "Planned session title in the sessions list"
                    ),
                    session.title
                )
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func durationText(_ minutes: Int) -> String {
        if minutes < 60 {
            return String(
                format: NSLocalizedString("%d min", comment: "Session duration in minutes"),
                minutes
            )
        }
        return String(
            format: NSLocalizedString("%1$dh %2$02dmin", comment: "Hours and minutes, sessions list"),
            minutes / 60,
            minutes % 60
        )
    }

    private func kcalText(_ kcal: Int) -> String {
        String(format: NSLocalizedString("%d kcal", comment: "Calories, sessions list"), kcal)
    }

    /// "oggi", il nome del giorno nell'ultima settimana, poi la data breve.
    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return NSLocalizedString("oggi", comment: "Today, sessions list")
        }
        if calendar.isDateInYesterday(date) {
            return NSLocalizedString("ieri", comment: "Yesterday, sessions list")
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        let formatter = DateFormatter()
        formatter.locale = .current
        if (0...6).contains(days) {
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("ddMMyy")
        }
        return formatter.string(from: date)
    }

    private func monthTitle(_ month: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("LLLLyyyy")
        return formatter.string(from: month).capitalizedFirstLetterForList
    }

    // MARK: - Date e numeri

    /// Giorno in cui la seduta è stata svolta.
    private func performedDate(_ session: FitnessSession) -> Date {
        session.completedAt ?? session.date
    }

    private func performedMinutes(_ session: FitnessSession) -> Int {
        session.actualMinutes ?? session.durationMinutes
    }

    private func startOfMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}

private extension String {
    /// I nomi dei mesi arrivano minuscoli in italiano e maiuscoli in inglese:
    /// qui servono come titolo, quindi si alza solo la prima lettera.
    var capitalizedFirstLetterForList: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
