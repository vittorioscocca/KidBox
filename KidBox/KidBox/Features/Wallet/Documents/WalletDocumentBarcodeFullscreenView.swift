//
//  WalletDocumentBarcodeFullscreenView.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Vista a schermo intero del barcode (Codice Fiscale) di un documento
//  d'identità, pensata per farlo scansionare allo sportello: barcode grande,
//  luminosità al massimo, ruota in orizzontale se il dispositivo viene
//  girato (stesso meccanismo di `allowsAllOrientationsWhileVisible()` già
//  usato dall'anteprima PDF/QuickLook), nome e cognome piccoli sotto.
//

import SwiftUI

struct WalletDocumentBarcodeFullscreenView: View {
    let codiceFiscale: String
    let holderName: String

    @Environment(\.dismiss) private var dismiss
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness
    @State private var barcodeImage: UIImage?

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 24) {
                if let barcodeImage {
                    Image(uiImage: barcodeImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 260)
                        .padding(.horizontal, 32)
                }

                if !holderName.isEmpty {
                    Text(holderName)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.black.opacity(0.55))
                }
            }
        }
        .task {
            barcodeImage = Code39Generator.generate(text: codiceFiscale, narrowWidth: 4, height: 160)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
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
}
