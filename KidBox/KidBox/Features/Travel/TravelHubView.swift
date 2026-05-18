//
//  TravelHubView.swift
//  KidBox
//

import SwiftUI

struct TravelHubView: View {

    let familyId: String
    let profile: TravelProfile?
    let aiAvailable: Bool
    let onPlanTrip: () -> Void
    let onDiscover: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let accent = Color(red: 0.95, green: 0.38, blue: 0.10)

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5 ..< 12: return "Buongiorno"
        case 12 ..< 18: return "Buon pomeriggio"
        default: return "Buonasera"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(.largeTitle.bold())
                Text("Dove andiamo?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            planTripCard
            discoverCard

            if let top = profile {
                Text("SUGGERIMENTO DEL MESE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                editorsPickHint(profile: top)
            }
        }
    }

    private var planTripCard: some View {
        Button(action: onPlanTrip) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.10, blue: 0.10),
                                Color(red: 0.28, green: 0.14, blue: 0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("PIANIFICA UN VIAGGIO")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accent)
                        Spacer()
                        Text("~2 MIN")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("So già")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("dove andare")
                            .font(.title2.bold())
                            .foregroundStyle(accent)
                    }
                    Text("Costruisci il viaggio intorno alla destinazione.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Inizia a pianificare →")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(accent)
                        .clipShape(Capsule())
                        .padding(.top, 4)
                }
                .padding(20)
            }
        }
        .buttonStyle(.plain)
        .disabled(!aiAvailable)
        .opacity(aiAvailable ? 1 : 0.55)
    }

    private var discoverCard: some View {
        Button(action: onDiscover) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("SCOPRI")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                    Spacer()
                    Image(systemName: "sparkles")
                        .foregroundStyle(accent)
                        .padding(10)
                        .background(accent.opacity(0.12))
                        .clipShape(Circle())
                }
                Text("Suggeriscimi un posto")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("Luoghi in linea con il tuo stile, budget e periodo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Mostrami i posti →")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.primary)
                    .clipShape(Capsule())
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(KBTheme.cardBackground(colorScheme))
                    .shadow(color: KBTheme.shadow(colorScheme), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(KBTheme.separator(colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!aiAvailable)
        .opacity(aiAvailable ? 1 : 0.55)
    }

    private func editorsPickHint(profile: TravelProfile) -> some View {
        HStack {
            Text("✨")
            Text("Apri Scopri per idee su misura (\(profile.pace.title.lowercased())).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(KBTheme.cardBackground(colorScheme))
                .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
        )
    }
}
