//
//  KBChip.swift
//  KidBox
//

import SwiftUI

/// Rounded pill for visibility tags, feature tags and filters — neutral or category-tinted.
/// Mirrors the KidBox design system's `Chip` component (design-system/components/core/Chip.jsx).
struct KBChip: View {
    enum Variant {
        case neutral
        case tinted(Color)
    }

    let title: String
    var icon: Image? = nil
    var variant: Variant = .neutral

    var body: some View {
        HStack(spacing: 6) {
            icon
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(background, in: Capsule())
        .foregroundStyle(foreground)
        .overlay(Capsule().stroke(border, lineWidth: 1))
    }

    private var background: Color {
        switch variant {
        case .neutral: return Color(.secondarySystemBackground)
        case .tinted(let tint): return tint.opacity(0.14)
        }
    }

    private var foreground: Color {
        switch variant {
        case .neutral: return .primary
        case .tinted(let tint): return tint
        }
    }

    private var border: Color {
        switch variant {
        case .neutral: return Color(.separator).opacity(0.5)
        case .tinted(let tint): return tint.opacity(0.26)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        KBChip(title: "Tutta la famiglia")
        KBChip(title: "Sincronizzato", icon: Image(systemName: "checkmark.circle.fill"), variant: .tinted(.green))
    }
    .padding()
}
