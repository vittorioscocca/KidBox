//
//  DocumentImageCompressor.swift
//  KidBox
//
//  Compressione conservativa delle immagini caricate come documenti.
//  Riduce foto/scan ad alta risoluzione prima di cifratura e upload, per
//  risparmiare storage e banda, preservando la leggibilità di referti e testo
//  (utile anche all'OCR). Non tocca PDF né altri formati.
//

import Foundation
import UIKit

enum DocumentImageCompressor {

    /// Lato lungo massimo (px). Sopra questa soglia l'immagine viene ridimensionata.
    /// 3000px mantiene leggibile il testo di un referto scansionato.
    static let maxDimension: CGFloat = 3000
    /// Qualità JPEG in uscita. 0.8 = compressione conservativa, artefatti trascurabili.
    static let jpegQuality: CGFloat = 0.8
    /// Sotto questa dimensione non vale la pena comprimere.
    static let minBytesToConsider = 1_200_000 // ~1.2 MB

    struct Output {
        let data: Data
        let fileName: String
        let mimeType: String
        let didCompress: Bool
    }

    static func isCompressibleImage(mimeType: String, fileExtension: String) -> Bool {
        if mimeType.hasPrefix("image/") { return true }
        let ext = fileExtension.lowercased()
        return ["jpg", "jpeg", "png", "heic", "heif"].contains(ext)
    }

    /// Restituisce una versione compressa dell'immagine se conviene, altrimenti
    /// i dati originali invariati. La compressione è lossy e produce sempre JPEG.
    static func compressIfNeeded(data: Data, fileName: String, mimeType: String) -> Output {
        let unchanged = Output(data: data, fileName: fileName, mimeType: mimeType, didCompress: false)

        let ext = (fileName as NSString).pathExtension
        guard isCompressibleImage(mimeType: mimeType, fileExtension: ext) else { return unchanged }
        guard data.count >= minBytesToConsider else { return unchanged }
        guard let image = UIImage(data: data) else { return unchanged }

        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longestSide = max(pixelWidth, pixelHeight)
        guard longestSide > 0 else { return unchanged }

        // Ridimensiona solo se supera il limite; altrimenti ricomprime a stessa dimensione.
        let scaleFactor = longestSide > maxDimension ? maxDimension / longestSide : 1.0
        let targetSize = CGSize(
            width: (pixelWidth * scaleFactor).rounded(),
            height: (pixelHeight * scaleFactor).rounded()
        )
        guard targetSize.width >= 1, targetSize.height >= 1 else { return unchanged }

        // scale=1 così il bitmap corrisponde esattamente a targetSize (niente
        // moltiplicatore del display che sprecherebbe memoria).
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpeg = rendered.jpegData(compressionQuality: jpegQuality) else { return unchanged }

        // Tieni la versione compressa solo se fa risparmiare spazio reale.
        guard jpeg.count < data.count else { return unchanged }

        let baseName = (fileName as NSString).deletingPathExtension
        let newName = baseName.isEmpty ? "image.jpg" : "\(baseName).jpg"

        KBLog.storage.kbInfo(
            "DocumentImageCompressor compressed \(fileName) \(data.count)B -> \(jpeg.count)B target=\(Int(targetSize.width))x\(Int(targetSize.height))"
        )
        return Output(data: jpeg, fileName: newName, mimeType: "image/jpeg", didCompress: true)
    }
}
