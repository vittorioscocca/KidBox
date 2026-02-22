//
//  VideoThumbnailView.swift
//  KidBox
//
//  Created by vscocca on 22/02/26.
//

import SwiftUI
import AVFoundation
import UIKit

struct VideoThumbnailView: View {
    let videoURL: URL
    let cacheKey: String
    
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground))
                    ProgressView()
                }
                .task(id: cacheKey) { await load() }
            }
        }
    }
    
    @MainActor
    private func load() async {
        if let cached = VideoThumbnailCache.shared.get(cacheKey) {
            self.image = cached
            return
        }
        
        let url = videoURL
        
        let img: UIImage? = await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)
            
            return await withCheckedContinuation { continuation in
                let time = CMTime(seconds: 0, preferredTimescale: 600)
                
                generator.generateCGImageAsynchronously(for: time) { cgImage, _, error in
                    if let cgImage {
                        continuation.resume(returning: UIImage(cgImage: cgImage))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }.value
        
        if let img {
            VideoThumbnailCache.shared.set(img, key: cacheKey)
            self.image = img
        }
    }
}
