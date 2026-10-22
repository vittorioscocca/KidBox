//
//  ImageMemoryCache.swift
//  KidBox
//
//  Created by vscocca on 22/02/26.
//

import UIKit
import ImageIO
import CryptoKit

final class ImageMemoryCache {
    static let shared = ImageMemoryCache()
    private init() {
        // Il costo è in byte decodificati: senza tetto NSCache tratteneva
        // immagini a piena risoluzione finché il sistema non la svuotava.
        cache.totalCostLimit = 200 * 1024 * 1024
    }

    private let cache = NSCache<NSURL, UIImage>()

    func get(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

// MARK: - ChatImageDiskCache

/// Copia su disco dei byte scaricati, così dopo un kill le foto della chat
/// tornano dal telefono e non dalla rete (la URLCache di sistema è piccola e
/// le butta presto). Tutto fuori dal main thread.
nonisolated enum ChatImageDiskCache {
    private static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let d = base.appendingPathComponent("kidbox-chat-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func data(for url: URL) -> Data? {
        try? Data(contentsOf: fileURL(for: url))
    }

    static func store(_ data: Data, for url: URL) {
        try? data.write(to: fileURL(for: url), options: [.atomic])
    }

    private static func fileURL(for url: URL) -> URL {
        let hashed = SHA256.hash(data: Data(url.absoluteString.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(hashed)
    }

    /// Decodifica già pronta per lo schermo: orientamento applicato, lato lungo
    /// al massimo `maxPixel`, pixel decompressi qui e non al primo disegno.
    static func decode(_ data: Data, maxPixel: CGFloat = 2048) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }
}
