//
//  KBWidgetPhotos.swift
//  KidBox
//
//  Foto per il widget: quali mostrare e le loro miniature nell'App Group.
//
//  Le foto sono cifrate sul server e il widget non ha la chiave: le prepara
//  l'app. Sorgenti, dalla più economica: anteprima media già in cache,
//  originale decifrato in locale, download (pochi per giro). La miniatura
//  piccola del documento Firestore (~200 px) non basta per un quadrato a tutto
//  schermo, quindi non si usa: meglio aspettare il giro dopo.
//
//  Si lavora solo se un widget Foto ha chiesto le foto di recente
//  (`KBWidgetPhotoFiles.recentlyRequested`): chi non ha il widget non scarica nulla.
//

import Foundation
import SwiftData
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum KBWidgetPhotos {

    /// Lato lungo della miniatura: il widget largo è ~360 punti a 3x; 1000 px
    /// bastano e restano sotto il limite di memoria dell'estensione.
    nonisolated static let maxDimension: CGFloat = 1000
    private static let recentCount = 30
    private static let perAlbumCount = 10
    private static let downloadsPerRun = 12

    private static var running = false

    /// Le foto che il widget può mostrare: le più recenti, più le ultime di ogni
    /// album (così un widget su un album non resta vuoto). Niente video.
    static func candidates(familyId: String, context: ModelContext) -> (photos: [KBFamilyPhoto], albums: [KBPhotoAlbum]) {
        let photos = ((try? context.fetch(FetchDescriptor<KBFamilyPhoto>(
            predicate: #Predicate { $0.familyId == familyId && $0.isDeleted == false },
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        ))) ?? []).filter { !$0.isVideo }
        let albums = (try? context.fetch(FetchDescriptor<KBPhotoAlbum>(
            predicate: #Predicate { $0.familyId == familyId && $0.isDeleted == false },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))) ?? []

        var chosen = Array(photos.prefix(recentCount))
        var seen = Set(chosen.map(\.id))
        for album in albums {
            for p in photos.lazy.filter({ $0.albumIds.contains(album.id) }).prefix(perAlbumCount)
            where seen.insert(p.id).inserted {
                chosen.append(p)
            }
        }
        return (chosen, albums)
    }

    /// Per l'istantanea: solo le foto con la miniatura già sul disco.
    static func snapshotPart(familyId: String, context: ModelContext)
        -> (photos: [KBWidgetSnapshot.Photo], albums: [KBWidgetSnapshot.Album]) {
        let (photos, albums) = candidates(familyId: familyId, context: context)
        let fm = FileManager.default
        let ready = photos.filter { p in
            KBWidgetPhotoFiles.url(for: p.id).map { fm.fileExists(atPath: $0.path) } ?? false
        }
        return (
            ready.map { .init(id: $0.id, takenAt: $0.takenAt, albumIds: $0.albumIds) },
            albums.map { .init(id: $0.id, title: $0.title) }
        )
    }

    private struct Job: Sendable {
        let id: String
        let storagePath: String
        let localPath: String?
    }

    /// Prepara le miniature mancanti e toglie quelle che non servono più.
    /// Se ne aggiunge qualcuna, chiede un nuovo giro dell'istantanea.
    static func prepareIfNeeded(familyId: String, uid: String, context: ModelContext) {
        guard !running, KBWidgetPhotoFiles.recentlyRequested,
              let dir = KBWidgetPhotoFiles.directory else { return }
        let (photos, _) = candidates(familyId: familyId, context: context)
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Via le miniature di foto non più fra quelle scelte (cancellate, uscite dalle recenti).
        let wanted = Set(photos.map { KBWidgetPhotoFiles.fileName(for: $0.id) })
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !wanted.contains(name) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }

        let jobs = photos.compactMap { p -> Job? in
            guard let url = KBWidgetPhotoFiles.url(for: p.id), !fm.fileExists(atPath: url.path) else { return nil }
            return Job(id: p.id, storagePath: p.storagePath, localPath: p.localPath)
        }
        guard !jobs.isEmpty else { return }

        running = true
        Task {
            var added = 0
            var downloads = 0
            for job in jobs {
                guard let out = KBWidgetPhotoFiles.url(for: job.id) else { continue }
                var source: Data?
                if let cached = cachedPreview(job.id) {
                    source = cached
                } else if let lp = job.localPath, fm.fileExists(atPath: lp) {
                    source = try? Data(contentsOf: URL(fileURLWithPath: lp))
                } else if !job.storagePath.isEmpty, downloads < downloadsPerRun {
                    downloads += 1
                    source = try? await SyncCenter.photoRemote.download(
                        storagePath: job.storagePath, familyId: familyId, userId: uid
                    )
                }
                guard let source else { continue }
                let data = await Task.detached(priority: .utility) {
                    Self.downscale(source, maxDimension: Self.maxDimension)
                }.value
                if let data, (try? data.write(to: out, options: .atomic)) != nil { added += 1 }
            }
            running = false
            if added > 0 { KBWidgetSync.shared.requestRefresh(delay: .zero) }
        }
    }

    /// Anteprime medie che la griglia delle foto ha già generato (vedi `PhotoPreviewCache`).
    private static func cachedPreview(_ photoId: String) -> Data? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KBPhotoPreviews", isDirectory: true)
        for bucket in [1200, 800] {
            if let d = try? Data(contentsOf: dir.appendingPathComponent("\(photoId)_\(bucket).jpg")) { return d }
        }
        return nil
    }

    /// JPEG ridotto e già raddrizzato secondo l'EXIF.
    nonisolated static func downscale(_ data: Data, maxDimension: CGFloat) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
