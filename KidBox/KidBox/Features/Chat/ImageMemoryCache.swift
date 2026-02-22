//
//  ImageMemoryCache.swift
//  KidBox
//
//  Created by vscocca on 22/02/26.
//

import UIKit

final class ImageMemoryCache {
    static let shared = ImageMemoryCache()
    private init() {}
    
    private let cache = NSCache<NSURL, UIImage>()
    
    func get(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }
    
    func set(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}
