//
//  TravelTripTodosSection.swift
//  KidBox
//

import SwiftUI

struct TravelTripTodosSection: View {

    let listName: String
    let openCount: Int
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let accent = Color(red: 0.25, green: 0.45, blue: 0.95)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "checklist")
                        .font(.title2)
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Todo del viaggio")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
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
        .accessibilityLabel("Todo del viaggio, \(subtitle)")
    }

    private var subtitle: String {
        if openCount == 0 {
            return "Apri la lista «\(listName)» · promemoria e cose da fare"
        }
        let word = openCount == 1 ? "attività aperta" : "attività aperte"
        return "\(openCount) \(word) in «\(listName)»"
    }
}
