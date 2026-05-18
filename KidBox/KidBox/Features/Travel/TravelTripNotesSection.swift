//
//  TravelTripNotesSection.swift
//  KidBox
//

import SwiftUI

struct TravelTripNotesSection: View {

    let noteTitle: String
    let hasContent: Bool
    let onTap: () -> Void

    private let accent = Color(red: 0.95, green: 0.38, blue: 0.10)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "note.text")
                        .font(.title2)
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Note del viaggio")
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
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Note del viaggio, \(subtitle)")
    }

    private var subtitle: String {
        if hasContent {
            return "Continua «\(noteTitle)»"
        }
        return "Apri la nota «\(noteTitle)» · annotazioni di viaggio"
    }
}
