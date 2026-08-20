//
//  LoyaltyCardColorExtractor.swift
//  KidBox
//
//  Created by vscocca on 20/08/26.
//
//  Estrae il colore dominante dal logo effettivamente scaricato di un brand,
//  così che la card fedeltà si colori come il logo invece che con i colori
//  curati a mano del catalogo.
//
//  Perché non la media dei pixel: le favicon dei brand sono quasi sempre un
//  glifo colorato su fondo bianco o trasparente. La media aritmetica di quei
//  pixel dà un grigio slavato — è il modo tipico di sbagliare questa cosa.
//  Qui i pixel quasi-bianchi, quasi-neri, trasparenti e desaturati vengono
//  SCARTATI, e tra quelli che restano si sceglie il bucket di colore più
//  frequente pesato per vividezza.
//
//  Guardia di qualità: se l'estrazione non produce un colore abbastanza saturo
//  e abbastanza scuro da reggere il testo bianco della tile, la funzione
//  restituisce `nil` e il chiamante ricade sui colori curati del catalogo —
//  che sono verificati e non vanno peggiorati da un'estrazione debole.
//

import Foundation
import UIKit

enum LoyaltyCardColorExtractor {

    /// Coppia di colori pronta per il gradient della card.
    struct Palette {
        let primaryHex: String
        let secondaryHex: String
    }

    // MARK: - Soglie

    /// Lato dell'immagine ricampionata: abbastanza per il conteggio, abbastanza
    /// piccolo da costare nulla.
    private static let sampleSide = 48
    /// Ampiezza del bucket per canale: raggruppa tinte vicine dello stesso logo.
    private static let bucketSize = 32

    private static let minAlpha: CGFloat = 0.5
    private static let minBrightnessKept: CGFloat = 0.12   // sotto: quasi-nero
    private static let minSaturationKept: CGFloat = 0.18   // sotto: grigio
    // "Quasi-bianco" è la combinazione alta luminosità + bassa saturazione, NON
    // la sola luminosità: in HSB un rosso pieno (#FF0000) ha brightness 1.0
    // esattamente come il bianco, e scartarlo per luminosità farebbe ricadere
    // sul catalogo proprio i loghi più vividi.
    private static let nearWhiteBrightness: CGFloat = 0.94
    private static let nearWhiteSaturation: CGFloat = 0.25

    /// Frazione minima di pixel utili sul totale campionato: sotto questa
    /// soglia il logo è praticamente monocromatico e l'estrazione non è
    /// affidabile.
    private static let minUsefulPixelRatio: Double = 0.02

    /// Il risultato deve reggere testo bianco sopra: saturo abbastanza da non
    /// sembrare un grigio, scuro abbastanza da dare contrasto.
    private static let minResultSaturation: CGFloat = 0.25
    /// Luminanza relativa massima (WCAG) del colore primario. È questa — non la
    /// brightness HSB — a dire davvero se il testo bianco resta leggibile:
    /// #FF0000 passa (0.21), #FFEB3B no (0.79).
    private static let maxResultLuminance: CGFloat = 0.62

    /// Quanto è più scuro il secondario rispetto al primario (~38%), in linea
    /// con le coppie di colori già presenti nel catalogo.
    private static let secondaryDarkenFactor: CGFloat = 0.62

    // MARK: - API

