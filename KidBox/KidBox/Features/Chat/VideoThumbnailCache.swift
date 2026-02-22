//
//  VideoThumbnailCache.swift
//  KidBox
//
//  Created by vscocca on 22/02/26.
//

import Foundation
import UIKit
import CryptoKit

final class VideoThumbnailCache {
    static let shared = VideoThumbnailCache()
    private init() {}
    
    private let mem = NSCache<NSString, UIImage>()
    
    private var dir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let d = base.appendingPathComponent("kidbox-video-thumbs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }
    
    func get(_ key: String) -> UIImage? {
        if let img = mem.object(forKey: key as NSString) { return img }
        let url = fileURL(for: key)
        if let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            mem.setObject(img, forKey: key as NSString)
            return img
        }
        return nil
    }
    
    func set(_ image: UIImage, key: String) {
        mem.setObject(image, forKey: key as NSString)
        let url = fileURL(for: key)
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url, options: [.atomic])
        }
    }
    
    private func fileURL(for key: String) -> URL {
        let hashed = SHA256.hash(data: Data(key.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent("\(hashed).jpg")
    }
}
