//
//  HomeHeroCard.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI
import Combine

// MARK: - HERO CARD (con crop)

struct HomeHeroCard: View {
    let title: String
    let subtitle: String
    let dateText: String
    let rightBadgeText: String
    
    let photoURL: URL?
    let photoUpdatedAt: Date?
    
    let scale: Double
    let offsetX: Double
    let offsetY: Double
    
    let isBusy: Bool
    let action: () -> Void
    
    @StateObject private var loader = HeroImageLoader()
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                
                if let ui = loader.image {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(height: 300)
                        .clipped()
                } else {
                    placeholder
                }
                
                LinearGradient(
                    colors: [Color.black.opacity(0.05), Color.black.opacity(0.60)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                
                VStack(spacing: 0) {
                    HStack {
                        Text(dateText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                        
                        Spacer()
                        
                        if !rightBadgeText.isEmpty {
                            Text(rightBadgeText)
                                .font(.caption2).bold()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(.white.opacity(0.18))
                                .clipShape(Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    
                    Spacer()
                    
                    HStack {
                        VStack(spacing: 0) {
                            
                            Text(title)
                                .font(.title2).bold()
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.90))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            HStack(spacing: 8) {
                                Image(systemName: "photo")
                                Text(isBusy ? "Caricamento…" : "Tocca per cambiare foto")
                            }
                            .font(.subheadline).bold()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        
                        Spacer()
                    }
                    
                }
                
                if isBusy {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .task(id: photoURL?.absoluteString) {
                loader.load(url: photoURL)
            }
            
        }
        .buttonStyle(.plain)
    }
    
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
            VStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Aggiungi una foto famiglia")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 300)
    }
}

@MainActor
final class HeroImageLoader: ObservableObject {
    @Published var image: UIImage?
    
    private var task: Task<Void, Never>?
    
    func load(url: URL?) {
        task?.cancel()
        image = nil
        guard let url else { return }
        
        task = Task {
            do {
                KBLog.sync.kbDebug("HeroImageLoader: loading from \(url.absoluteString)")
                let (data, response) = try await URLSession.shared.data(from: url)
                
                if Task.isCancelled { return }
                
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                KBLog.sync.kbDebug("HeroImageLoader: received \(data.count) bytes, status=\(statusCode)")
                
                image = UIImage(data: data)
                
                if image == nil {
                    KBLog.sync.kbError("HeroImageLoader: UIImage(data:) returned nil despite \(data.count) bytes")
                } else {
                    KBLog.sync.kbInfo("HeroImageLoader: image loaded successfully")
                }
                
            } catch {
                if Task.isCancelled { return }
                KBLog.sync.kbError("HeroImageLoader error: \(error.localizedDescription)")
            }
        }
    }
}
