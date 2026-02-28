//
//  ChatUIComponents.swift
//  KidBox
//
//  Created by vscocca on 28/02/26.
//

import SwiftUI
import MapKit

// MARK: - Shared sizing
enum ChatThumbStyle {
    static let composerReplySize: CGFloat = 26
    static let replyCorner: CGFloat = 6
    
    static let bubbleReplySize: CGFloat = 36
    static let composerCorner: CGFloat = 8
    
    static let mediaW: CGFloat = 220
    static let mediaH: CGFloat = 160
    static let mediaCorner: CGFloat = 10
}

// MARK: - URL extractor
enum ChatLinkDetector {
    static func firstURL(in text: String) -> URL? {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return d.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.url
    }
}

// MARK: - Link preview thumb (shared)
struct LinkPreviewThumb: View {
    let url: URL
    let size: CGFloat
    let corner: CGFloat
    
    @EnvironmentObject private var store: LinkPreviewStore
    
    init(url: URL, size: CGFloat, corner: CGFloat) {
        self.url = url
        self.size = size
        self.corner = corner
    }
    
    var body: some View {
        Group {
            switch store.previews[url] {
            case .ready(let meta):
                if let iu = meta.imageURL {
                    CachedAsyncImage(url: iu, contentMode: .fill)
                } else {
                    placeholder
                }
            default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .onAppear { store.fetchIfNeeded(for: url) }
    }
    
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(Color.primary.opacity(0.08))
    }
}

// MARK: - Mini location thumb (shared)
struct MiniLocationThumb: View {
    let latitude: Double
    let longitude: Double
    
    private var center: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    
    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: center,
            span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))) {
            Marker("", coordinate: center)
        }
        .mapStyle(.standard)
        .allowsHitTesting(false)
    }
}
