//
//  TravelOnboardingView.swift
//  KidBox
//

import SwiftUI

struct TravelOnboardingView: View {

    let onComplete: (TravelProfile) -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var step = 0
    @State private var selectedStyles: Set<TravelStyle> = []
    @State private var selectedPace: TravelPace?
    @State private var selectedAgeGroup: TravelAgeGroup?

    private let accent = Color(red: 0.95, green: 0.38, blue: 0.10)
    private let totalSteps = 3

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.10, blue: 0.10)
            : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.16, blue: 0.16) : .white
    }

    private var canContinue: Bool {
        switch step {
        case 0: return !selectedStyles.isEmpty
        case 1: return selectedPace != nil
        case 2: return selectedAgeGroup != nil
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            progressBar
                .padding(.horizontal, 20)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stepHeader
                    stepContent
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }

            footer
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    private var header: some View {
        HStack {
            if step > 0 {
                Button("Indietro") { step -= 1 }
                    .foregroundStyle(.primary)
            } else {
                Color.clear.frame(width: 60, height: 1)
            }
            Spacer()
            Text("\(step + 1) di \(totalSteps)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(accent)
                    .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(totalSteps))
            }
        }
        .frame(height: 4)
    }

    @ViewBuilder
    private var stepHeader: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 8) {
                Text("Qual è il tuo stile di viaggio?")
                    .font(.title.bold())
                Text("Seleziona tutto ciò che ti interessa")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case 1:
            VStack(alignment: .leading, spacing: 8) {
                Text("Come ti piace viaggiare?")
                    .font(.title.bold())
                Text("Il tuo ritmo preferito")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("La tua fascia d'età?")
                    .font(.title.bold())
                Text("Ci aiuta a personalizzare i consigli")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            VStack(spacing: 12) {
                ForEach(TravelStyle.allCases) { style in
                    styleRow(style)
                }
            }
        case 1:
            VStack(spacing: 12) {
                ForEach(TravelPace.allCases) { pace in
                    paceRow(pace)
                }
            }
        default:
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(TravelAgeGroup.allCases) { group in
                        ageCard(group)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Quasi fatto!")
                        .font(.headline)
                    Text("Salveremo le tue preferenze per proporti itinerari più adatti a te.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func styleRow(_ style: TravelStyle) -> some View {
        let selected = selectedStyles.contains(style)
        return Button {
            if selected {
                selectedStyles.remove(style)
            } else {
                selectedStyles.insert(style)
            }
        } label: {
            HStack(spacing: 14) {
                Text(style.emoji)
                    .font(.title2)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(style.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? accent : Color.secondary.opacity(0.45))
            }
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? accent : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func paceRow(_ pace: TravelPace) -> some View {
        let selected = selectedPace == pace
        let tint = Color(red: pace.tint.red, green: pace.tint.green, blue: pace.tint.blue)
        return Button {
            selectedPace = pace
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 44, height: 44)
                    Image(systemName: pace.systemImage)
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(pace.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(pace.line1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pace.line2)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? accent : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func ageCard(_ group: TravelAgeGroup) -> some View {
        let selected = selectedAgeGroup == group
        return Button {
            selectedAgeGroup = group
        } label: {
            VStack(spacing: 8) {
                Text(group.emoji)
                    .font(.largeTitle)
                Text(group.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text(group.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? accent : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        Button {
            advance()
        } label: {
            Text(step == totalSteps - 1 ? "Continua" : "Continua")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canContinue ? accent : Color.gray.opacity(0.35))
                .clipShape(Capsule())
        }
        .disabled(!canContinue)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(backgroundColor)
    }

    private func advance() {
        guard canContinue else { return }
        if step < totalSteps - 1 {
            step += 1
            return
        }
        guard let pace = selectedPace, let ageGroup = selectedAgeGroup else { return }
        onComplete(
            TravelProfile(
                styles: Array(selectedStyles).sorted { $0.rawValue < $1.rawValue },
                pace: pace,
                ageGroup: ageGroup
            )
        )
    }
}
