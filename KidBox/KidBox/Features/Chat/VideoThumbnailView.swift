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
    var onImageSize: ((CGSize) -> Void)? = nil
    
    @State private var image: UIImage?
    @State private var showsSpinner = false
    
    init(videoURL: URL, cacheKey: String, onImageSize: ((CGSize) -> Void)? = nil) {
        self.videoURL = videoURL
        self.cacheKey = cacheKey
        self.onImageSize = onImageSize
        // Rientro in chat: l'anteprima già vista c'è dal primo frame.
        _image = State(initialValue: VideoThumbnailCache.shared.memoryImage(cacheKey))
    }
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground))
                    if showsSpinner { ProgressView() }
                }
                .task(id: cacheKey) { await load() }
                .task(id: cacheKey) {
                    try? await Task.sleep(for: .milliseconds(400))
                    if !Task.isCancelled { showsSpinner = true }
                }
            }
        }
    }
    
    @MainActor
    private func load() async {
        if let cached = VideoThumbnailCache.shared.get(cacheKey) {
            self.image = cached
            onImageSize?(cached.size)
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
            onImageSize?(img.size)
        }
    }
}
