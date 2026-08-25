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
                    GeometryReader { geo in
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: 300)
                            .clipped()
                            .allowsHitTesting(false)
                    }
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
                                Text(badgeText)
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
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            // L'id include il timestamp: un ritaglio o una nuova foto cambiano
            // `heroPhotoUpdatedAt` anche quando l'URL resta identico (il path su
            // Storage è fisso, `hero/hero.jpg`), e senza il timestamp nell'id la
            // card continuerebbe a mostrare la versione precedente.
            .task(id: "\(photoURL?.absoluteString ?? "")|\(photoUpdatedAt?.timeIntervalSince1970 ?? 0)") {
                loader.load(url: photoURL, updatedAt: photoUpdatedAt)
            }
            
        }
        .buttonStyle(.plain)
    }

    // Stessa dicitura dinamica del badge in basso: se non c'è ancora una foto
    // il tasto deve invitare ad aggiungerla, non a "cambiarla".
    // Tipizzato `LocalizedStringKey` (non `String`) per restare risolto dal
    // catalogo di localizzazione invece di essere trattato come testo verbatim.
    private var badgeText: LocalizedStringKey {
        if isBusy { return "Caricamento…" }
        return loader.image == nil ? "Aggiungi foto famiglia" : "Tocca per cambiare foto"
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
            Image(systemName: "person.2.fill")
                .font(.title)
                .foregroundStyle(.secondary)
        }
        .frame(height: 300)
    }
}

@MainActor
final class HeroImageLoader: ObservableObject {
    @Published var image: UIImage?
    
    private var task: Task<Void, Never>?
    
    func load(url: URL?, updatedAt: Date?) {
        task?.cancel()
        guard let url else {
            image = nil
            return
        }

        // Cache valida per questa versione remota: si mostra subito, senza rete.
        // `image` non viene azzerato prima del controllo, altrimenti il
        // placeholder lampeggerebbe anche quando la foto è già sul dispositivo.
        if let cached = HeroImageCache.image(for: url, updatedAt: updatedAt) {
            image = cached
            KBLog.sync.kbDebug("HeroImageLoader: cache hit, skipping download")
            return
        }

        image = nil

        task = Task {
            // Un solo ritentativo: "network connection lost" e i timeout sono
            // glitch transitori tipici del passaggio Wi-Fi/cellulare, non
            // guasti veri — al secondo tentativo la hero si carica.
            for attempt in 0...1 {
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
                        // Si salva solo ciò che è stato decodificato davvero:
                        // mettere in cache byte non validi li farebbe ripresentare
                        // a ogni avvio senza più passare dalla rete.
                        HeroImageCache.store(data, for: url, updatedAt: updatedAt)
                    }
                    return

                } catch {
                    if Task.isCancelled { return }

                    if Self.isTransientNetworkError(error) {
                        if attempt == 0 {
                            KBLog.sync.kbDebug("HeroImageLoader: transient network error, retrying: \(error.localizedDescription)")
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            continue
                        }
                        // Esaurito il ritentativo resta un problema di rete
                        // dell'utente, non un difetto dell'app: warning, così
                        // non finisce tra i casi critici in console.
                        KBLog.sync.kbWarning("HeroImageLoader: network unavailable: \(error.localizedDescription)")
                    } else {
                        KBLog.sync.kbError("HeroImageLoader error: \(error.localizedDescription)")
                    }
                    return
                }
            }
        }
    }

    private static func isTransientNetworkError(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed,
        ].contains(ns.code)
    }
}
