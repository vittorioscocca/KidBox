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
    /// Larghezza massima del codice. Default 320pt (aspetto compatto dei
    /// biglietti); le carte fedeltà passano `.infinity`.
    var maxWidth: CGFloat = 320
    /// Se `true`, un codice **monodimensionale** riempie tutta la larghezza
    /// disponibile mantenendo l'altezza fissa, invece di scalare in proporzione.
    ///
    /// Serve perché con `scaledToFit` le proporzioni sono vincolate: allargare
    /// il codice lo farebbe crescere anche in altezza. In un barcode 1D
    /// l'altezza però non porta informazione — i dati stanno tutti nella
    /// sequenza orizzontale di barre — quindi allungare le barre in orizzontale
    /// e tenere l'altezza fissa è lecito e resta perfettamente scansionabile.
    /// Sui codici 2D (QR/Aztec/PDF417) il parametro è ignorato: lì la
    /// proporzione è parte della codifica e deformarli li renderebbe illeggibili.
    var stretchOneDimensionalToWidth: Bool = false

    @State private var uiImage: UIImage?
    @State private var copiedFlash = false

    private var fixedHeight: CGFloat { isOneDimensional ? 120 : 240 }

    /// Riempimento non uniforme solo dove è sicuro farlo.
    private var shouldStretch: Bool { stretchOneDimensionalToWidth && isOneDimensional }

    var body: some View {
        VStack(spacing: 10) {
            if let uiImage {
                Group {
                    if shouldStretch {
                        Image(uiImage: uiImage)
                            .interpolation(.none)
                            .resizable()   // niente scaledToFit: riempie in larghezza
                            .frame(maxWidth: .infinity)
                            .frame(height: fixedHeight)
                    } else {
                        Image(uiImage: uiImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: maxWidth, maxHeight: fixedHeight)
                    }
                }
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

        // Vision restituisce il payload come stringa decodificata in
        // ISO-8859-1: un biglietto Trenitalia o una carta d'imbarco portano
        // byte alti (>0x7F) che, ri-codificati in UTF-8, diventano due byte e
        // producono un codice **diverso** da quello del biglietto. Per i
        // formati che nascono binari si ritorna quindi ai byte originali; sul
        // QR, che per specifica trasporta testo UTF-8, si resta su UTF-8.
        // (Verificato: 0xC0 0xE8 0xF9 → utf8 dà C3 80 C3 A8 C3 B9, latin1 li
        // riporta identici.)
        let data: Data = {
            switch normalized {
            case .aztec, .pdf417, .code128:
                return text.data(using: .isoLatin1) ?? Data(text.utf8)
            default:
                return Data(text.utf8)
            }
        }()

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
                // Basso di proposito: l'altezza la decide la view. Con un
                // valore alto (era 80) l'immagine sorgente resta quasi
                // quadrata, `scaledToFit` la limita in altezza e il codice
                // finisce disegnato stretto — barre sottili, largo la metà
                // dello spazio disponibile. Misurato: 80 → 187pt su 320.
                f.barcodeHeight = 24
                return f.outputImage
            case .code39, .ean13, .itf14, .i2of5:
                // CoreImage genera solo Code128/QR/Aztec/PDF417. Code 39 (il
                // codice fiscale sulla Tessera Sanitaria), EAN-13 e ITF li
                // disegniamo a mano qui sotto: senza, la card mostrava il
                // numero come testo e il codice non c'era proprio.
                return nil // gestiti a parte, non passano dal path CIImage
            default:
                // Formati non supportati dai CIFilter built-in.
                return nil
            }
        }()

        // Formati disegnati con Core Graphics invece che con CoreImage.
        switch normalized {
        case .code39:
            if let image = Code39Generator.generate(text: text) { return image }
        case .ean13:
            if let image = EAN13Generator.generate(text: text) { return image }
        case .itf14, .i2of5:
            if let image = ITFGenerator.generate(text: text) { return image }
        default:
            break
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

/// EAN-13 disegnato a mano: CoreImage non ha un `CIEAN13BarcodeGenerator`, e
/// senza questo la card mostrava solo il numero.
///
/// Struttura da specifica: 95 moduli — guardia `101`, sei cifre a sinistra
/// codificate L o G secondo la prima cifra, guardia centrale `01010`, sei
/// cifre a destra in R, guardia `101` — più le zone di quiete (9 moduli a
/// sinistra, 7 a destra) senza le quali molti lettori non agganciano il codice.
enum EAN13Generator {
    private static let left = [
        "0001101", "0011001", "0010011", "0111101", "0100011",
        "0110001", "0101111", "0111011", "0110111", "0001011",
    ]
    private static let leftEven = [
        "0100111", "0110011", "0011011", "0100001", "0011101",
        "0111001", "0000101", "0010001", "0001001", "0010111",
    ]
    private static let right = [
        "1110010", "1100110", "1101100", "1000010", "1011100",
        "1001110", "1010000", "1000100", "1001000", "1110100",
    ]
    /// Come la prima cifra sceglie la parità delle sei di sinistra: è lei a
    /// portare la tredicesima informazione, che non ha barre proprie.
    private static let parity = [
        "LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
        "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL",
    ]

    /// Cifra di controllo mod 10 con pesi 1,3 alternati.
    static func checkDigit(_ digits: [Int]) -> Int {
        let sum = digits.enumerated().reduce(0) { acc, item in
            acc + item.element * (item.offset % 2 == 0 ? 1 : 3)
        }
        return (10 - sum % 10) % 10
    }

    /// `nil` se il testo non è un EAN-13 valido: meglio il fallback testuale di
    /// un codice che il lettore rifiuterà per checksum.
    static func generate(text: String, moduleWidth: CGFloat = 3, height: CGFloat = 120) -> UIImage? {
        var digits = text.compactMap { $0.wholeNumberValue }.filter { (0...9).contains($0) }
        if digits.count == 12 { digits.append(checkDigit(digits)) }
        guard digits.count == 13, checkDigit(Array(digits.prefix(12))) == digits[12] else { return nil }

        let pattern = parity[digits[0]]
        var modules = "101"
        for (i, p) in pattern.enumerated() {
            let d = digits[i + 1]
            modules += (p == "L" ? left[d] : leftEven[d])
        }
        modules += "01010"
        for d in digits[7...] { modules += right[d] }
        modules += "101"

        let quietLeft = 9, quietRight = 7
        let total = CGFloat(quietLeft + modules.count + quietRight)
        let size = CGSize(width: total * moduleWidth, height: height)

        // Le guardie scendono sotto le barre dati, dentro la riga delle cifre:
        // è così che si riconosce un EAN a colpo d'occhio.
        let textBand: CGFloat = 16
        let barHeight = height - textBand
        let guardHeight = height - textBand * 0.35
        let guardRanges = [0..<3, 45..<50, 92..<95]

        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            for (i, bit) in modules.enumerated() where bit == "1" {
                let isGuard = guardRanges.contains { $0.contains(i) }
                let x = CGFloat(quietLeft + i) * moduleWidth
                ctx.fill(CGRect(x: x, y: 0, width: moduleWidth, height: isGuard ? guardHeight : barHeight))
            }

            let font = UIFont.monospacedDigitSystemFont(ofSize: textBand - 3, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
            func draw(_ s: String, from: Int, to: Int) {
                let rect = CGRect(x: CGFloat(from) * moduleWidth, y: height - textBand + 1,
                                  width: CGFloat(to - from) * moduleWidth, height: textBand)
                let width = (s as NSString).size(withAttributes: attrs).width
                (s as NSString).draw(at: CGPoint(x: rect.midX - width / 2, y: rect.minY), withAttributes: attrs)
            }
            // Prima cifra nella zona di quiete, poi i due gruppi di sei sotto
            // le rispettive metà.
            draw("\(digits[0])", from: 0, to: quietLeft)
            draw(digits[1...6].map(String.init).joined(), from: quietLeft + 3, to: quietLeft + 45)
            draw(digits[7...12].map(String.init).joined(), from: quietLeft + 50, to: quietLeft + 92)
        }
    }
}

/// Interleaved 2 of 5 (e la sua variante a 14 cifre, ITF-14). Le cifre vanno a
/// coppie: la prima detta le barre, la seconda gli spazi, intrecciati elemento
/// per elemento — da cui il nome.
enum ITFGenerator {
    /// Cinque elementi per cifra, "1" = largo.
    private static let patterns = [
        "00110", "10001", "01001", "11000", "00101",
        "10100", "01100", "00011", "10010", "01010",
    ]

    static func generate(text: String, narrowWidth: CGFloat = 3, height: CGFloat = 120) -> UIImage? {
        var digits = text.compactMap { $0.wholeNumberValue }.filter { (0...9).contains($0) }
        guard !digits.isEmpty else { return nil }
        // Il formato codifica coppie: con un numero dispari di cifre si
        // antepone uno zero, come fanno tutti i lettori.
        if digits.count % 2 == 1 { digits.insert(0, at: 0) }

        let wideWidth = narrowWidth * 3
        var elements: [(isBar: Bool, isWide: Bool)] = []
        // Start: barra, spazio, barra, spazio, tutti stretti.
        elements += [(true, false), (false, false), (true, false), (false, false)]
        for pair in stride(from: 0, to: digits.count, by: 2) {
            let bars = patterns[digits[pair]]
            let spaces = patterns[digits[pair + 1]]
            for i in 0..<5 {
                elements.append((true, Array(bars)[i] == "1"))
                elements.append((false, Array(spaces)[i] == "1"))
            }
        }
        // Stop: barra larga, spazio stretto, barra stretta.
        elements += [(true, true), (false, false), (true, false)]

        let barsWidth = elements.reduce(CGFloat(0)) { $0 + ($1.isWide ? wideWidth : narrowWidth) }
        let textBand: CGFloat = 16
        // ITF-14 (le 14 cifre del codice logistico) vuole le barre di
        // contenimento intorno al simbolo: senza, il lettore lo riconosce come
        // un generico Interleaved 2 of 5.
        let bearer: CGFloat = digits.count == 14 ? narrowWidth * 2 : 0
        // Dieci moduli stretti di quiete, che con la cornice vanno contati al
        // suo interno.
        let quiet = narrowWidth * 10 + bearer
        let size = CGSize(width: barsWidth + quiet * 2, height: height)

        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            if bearer > 0 {
                let frame = CGRect(x: 0, y: 0, width: size.width, height: height - textBand)
                ctx.fill(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: bearer))
                ctx.fill(CGRect(x: frame.minX, y: frame.maxY - bearer, width: frame.width, height: bearer))
                ctx.fill(CGRect(x: frame.minX, y: frame.minY, width: bearer, height: frame.height))
                ctx.fill(CGRect(x: frame.maxX - bearer, y: frame.minY, width: bearer, height: frame.height))
            }
            var x = quiet
            for element in elements {
                let w = element.isWide ? wideWidth : narrowWidth
                if element.isBar {
                    ctx.fill(CGRect(x: x, y: bearer, width: w, height: height - textBand - bearer * 2))
                }
                x += w
            }

            let font = UIFont.monospacedDigitSystemFont(ofSize: textBand - 3, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
            let label = digits.map(String.init).joined() as NSString
            let width = label.size(withAttributes: attrs).width
            label.draw(at: CGPoint(x: (size.width - width) / 2, y: height - textBand + 1), withAttributes: attrs)
        }
    }
}
