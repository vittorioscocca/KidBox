//
//  CachedAsyncImage.swift
//  KidBox
//
//  Created by vscocca on 22/02/26.
//

import SwiftUI
import UIKit

extension UIImage {
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}

struct CachedAsyncImage: View {
    let url: URL
    var contentMode: ContentMode = .fill
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemBackground))
                    ProgressView()
                }
                .task(id: url) { await load() }
            }
        }
    }
    
    @MainActor
    private func load() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        
        if let cached = ImageMemoryCache.shared.get(url) {
            self.image = cached
            return
        }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let ui = UIImage(data: data) {
                let fixed = ui.fixedOrientation()
                print("orientation:", ui.imageOrientation.rawValue)// <-- QUI
                ImageMemoryCache.shared.set(fixed, for: url) // <-- cache del fixed
                self.image = fixed
            }
        } catch {
            // placeholder
        }
    }
}
