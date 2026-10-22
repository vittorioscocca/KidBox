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
    var onImageSize: ((CGSize) -> Void)? = nil
    
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var showsSpinner = false

    init(url: URL, contentMode: ContentMode = .fill, onImageSize: ((CGSize) -> Void)? = nil) {
        self.url = url
        self.contentMode = contentMode
        self.onImageSize = onImageSize
        // Già in memoria (rientro in chat): l'immagine c'è dal primo frame,
        // senza il riquadro grigio che lampeggia.
        _image = State(initialValue: ImageMemoryCache.shared.get(url))
    }

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
                    // Lo spinner solo se serve la rete: dal disco l'immagine arriva prima.
                    if showsSpinner { ProgressView() }
                }
                .task(id: url) { await load() }
                .task(id: url) {
                    try? await Task.sleep(for: .milliseconds(400))
                    if !Task.isCancelled { showsSpinner = true }
                }
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
            onImageSize?(cached.size)
            return
        }

        let url = self.url
        // Disco e decodifica fuori dal main thread: decodificare sul main
        // bloccava lo scroll a ogni foto che entrava nello schermo.
        var decoded: UIImage? = await Task.detached(priority: .userInitiated) {
            ChatImageDiskCache.data(for: url).flatMap { ChatImageDiskCache.decode($0) }
        }.value

        if decoded == nil {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
            decoded = await Task.detached(priority: .userInitiated) {
                guard let image = ChatImageDiskCache.decode(data) else { return nil }
                ChatImageDiskCache.store(data, for: url)
                return image
            }.value
        }

        guard let decoded else { return }
        ImageMemoryCache.shared.set(decoded, for: url)
        guard !Task.isCancelled else { return }
        self.image = decoded
        onImageSize?(decoded.size)
    }
}
