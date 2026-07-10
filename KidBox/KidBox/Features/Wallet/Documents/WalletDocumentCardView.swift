//
//  WalletDocumentCardView.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Card visiva del documento d'identità, stessa lingua visiva di
//  `WalletTicketCardView` (gradient per kind, testo bianco) così la sezione
//  "Documenti" del Wallet è coerente con quella "Biglietti".
//

import SwiftUI

struct WalletDocumentCardView: View {
    let document: KBDocument
    let ownerName: String
    var isSelectionMode: Bool = false
    var isSelected: Bool = false

    var height: CGFloat = 150

    private var kind: KBWalletDocumentKind { document.walletDocumentKind ?? .altro }
    private var metadata: KBWalletDocumentMetadata? { document.walletMetadata }

    var body: some View {
        ZStack(alignment: .topLeading) {
            gradient

            VStack(alignment: .leading, spacing: 10) {
                header
                Spacer(minLength: 6)
                footer
            }
            .padding(16)

            if isSelectionMode {
                selectionBadge
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: kind.accentColorSecondary.opacity(0.3), radius: 8, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 0.5)
        )
    }

    private var gradient: some View {
        LinearGradient(
            colors: [kind.accentColor, kind.accentColorSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: kind.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.18)))

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)

                Text(document.title.isEmpty ? kind.displayName : document.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Text(ownerName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Spacer()

            if let expiry = metadata?.effectiveExpiryDate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(expiry < Date() ? "SCADUTO" : "SCADE")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(expiry.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var selectionBadge: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(.white, isSelected ? Color.accentColor : Color.white.opacity(0.35))
            .background(Circle().fill(Color.black.opacity(0.15)))
    }
}