    /// Scarica il logo e ne estrae la palette, con timeout breve.
    ///
    /// Non lancia mai: qualsiasi problema (offline, 404, immagine illeggibile,
    /// estrazione debole) restituisce `nil`, e il chiamante prosegue con i
    /// colori curati. Il salvataggio della carta non deve MAI dipendere da
    /// questo download.
    static func palette(fromLogoURL urlString: String?, timeout: TimeInterval = 3.0) async -> Palette? {
        guard let s = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
              let url = URL(string: s) else { return nil }

        // `URLSession.shared` sfrutta la URLCache già configurata: nella
        // stragrande maggioranza dei casi il logo è appena stato mostrato nel
        // picker "Scegli il negozio", quindi la risposta arriva dalla cache.
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let image = UIImage(data: data) else { return nil }
            return palette(from: image)
        } catch {
            KBLog.ui.kbDebug("[LoyaltyCardColor] logo download failed, using catalog colors: \(error.localizedDescription)")
            return nil
        }
    }

    /// Estrae la palette da un'immagine già in memoria.
    /// - Returns: `nil` se il logo non offre un colore utilizzabile.
    static func palette(from image: UIImage) -> Palette? {
        guard let dominant = dominantColor(in: image) else { return nil }

        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard dominant.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return nil }

        // Guardia di qualità finale (requisito, non optional).
        guard s >= minResultSaturation else {
            KBLog.ui.kbDebug("[LoyaltyCardColor] colore troppo desaturato (sat=\(s) bri=\(b)) → colori catalogo")
            return nil
        }
        guard relativeLuminance(dominant) <= maxResultLuminance else {
            KBLog.ui.kbDebug("[LoyaltyCardColor] colore troppo chiaro per testo bianco → colori catalogo")
            return nil
        }

        let secondary = UIColor(hue: h, saturation: min(1, s + 0.05), brightness: b * secondaryDarkenFactor, alpha: 1)
        return Palette(primaryHex: hexString(dominant), secondaryHex: hexString(secondary))
    }

    // MARK: - Core

    /// Ricampiona a `sampleSide`², scarta i pixel inutili e restituisce il
    /// colore medio del bucket vincente.
    private static func dominantColor(in image: UIImage) -> UIColor? {
        guard let pixels = rgbaPixels(of: image, side: sampleSide) else { return nil }

        struct Bucket {
            var count = 0
            var rSum: CGFloat = 0
            var gSum: CGFloat = 0
            var bSum: CGFloat = 0
            var satSum: CGFloat = 0
        }

        var buckets: [Int: Bucket] = [:]
        var kept = 0
        let total = sampleSide * sampleSide

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = CGFloat(pixels[i + 3]) / 255
            guard alpha >= minAlpha else { continue }

            let r = CGFloat(pixels[i]) / 255
            let g = CGFloat(pixels[i + 1]) / 255
            let b = CGFloat(pixels[i + 2]) / 255

            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, ignored: CGFloat = 0
            guard UIColor(red: r, green: g, blue: b, alpha: 1)
                .getHue(&hue, saturation: &sat, brightness: &bri, alpha: &ignored) else { continue }

            // Scarto: quasi-nero, quasi-grigio, quasi-bianco.
            guard bri >= minBrightnessKept, sat >= minSaturationKept else { continue }
            if bri > nearWhiteBrightness && sat < nearWhiteSaturation { continue }

            let key = (Int(pixels[i]) / bucketSize) << 16
                | (Int(pixels[i + 1]) / bucketSize) << 8
                | (Int(pixels[i + 2]) / bucketSize)

            var bucket = buckets[key] ?? Bucket()
            bucket.count += 1
            bucket.rSum += r
            bucket.gSum += g
            bucket.bSum += b
            bucket.satSum += sat
            buckets[key] = bucket
            kept += 1
        }

        guard kept > 0, Double(kept) / Double(total) >= minUsefulPixelRatio else {
            KBLog.ui.kbDebug("[LoyaltyCardColor] logo senza pixel colorati utili (kept=\(kept)/\(total))")
            return nil
        }

        // Punteggio: frequenza pesata per vividezza media del bucket. Un
        // piccolo accento molto vivido non deve battere il colore portante,
        // ma tra due bucket simili vince quello più vivo.
        var best: (score: Double, bucket: Bucket)?
        for (_, bucket) in buckets {
            let avgSat = bucket.satSum / CGFloat(bucket.count)
            let score = Double(bucket.count) * (0.55 + Double(avgSat))
            if best == nil || score > best!.score {
                best = (score, bucket)
            }
        }

        guard let winner = best?.bucket, winner.count > 0 else { return nil }
        let n = CGFloat(winner.count)
        return UIColor(red: winner.rSum / n, green: winner.gSum / n, blue: winner.bSum / n, alpha: 1)
    }

    /// Ridisegna l'immagine in un buffer RGBA `side`×`side` e ne restituisce i bytes.
    private static func rgbaPixels(of image: UIImage, side: Int) -> [UInt8]? {
        guard let cgImage = image.cgImage ?? image.ciImage.flatMap({ CIContext().createCGImage($0, from: $0.extent) }) else {
            return nil
        }
        let bytesPerRow = side * 4
        var buffer = [UInt8](repeating: 0, count: side * side * 4)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &buffer,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }

    // MARK: - Utility colore

    /// Luminanza relativa WCAG: serve a stimare se il testo bianco resta leggibile.
    private static func relativeLuminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private static func hexString(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int((max(0, min(1, r)) * 255).rounded()),
            Int((max(0, min(1, g)) * 255).rounded()),
            Int((max(0, min(1, b)) * 255).rounded())
        )
    }
}
