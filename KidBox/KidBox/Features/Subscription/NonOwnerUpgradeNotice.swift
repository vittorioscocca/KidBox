//
//  NonOwnerUpgradeNotice.swift
//  KidBox
//

import SwiftUI

struct NonOwnerUpgradeNotice: View {
    private let accent = Color(red: 0.55, green: 0.35, blue: 0.9)
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "crown.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Piano gestito dal creatore")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Solo chi ha creato la famiglia può attivare o cambiare un abbonamento. Chiedi al creatore di passare a un piano superiore se serve più spazio o funzioni AI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 1)
        )
    }
}
