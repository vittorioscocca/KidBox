//
//  TravelTripExpensesSection.swift
//  KidBox
//

import SwiftUI

struct TravelTripExpensesSection: View {

    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let accent = Color(red: 0.12, green: 0.62, blue: 0.45)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "airplane")
                        .font(.title2)
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Spese del viaggio")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Apri le spese di famiglia · categoria Viaggi già selezionata")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
            }
            .padding(16)
            .background(KBTheme.cardBackground(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Spese del viaggio, categoria Viaggi selezionata")
    }
}
