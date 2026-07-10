//
//  WalletPatenteFullscreenView.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Visualizzazione a schermo intero di un documento d'identità: mostra le
//  immagini vere scansionate (fronte / retro / altre pagine) in un pager
//  sfogliabile, con sfondo tenue nel colore del tipo documento, luminosità al
//  massimo e rotazione libera. Usata da patente, carta d'identità/CIE,
//  codice fiscale — analoga alla vista a tutto schermo del barcode.
//

import SwiftUI

struct WalletDocumentImagesFullscreenView: View {
    let images: [UIImage]
    var tint: Color = Color(red: 0.9, green: 0.9, blue: 0.92)

    @Environment(\.dismiss) private var dismiss
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness
    @State private var selection = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [tint.opacity(0.18), tint.opacity(0.32)],
                startPoint: .top, endPoint: .bottom
            )
            .background(Color.white)
            .ignoresSafeArea()

            VStack(spacing: 16) {
                if images.isEmpty {
                    ContentUnavailableView("Immagine non disponibile", systemImage: "photo")
                } else {
                    TabView(selection: $selection) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            VStack(spacing: 12) {
                                Text(pageLabel(index))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.black.opacity(0.6))
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                                    .padding(.horizontal, 20)
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
                }
            }
            .padding(.vertical, 40)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.black.opacity(0.5))
                    .padding()
            }
        }
        .allowsAllOrientationsWhileVisible()
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
        }
        .statusBarHidden()
    }

    private func pageLabel(_ index: Int) -> String {
        switch index {
        case 0:  return "Fronte"
        case 1:  return "Retro"
        default: return "Pagina \(index + 1)"
        }
    }
}
