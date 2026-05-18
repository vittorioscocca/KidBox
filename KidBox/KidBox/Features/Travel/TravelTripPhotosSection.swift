//
//  TravelTripPhotosSection.swift
//  KidBox
//

import SwiftUI

struct TravelTripPhotosSection: View {

    let photoCount: Int
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let accent = Color(red: 0.95, green: 0.38, blue: 0.10)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Foto del viaggio")
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
        .accessibilityLabel("Foto del viaggio, \(subtitle)")
    }

    private var subtitle: String {
        if photoCount == 0 {
            return "Apri l'album dedicato · le nuove foto si salvano qui"
        }
        return "\(photoCount) foto nell'album del viaggio"
    }
}
