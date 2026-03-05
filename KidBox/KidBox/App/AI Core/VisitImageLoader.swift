//
//  VisitImageLoader.swift
//  KidBox
//

import Foundation
import OSLog
import UIKit

/// Downloads visit photos from Firebase Storage URLs and converts them to base64.
/// Images are cached on disk — successive opens of the same visit are instant.
enum VisitImageLoader {
    
    private static let log = Logger(subsystem: "com.kidbox", category: "visit_image_loader")
    private static let maxDimension: CGFloat = 1200
    private static let maxImages = 5
    
    /// Cache directory: <Caches>/KidBox/VisitImages/
    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir  = base.appendingPathComponent("KidBox/VisitImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    struct EncodedImage {
        let base64:    String
        let mediaType: String
    }
    
    // MARK: - Public
    
    static func loadImages(from urls: [String]) async -> [EncodedImage] {
        let limited = Array(urls.prefix(maxImages))
        guard !limited.isEmpty else { return [] }
        
        log.debug("VisitImageLoader: loading \(limited.count) images")
        
        var results: [EncodedImage] = []
        
        await withTaskGroup(of: EncodedImage?.self) { group in
            for urlString in limited {
                group.addTask { await loadSingle(urlString: urlString) }
            }
            for await result in group {
                if let img = result { results.append(img) }
            }
        }
        
        log.info("VisitImageLoader: loaded \(results.count)/\(limited.count) images")
        return results
    }
    
    /// Removes all cached images older than `days` days.
    /// Call periodically (e.g. on app launch) to avoid unbounded growth.
    static func clearStaleCache(olderThanDays days: Int = 30) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        
        var removed = 0
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified < cutoff {
                try? FileManager.default.removeItem(at: file)
                removed += 1
            }
        }
        if removed > 0 { log.info("VisitImageLoader: cleared \(removed) stale cached images") }
    }
    
    // MARK: - Private
    
    private static func loadSingle(urlString: String) async -> EncodedImage? {
        guard let url = URL(string: urlString) else {
            log.warning("VisitImageLoader: invalid URL")
            return nil
        }
        
        let mediaType = detectMediaTypeFromURL(url)
        let cacheKey  = cacheFileName(for: urlString, mediaType: mediaType)
        let cacheFile = cacheDir.appendingPathComponent(cacheKey)
        
        // ── Cache hit ──
        if let cached = try? Data(contentsOf: cacheFile) {
            log.debug("VisitImageLoader: cache hit \(cacheKey)")
            return EncodedImage(base64: cached.base64EncodedString(), mediaType: mediaType)
        }
        
        // ── Download ──
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                log.warning("VisitImageLoader: bad HTTP response")
                return nil
            }
            
            let finalData = resizeIfNeeded(data: data, mediaType: mediaType) ?? data
            
            // Salva in cache
            try? finalData.write(to: cacheFile, options: .atomic)
            log.debug("VisitImageLoader: downloaded and cached \(cacheKey) size=\(finalData.count / 1024)KB")
            
            return EncodedImage(base64: finalData.base64EncodedString(), mediaType: mediaType)
            
        } catch {
            log.error("VisitImageLoader: download failed \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Stable cache filename: SHA-like hash of the URL string + extension.
    private static func cacheFileName(for urlString: String, mediaType: String) -> String {
        let hash = abs(urlString.hashValue)
        let ext  = mediaType == "image/png" ? "png" : "jpg"
        return "\(hash).\(ext)"
    }
    
    private static func detectMediaTypeFromURL(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "png"  { return "image/png"  }
        if ext == "webp" { return "image/webp" }
        return "image/jpeg"
    }
    
    private static func resizeIfNeeded(data: Data, mediaType: String) -> Data? {
#if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return data }
        
        let scale   = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized  = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        
        return mediaType == "image/png"
        ? resized.pngData()
        : resized.jpegData(compressionQuality: 0.82)
#else
        return data
#endif
    }
}
