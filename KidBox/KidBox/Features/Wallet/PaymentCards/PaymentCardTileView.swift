//
//  PaymentCardTileView.swift
//  KidBox
//
//  Created by vscocca on 03/10/26.
//
//  La carta disegnata come una carta vera: nome e circuito in alto, numero
//  mascherato al centro, intestatario e scadenza in basso. Il numero intero
//  non compare mai qui, nemmeno nel dettaglio.
//

import SwiftUI

struct PaymentCardTileView: View {
    let plain: PaymentCardPlain
    let colorHex: String
    var height: CGFloat = 200

    var body: some View {
        let base = Color.loyaltyCardColor(hex: colorHex)
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [base, base.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .background(Color.black)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(plain.isUnreadable
                         ? NSLocalizedString("Carta non leggibile", comment: "Payment card tile: cannot decrypt")
                         : plain.tileTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text(plain.network == .other ? "" : plain.network.displayName)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .italic()
                        .opacity(0.9)
                }

                Spacer(minLength: 0)

                Image(systemName: "creditcard.fill")
                    .font(.system(size: 22))
                    .opacity(0.35)

                Spacer(minLength: 0)

                if !plain.cardNumber.isEmpty {
                    Text(PaymentCardFormat.masked(plain.cardNumber))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.bottom, 10)
                }

                HStack(alignment: .bottom) {
                    Text(plain.holderName.uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    if !plain.expiry.isEmpty {
                        VStack(alignment: .trailing, spacing: 1) {
                            if PaymentCardFormat.isExpired(plain.expiry) {
                                Text("Scaduta")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.85), in: Capsule())
                            }
                            Text(plain.expiry)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.loyaltyCardColor(hex: colorHex).opacity(0.35), radius: 8, y: 4)
    }
}
