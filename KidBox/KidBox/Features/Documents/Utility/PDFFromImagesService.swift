//
//  PDFFromImagesService.swift
//  KidBox
//

import Foundation
import ImageIO
import PDFKit
import SwiftData
import UIKit
import OSLog

/// Trasforma una o più immagini JPEG in un unico PDF, una pagina per immagine.
///
/// Stesso giro di `PDFMergeService`: scarica e decifra ogni documento in un file
/// temporaneo, costruisce il PDF e restituisce i byte, ripulendo i temporanei
/// comunque vada.
enum PDFFromImagesService {

    enum ConvertError: LocalizedError {
        case noImagesSelected
        case invalidImage(String)
        case noPages
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .noImagesSelected:    return "Nessuna immagine selezionata."
            case .invalidImage(let f): return "Impossibile leggere l'immagine: \(f)"
            case .noPages:            return "Le immagini selezionate non hanno prodotto pagine."
            case .saveFailed:         return "Impossibile salvare il PDF."
            }
        }
    }

    /// MIME accettati dalla conversione.
    private static let convertibleMimes: Set<String> = [
        "image/jpeg", "image/jpg", "image/png", "image/heic", "image/heif",
    ]

    /// Estensioni accettate, per i documenti caricati con un MIME generico.
    private static let convertibleExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif",
    ]

    /// Vero se il documento è un'immagine trasformabile in PDF.
    ///
    /// JPEG, PNG e HEIC: i tre formati che escono da fotocamera e schermate.
    /// `UIImage` li legge tutti nativamente, quindi non serve distinguerli più
    /// avanti — la trasparenza del PNG sì, e la gestisce `flattened`.
    static func isConvertibleImage(_ doc: KBDocument) -> Bool {
        if convertibleMimes.contains(doc.mimeType.lowercased()) { return true }
        return convertibleExtensions.contains((doc.fileName as NSString).pathExtension.lowercased())
    }

    // MARK: - Public

    /// PDF con una pagina per immagine, nell'ordine ricevuto.
    static func makePDF(
        docs: [KBDocument],
        modelContext: ModelContext
    ) async throws -> Data {
        guard !docs.isEmpty else { throw ConvertError.noImagesSelected }

        KBLog.data.kbInfo("PDFFromImagesService started count=\(docs.count)")

        var tempURLs: [URL] = []
        defer {
            for url in tempURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        for doc in docs {
            let tempURL = try await DocumentLocalCache.downloadToLocal(doc: doc, modelContext: modelContext)
            tempURLs.append(tempURL)
        }

        let pdf = PDFDocument()

        for (index, tempURL) in tempURLs.enumerated() {
            let name = docs[index].fileName
            guard let image = downsampled(at: tempURL) else {
                KBLog.data.kbError("PDFFromImagesService unreadable image name=\(name)")
                throw ConvertError.invalidImage(name)
            }
            guard let page = PDFPage(image: flattened(image)) else {
                KBLog.data.kbError("PDFFromImagesService page build failed name=\(name)")
                throw ConvertError.invalidImage(name)
            }
            pdf.insert(page, at: pdf.pageCount)
        }

        guard pdf.pageCount > 0 else { throw ConvertError.noPages }
        guard let data = pdf.dataRepresentation() else {
            KBLog.data.kbError("PDFFromImagesService dataRepresentation() returned nil")
            throw ConvertError.saveFailed
        }

        KBLog.data.kbInfo("PDFFromImagesService completed pages=\(pdf.pageCount) bytes=\(data.count)")
        return data
    }

    // MARK: - Private

    /// Lato lungo massimo in pixel, come su Android e sul web: ~250 dpi su un A4.
    private static let maxPixelSide = 3000

    /// Carica l'immagine già ridotta entro il tetto e già raddrizzata.
    ///
    /// Si passa da ImageIO invece che da `UIImage(data:)` per non decodificare
    /// mai l'originale intero: una foto da 12 MP sarebbe un bitmap da ~48 MB, e
    /// con parecchie pagine si arriva a esaurire la memoria. È lo stesso motivo
    /// per cui su Android si usa `inSampleSize`.
    ///
    /// `kCGImageSourceCreateThumbnailWithTransform` applica l'orientamento EXIF:
    /// le foto portano la rotazione nei metadati e `PDFPage(image:)` guarda i
    /// pixel, quindi senza raddrizzarle una foto verticale finirebbe coricata.
    ///
    /// Se ImageIO non ce la fa si torna alla decodifica diretta: meglio una
    /// pagina pesante che nessuna pagina.
    private static func downsampled(at url: URL) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        if let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) {
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSide,
            ] as CFDictionary
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                return UIImage(cgImage: cgImage)
            }
        }

        KBLog.data.kbError("PDFFromImagesService ImageIO failed, fallback name=\(url.lastPathComponent)")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Ridisegna l'immagine su fondo bianco quando ha un canale alfa.
    ///
    /// Un PNG trasparente su una pagina senza fondo diventa nero, perché il
    /// contesto opaco parte da quel colore. Senza alfa si restituisce com'è: il
    /// ridisegno costa memoria e non aggiungerebbe nulla. L'orientamento è già
    /// stato applicato da `downsampled`.
    private static func flattened(_ image: UIImage) -> UIImage {
        guard hasAlpha(image) else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: image.size))
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func hasAlpha(_ image: UIImage) -> Bool {
        switch image.cgImage?.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast, nil:
            return false
        default:
            return true
        }
    }
}
