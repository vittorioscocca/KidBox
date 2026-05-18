//
//  TravelPlanningLoadingView.swift
//  KidBox
//

import SwiftUI
import Combine

struct TravelPlanningLoadingView: View {

    let destinationName: String
    let subtitle: String
    let plannedDayCount: Int

    @Environment(\.colorScheme) private var colorScheme

    @State private var secondsLeft: Int
    @State private var tip = TravelDiscoverTips.random()
    private let totalSeconds: Int
    private let accent = Color(red: 0.95, green: 0.38, blue: 0.10)

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(destinationName: String, subtitle: String, plannedDayCount: Int = 3) {
        self.destinationName = destinationName
        self.subtitle = subtitle
        self.plannedDayCount = max(plannedDayCount, 1)
        let total = TravelPlanningCountdown.totalSeconds(plannedDayCount: self.plannedDayCount)
        self.totalSeconds = total
        _secondsLeft = State(initialValue: total)
    }

    /// Anello pieno all'inizio (tempo interamente disponibile), si riduce col countdown.
    private var ringProgress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(secondsLeft) / Double(totalSeconds)
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 6)
                    .frame(width: 148, height: 148)
                Circle()
                    .trim(from: 0, to: max(0.001, ringProgress))
                    .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 148, height: 148)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.9), value: ringProgress)

                VStack(spacing: 2) {
                    Text("CIRCA")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(timeString)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("RIMASTI")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(36)
                .background(
                    Circle()
                        .fill(KBTheme.cardBackground(colorScheme))
                        .shadow(color: KBTheme.shadow(colorScheme), radius: 12, y: 4)
                )
            }

            VStack(spacing: 8) {
                Text("Pianifico \(destinationName)…")
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(TravelPlanningCountdown.estimateLabel(plannedDayCount: plannedDayCount))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(accent)
                        .frame(width: geo.size.width * ringProgress)
                        .animation(.easeInOut(duration: 0.9), value: ringProgress)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(tip.title.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                Text(tip.body)
                    .font(.subheadline.weight(.semibold))
                Text("Consiglio utile mentre l'AI lavora.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KBTheme.cardBackground(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 4)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KBTheme.background(colorScheme))
        .onReceive(timer) { _ in
            if secondsLeft > 0 { secondsLeft -= 1 }
            if Int.random(in: 0 ..< 12) == 0 {
                tip = TravelDiscoverTips.random()
            }
        }
    }

    private var timeString: String {
        let m = secondsLeft / 60
        let s = secondsLeft % 60
        return String(format: "%d:%02d", m, s)
    }
}
