//
//  LoyaltyCardTileView.swift
//  KidBox
//
//  Created by vscocca on 20/08/26.
//
//  Tile colorata per una carta fedeltà: gradient primario/secondario + logo
//  reale del brand (caricato a runtime da `card.logoURL`, vedi
//  `LoyaltyCardLogoView`) e nome brand in wordmark testuale, che resta il
//  fallback quando il logo manca o non carica.
//

import SwiftUI
import UIKit

struct LoyaltyCardTileView: View {
    let card: KBLoyaltyCard
    var height: CGFloat = 130

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.loyaltyCardColor(hex: card.primaryColorHex), Color.loyaltyCardColor(hex: card.secondaryColorHex)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Logo reale del brand in alto a destra, dentro il chip bianco.
            // Se `logoURL` è nil o l'immagine non carica, il chip sparisce e
            // resta il glifo generico + il wordmark testuale in basso.
            Group {
                if card.logoURL?.isEmpty == false {
                    LoyaltyCardLogoView(card: card, style: .card, size: logoSide)
                } else {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.18))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.brandName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                if !card.cardNumber.isEmpty {
                    Text(maskedNumber)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(14)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.loyaltyCardColor(hex: card.primaryColorHex).opacity(0.35), radius: 8, y: 4)
    }

    /// Il logo scala con l'altezza della tile ma non supera i 56pt: molte
    /// favicon sorgente sono 48px e oltre quella soglia sgranano.
    private var logoSide: CGFloat {
        min(LoyaltyCardLogoView.maxLogoSide, max(36, height * 0.34))
    }

    private var maskedNumber: String {
        let trimmed = card.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 4 else { return trimmed }
        let tail = trimmed.suffix(4)
        return "•••• \(tail)"
    }
}

// MARK: - Color(hex:)
//
// L'inizializzatore fallibile `Color.init?(hex:)` è già definito in
// `CalendarView.swift` (progetto-wide). Qui aggiungiamo solo un helper non
// fallibile con fallback grigio neutro (comodo per i brand del catalogo,
// dove il colore è sempre valido ma vogliamo evitare optional a catena) e
// la serializzazione inversa per il color picker manuale.

extension Color {
    /// Wrapper non fallibile su `Color.init?(hex:)`: fallback grigio neutro
    /// se la stringa non è un hex valido.
    static func loyaltyCardColor(hex: String) -> Color {
        Color(hex: hex) ?? Color(.systemGray)
    }

    /// Serializza in `"#RRGGBB"` (best-effort, spazio sRGB).
    func toHexString() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
