//
//  LoyaltyCardLogoView.swift
//  KidBox
//
//  Created by vscocca on 20/08/26.
//
//  Logo del brand di una carta fedeltà, caricato a runtime dall'URL del
//  catalogo (`LoyaltyCardBrand.logoURL`, congelato su `KBLoyaltyCard.logoURL`).
//
//  Stesso pattern di `entryIcon(entry:)` in `PasswordsHomeView`: `AsyncImage`
//  con switch sulle fasi e fallback grazioso. Qui però il fallback non sono le
//  iniziali ma il wordmark testuale del brand, che è come le carte fedeltà si
//  sono sempre mostrate finora.
//
//  Nota grafica: quasi tutti i loghi sono favicon quadrate su fondo bianco o
//  trasparente. Sopra il gradiente colorato del brand sparirebbero, quindi
//  vengono messe dentro un "chip" bianco arrotondato — è così che appaiono le
//  carte vere. I sorgenti sono spesso piccoli (48px o meno): la dimensione è
//  perciò limitata a `maxLogoSide` (56pt) per non farli sgranare.
//

import SwiftUI

struct LoyaltyCardLogoView: View {

    /// Contesto d'uso, che determina il fallback quando il logo manca o non carica.
    enum Style {
        /// Badge piccolo nella lista "Scegli il negozio": il fallback è il
        /// riquadro col gradiente del brand, esattamente come prima dei loghi.
        case badge
        /// Logo sulla card colorata: il fallback è "niente chip", perché la
        /// tile continua a mostrare il wordmark testuale del brand — che resta
        /// il fallback grafico di sempre.
        case card
    }

    /// Oltre questa dimensione le favicon (spesso 48px) sgranano.
    static let maxLogoSide: CGFloat = 56

    let logoURL: String?
    let brandName: String
    let primaryColorHex: String
    let secondaryColorHex: String
    var style: Style = .badge
    /// Lato del chip in punti. Viene comunque limitato a `maxLogoSide`.
    var size: CGFloat = 36

    private var side: CGFloat { min(size, Self.maxLogoSide) }
    private var cornerRadius: CGFloat { style == .badge ? 8 : 12 }

    private var url: URL? {
        guard let s = logoURL?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var brandGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.loyaltyCardColor(hex: primaryColorHex),
                Color.loyaltyCardColor(hex: secondaryColorHex)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        chip {
                            img
                                .resizable()
                                .scaledToFit()
                                .padding(side * 0.14)
                        }
                    case .failure:
                        fallback
                    case .empty:
                        // Placeholder discreto: stesso ingombro, niente salti di layout.
                        placeholder
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: side, height: side)
        .accessibilityLabel(Text(String(format: NSLocalizedString("Logo %@", comment: "Accessibility label for a loyalty card brand logo, %@ = brand name"), brandName)))
    }

    /// Contenitore bianco arrotondato che tiene leggibile una favicon
    /// trasparente/bianca sopra il gradiente colorato del brand.
    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: side, height: side)
            .background(Color.white, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var placeholder: some View {
        switch style {
        case .badge:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(brandGradient)
                .frame(width: side, height: side)
        case .card:
            chip { Color.clear }
        }
    }

    /// Fallback: badge → gradiente del brand; card → nulla, perché la tile
    /// mostra già il wordmark testuale con il nome del brand.
    @ViewBuilder
    private var fallback: some View {
        switch style {
        case .badge:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(brandGradient)
                .frame(width: side, height: side)
        case .card:
            Color.clear
        }
    }
}

extension LoyaltyCardLogoView {
    /// Comodo init dal brand del catalogo (lista "Scegli il negozio").
    init(brand: LoyaltyCardBrand, style: Style = .badge, size: CGFloat = 36) {
        self.init(
            logoURL: brand.logoURL,
            brandName: brand.name,
            primaryColorHex: brand.primaryColorHex,
            secondaryColorHex: brand.secondaryColorHex,
            style: style,
            size: size
        )
    }

    /// Comodo init dalla carta salvata (tile in griglia e dettaglio).
    init(card: KBLoyaltyCard, style: Style = .card, size: CGFloat = 48) {
        self.init(
            logoURL: card.logoURL,
            brandName: card.brandName,
            primaryColorHex: card.primaryColorHex,
            secondaryColorHex: card.secondaryColorHex,
            style: style,
            size: size
        )
    }
}
