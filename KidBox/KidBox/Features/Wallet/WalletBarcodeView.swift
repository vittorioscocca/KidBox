//
//  WalletBarcodeView.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//
//  Rigenera visivamente il barcode/QR estratto da `WalletPDFParser`.
//  L'immagine è generata on-the-fly con CoreImage a partire da:
//    - `text`:   payload del codice (estratto via Vision sulla pagina PDF)
//    - `format`: raw value di `VNBarcodeSymbology` (es. "VNBarcodeSymbologyQR")
//
//  Non persistiamo la bitmap: la richiesta è leggera e la card rende bene a
//  qualsiasi risoluzione (vettoriale nativa). Se il formato non è generabile
//  via CoreImage, mostriamo un fallback testuale.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct WalletBarcodeView: View {
    let text: String
    let format: String?

    @State private var uiImage: UIImage?
    @State private var copiedFlash = false

    var body: some View {
        VStack(spacing: 10) {
            if let uiImage {
                Image(uiImage: uiImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: isOneDimensional ? 120 : 240)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    .accessibilityLabel("Codice \(displayFormat)")
                    .accessibilityValue(text)
            } else {
                // Fallback: formato non generabile o testo vuoto.
                VStack(alignment: .leading, spacing: 6) {
                    Label(displayFormat, systemImage: "barcode")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack {
                Text(displayFormat)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    UIPasteboard.general.string = text
                    withAnimation(.easeInOut(duration: 0.2)) { copiedFlash = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation(.easeInOut(duration: 0.3)) { copiedFlash = false }
                    }
                } label: {
                    Label(copiedFlash ? "Copiato" : "Copia",
                          systemImage: copiedFlash ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .task(id: "\(format ?? "nil")|\(text)") {
            uiImage = await Self.render(text: text, format: format)
        }
    }

    // MARK: - Display helpers

    private var isOneDimensional: Bool {
        switch normalizedFormat {
        case .code128, .code39, .code93, .ean8, .ean13, .upce, .itf14, .i2of5:
            return true
        default: return false
        }
    }

    private var displayFormat: String {
        switch normalizedFormat {
        case .qr:       return "QR Code"
        case .aztec:    return "Aztec"
        case .pdf417:   return "PDF417"
        case .code128:  return "Code 128"
        case .code39:   return "Code 39"
        case .code93:   return "Code 93"
        case .ean8:     return "EAN-8"
        case .ean13:    return "EAN-13"
        case .upce:     return "UPC-E"
        case .itf14:    return "ITF-14"
        case .i2of5:    return "Interleaved 2 of 5"
        case .dataMatrix: return "Data Matrix"
        case .unknown:  return "Codice"
        }
    }

    // MARK: - Format normalization

    private enum NormalizedFormat {
        case qr, aztec, pdf417, code128, code39, code93
        case ean8, ean13, upce, itf14, i2of5
        case dataMatrix, unknown
    }

    private var normalizedFormat: NormalizedFormat {
        Self.normalize(format: format, text: text)
    }

    private static func normalize(format: String?, text: String) -> NormalizedFormat {
        let f = (format ?? "").lowercased()
        if f.contains("qr") { return .qr }
        if f.contains("aztec") { return .aztec }
        if f.contains("pdf417") { return .pdf417 }
        if f.contains("code128") { return .code128 }
        if f.contains("code39") { return .code39 }
        if f.contains("code93") { return .code93 }
        if f.contains("ean13") { return .ean13 }
        if f.contains("ean8") { return .ean8 }
        if f.contains("upce") { return .upce }
        if f.contains("itf14") { return .itf14 }
        if f.contains("i2of5") || f.contains("interleaved2of5") { return .i2of5 }
        if f.contains("datamatrix") { return .dataMatrix }

        // Senza info di formato: proviamo un'euristica. Se il testo sembra
        // un URL/testo lungo, assumiamo QR (formato più comune nei biglietti).
        if text.count > 32 || text.contains("://") { return .qr }
        return .unknown
    }

    // MARK: - CoreImage rendering

    /// Tenta la generazione via CoreImage. Ritorna `nil` se il formato non è
    /// supportato dai CIFilter built-in (es. Data Matrix, UPC-E).
    private static func render(text: String, format: String?) async -> UIImage? {
        guard !text.isEmpty else { return nil }
        let normalized = normalize(format: format, text: text)

        let context = CIContext(options: [.useSoftwareRenderer: false])
        let data = Data(text.utf8)

        let ciImage: CIImage? = {
            switch normalized {
            case .qr:
                let f = CIFilter.qrCodeGenerator()
                f.message = data
                f.correctionLevel = "M"
                return f.outputImage
            case .aztec:
                let f = CIFilter.aztecCodeGenerator()
                f.message = data
                f.correctionLevel = 23
                f.compactStyle = 0 // 0 = full range (non-compact), 1 = compact
                return f.outputImage
            case .pdf417:
                let f = CIFilter.pdf417BarcodeGenerator()
                f.message = data
                f.correctionLevel = 2
                return f.outputImage
            case .code128:
                // Code128 accetta ASCII. Se il testo contiene non-ASCII,
                // saltiamo il generator (fallback testuale).
                guard text.allSatisfy({ $0.isASCII }) else { return nil }
                let f = CIFilter.code128BarcodeGenerator()
                f.message = data
                f.quietSpace = 7
                f.barcodeHeight = 80
                return f.outputImage
            case .code39:
                // CoreImage non ha un generatore Code 39 built-in (a differenza
                // di Code128/QR/Aztec/PDF417): lo disegniamo a mano in
                // `Code39Generator`, usato per la Tessera Sanitaria (il CF è
                // codificato in Code 39 sul fronte della tessera).
                return nil // gestito a parte sotto, non passa dal path CIImage
            default:
                // Formati non supportati dai CIFilter built-in.
                return nil
            }
        }()

        if normalized == .code39, let cg = Code39Generator.generate(text: text)?.cgImage {
            return UIImage(cgImage: cg)
        }

        guard let ci = ciImage else { return nil }

        // Upscale a risoluzione retina per tenere i moduli netti.
        let scale: CGFloat = normalized == .code128 ? 3 : 10
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Generatore Code 39 "manuale" (disegno barre via Core Graphics): CoreImage
/// non offre un `CICode39BarcodeGenerator` built-in. Copre l'alfabeto standard
/// (0-9, A-Z, spazio, `- . $ / + %`), sufficiente per il Codice Fiscale.
enum Code39Generator {
    /// Pattern a 9 elementi (bar,space,bar,space,bar,space,bar,space,bar):
    /// "0" = elemento stretto, "1" = elemento largo.
    private static let patterns: [Character: String] = [
        "0": "000110100", "1": "100100001", "2": "001100001", "3": "101100000",
        "4": "000110001", "5": "100110000", "6": "001110000", "7": "000100101",
        "8": "100100100", "9": "001100100",
        "A": "100001001", "B": "001001001", "C": "101001000", "D": "000011001",
        "E": "100011000", "F": "001011000", "G": "000001101", "H": "100001100",
        "I": "001001100", "J": "000011100", "K": "100000011", "L": "001000011",
        "M": "101000010", "N": "000010011", "O": "100010010", "P": "001010010",
        "Q": "000000111", "R": "100000110", "S": "001000110", "T": "000010110",
        "U": "110000001", "V": "011000001", "W": "111000000", "X": "010010001",
        "Y": "110010000", "Z": "011010000",
        "-": "010000101", ".": "110000100", " ": "011000100",
        "$": "010101000", "/": "010100010", "+": "010001010", "%": "000101010",
        "*": "010010100"
    ]

    /// `nil` se `text` contiene caratteri fuori dall'alfabeto Code 39.
    static func generate(text: String, narrowWidth: CGFloat = 2, height: CGFloat = 120) -> UIImage? {
        let upper = text.uppercased()
        guard !upper.isEmpty, upper.allSatisfy({ patterns[$0] != nil }) else { return nil }

        let full = "*\(upper)*"
        var elements: [(isBar: Bool, isWide: Bool)] = []
        for (idx, char) in full.enumerated() {
            guard let pattern = patterns[char] else { return nil }
            for (i, bit) in pattern.enumerated() {
                elements.append((isBar: i % 2 == 0, isWide: bit == "1"))
            }
            if idx < full.count - 1 {
                elements.append((isBar: false, isWide: false)) // gap stretto tra caratteri
            }
        }

        let wideWidth = narrowWidth * 3
        let totalWidth = elements.reduce(CGFloat(0)) { $0 + ($1.isWide ? wideWidth : narrowWidth) }
        let size = CGSize(width: totalWidth, height: height)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            var x: CGFloat = 0
            for element in elements {
                let w = element.isWide ? wideWidth : narrowWidth
                if element.isBar {
                    ctx.fill(CGRect(x: x, y: 0, width: w, height: height))
                }
                x += w
            }
        }
    }
}
