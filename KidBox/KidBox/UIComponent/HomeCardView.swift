//
//  CardView.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI

// MARK: - Home Card (grid)

struct HomeCardView: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let action: () -> Void

    private let cornerRadius: CGFloat = 16

    var body: some View {
        Button(action: action) {
            HomeCardLabel(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle))
    }
}

/// Contenuto visivo della card Home (usabile dentro `NavigationLink`).
struct HomeCardLabel: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let tint: Color

    private let cornerRadius: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .compositingGroup()
    }
}
