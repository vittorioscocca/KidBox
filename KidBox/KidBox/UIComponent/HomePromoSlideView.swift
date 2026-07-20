//
//  HomePromoSlideView.swift
//  KidBox
//
//  Slide promozionali del carosello Home (dopo la foto famiglia): immagini
//  statiche tappabili che portano alla sezione corrispondente dell'app.
//

import SwiftUI

/// Una slide del carosello promozionale in Home.
struct HomePromoSlideData: Identifiable {
    let id: String
    /// Nome dell'imageset in Assets.xcassets.
    let imageName: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let destination: HomeDestination
}

/// Vista di una singola slide: immagine statica a piena larghezza con testo
/// promozionale sovrapposto in basso (scrim sfumato), stesse dimensioni/
/// arrotondamento di `HomeHeroCard` (altezza 300, corner radius 18). Il testo
/// resta più in alto rispetto ai dot del carosello, che vivono fuori dalla card.
struct HomePromoSlideView: View {
    let imageName: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: 300)
                        .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 150)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 22)
                    .padding(.trailing, 12)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
