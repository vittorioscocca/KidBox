//
//  PhotoFullscreenView.swift
//  KidBox
//
//  Created by vscocca on 31/03/26.
//


import SwiftUI
import SwiftData
import AVKit
import CoreGraphics
import ImageIO

// MARK: - IdentifiableImagePath
// Wrapper Identifiable per il path del JPEG su disco.
// Necessario per sheet(item:) in PhotoEditorView.
struct IdentifiableImagePath: Identifiable {
    let id   = UUID()
    let path: String
}

// MARK: - PhotoFullscreenView

struct PhotoFullscreenView: View {
    
    let startPhoto: KBFamilyPhoto
    let allPhotos:  [KBFamilyPhoto]
    let familyId:   String
    let userId:     String
    let onDismiss:  () -> Void
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var currentIndex:    Int
    @State private var imageCache:      [String: UIImage] = [:]
    @State private var imageCacheOrder: [String]          = []
    @State private var videoURLCache:   [String: URL]     = [:]
    @State private var editorImagePath: IdentifiableImagePath? = nil
    
    @State private var showChrome:      Bool    = true
    @State private var dragOffset:      CGFloat = 0
    
    // Share
    @State private var shareItems:      [Any]   = []
    @State private var showShare:       Bool    = false
    @State private var isPreparingShare: Bool   = false
    
    // Delete
    @State private var showDeleteConfirm: Bool  = false
    
    private let maxCachedImages = 3
    
    init(startPhoto: KBFamilyPhoto, allPhotos: [KBFamilyPhoto],
         familyId: String, userId: String, onDismiss: @escaping () -> Void) {
        self.startPhoto = startPhoto
        self.allPhotos  = allPhotos
        self.familyId   = familyId
        self.userId     = userId
        self.onDismiss  = onDismiss
        _currentIndex   = State(initialValue: allPhotos.firstIndex { $0.id == startPhoto.id } ?? 0)
    }
    
    private var currentPhoto: KBFamilyPhoto {
        guard allPhotos.indices.contains(currentIndex) else { return startPhoto }
        return allPhotos[currentIndex]
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                // Aperta a schermo intero dalla griglia: l'origine è sempre la
                // lista, e non serve il coordinator (qui si arriva da un
                // fullScreenCover, non da una route).
                .onAppear {
                    let photo = startPhoto
                    Task {
                        await KBAnalytics.shared.logRetrieval(
                            feature: .photoVideo,
                            uploaderUid: photo.createdBy,
                            createdAt: photo.createdAt,
                            entryPoint: .list
                        )
                    }
                }
            
            // ── Pager ────────────────────────────────────────────────────────
            TabView(selection: $currentIndex) {
                ForEach(allPhotos.indices, id: \.self) { i in
                    let p = allPhotos[i]
                    PhotoFullscreenCell(
                        photo:    p,
                        image:    imageCache[p.id],
                        videoURL: videoURLCache[p.id]
                    )
                    .tag(i)
                    .task(id: p.id) { await load(p) }
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: dragOffset)
            
            // ── Chrome ───────────────────────────────────────────────────────
            if showChrome {
                VStack(spacing: 0) {
                    
                    // Top bar
                    HStack(alignment: .top) {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        .padding(.leading, 16)
                        .padding(.top, 60)
                        
                        Spacer()
                        
                        VStack(spacing: 2) {
                            if let caption = currentPhoto.caption, !caption.isEmpty {
                                Text(caption)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white).lineLimit(1)
                            }
                            Text(currentPhoto.takenAt.formatted(
                                date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                        }
                        .padding(.top, 60)
                        
                        Spacer()
                        
                        Text("\(currentIndex + 1) / \(allPhotos.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.4), in: Capsule())
                            .padding(.trailing, 16)
                            .padding(.top, 60)
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(colors: [.black.opacity(0.65), .clear],
                                       startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .top)
                    )
                    
                    Spacer()
                    
                    // ── Bottom area ───────────────────────────────────────────
                    VStack(spacing: 0) {
                        
                        // Thumbnail strip
                        if allPhotos.count > 1 {
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 3) {
                                        ForEach(allPhotos.indices, id: \.self) { idx in
                                            thumbCell(photo: allPhotos[idx], idx: idx)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                }
                                .onChange(of: currentIndex) { _, newIdx in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        proxy.scrollTo("pthumb_\(newIdx)", anchor: .center)
                                    }
                                }
                            }
                        }
                        
                        Divider().overlay(Color.white.opacity(0.15))
                        
                        // Toolbar
                        HStack(spacing: 0) {
                            
                            // Condividi
                            toolbarBtn(icon: "square.and.arrow.up",
                                       label: isPreparingShare ? "…" : "Condividi") {
                                Task { await shareCurrentPhoto() }
                            }
                                       .disabled(isPreparingShare)
                            
                            // Modifica (solo foto, non video)
                            if !currentPhoto.isVideo {
                                toolbarBtn(icon: "slider.horizontal.3", label: "Modifica") {
                                    Task { await loadOriginalForEditor(currentPhoto) }
                                }
                            } else {
                                // placeholder per mantenere la spaziatura
                                Color.clear.frame(maxWidth: .infinity).frame(height: 56)
                            }
                            
                            // Elimina
                            toolbarBtn(icon: "trash", label: "Elimina", tint: .red) {
                                showDeleteConfirm = true
                            }
                        }
                        .padding(.bottom, 28)
                    }
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                       startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                    )
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(!showChrome)
        // Swipe down per chiudere
        .gesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onChanged { v in
                    guard v.translation.height > 0 else { return }
                    dragOffset = v.translation.height
                }
                .onEnded { v in
                    if v.translation.height > 120 || v.predictedEndTranslation.height > 200 {
                        withAnimation(.easeIn(duration: 0.2)) {
                            dragOffset = UIScreen.main.bounds.height
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        // Editor sheet
        .sheet(item: $editorImagePath) { item in
            PhotoEditorView(
                photo: currentPhoto,
                imagePath: item.path,
                familyId: familyId,
                userId: userId,
                onSaved: { _ in }
            )
        }
        // Share sheet
        .sheet(isPresented: $showShare) {
            ActivityViewControllerPhoto(activityItems: shareItems)
                .ignoresSafeArea()
        }
        // Conferma elimina
        .confirmationDialog("Eliminare questa foto?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { deleteCurrentPhoto() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("La foto verrà rimossa da tutti i dispositivi.")
        }
        .onDisappear {
            imageCache.removeAll()
            imageCacheOrder.removeAll()
        }
    }
    
    // MARK: - Thumbnail strip cell
    
    @ViewBuilder
    private func thumbCell(photo: KBFamilyPhoto, idx: Int) -> some View {
        let isSelected = idx == currentIndex
        ZStack {
            if let td = photo.thumbnailData, let img = UIImage(data: td) {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 52, height: 52).clipped()
            } else {
                Color.gray.opacity(0.3).frame(width: 52, height: 52)
            }
            if photo.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(.black.opacity(0.5), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(3)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 2)
        )
        .opacity(isSelected ? 1 : 0.55)
        .id("pthumb_\(idx)")
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { currentIndex = idx }
        }
    }
    
    // MARK: - Toolbar button
    
    private func toolbarBtn(icon: String, label: String,
                            tint: Color = .white,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(tint)
                Text(label).font(.caption2).foregroundStyle(tint.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Share
    
    private func shareCurrentPhoto() async {
        isPreparingShare = true
        defer { isPreparingShare = false }
        
        var items: [Any] = []
        
        // Usa il file locale se disponibile
        if let path = currentPhoto.localPath,
           FileManager.default.fileExists(atPath: path) {
            if currentPhoto.isVideo {
                items = [URL(fileURLWithPath: path)]
            } else if let img = UIImage(contentsOfFile: path) {
                items = [img]
            }
        }
        
        // Altrimenti scarica
        if items.isEmpty, !currentPhoto.storagePath.isEmpty {
            do {
                let data = try await SyncCenter.photoRemote.download(
                    storagePath: currentPhoto.storagePath,
                    familyId: familyId, userId: userId)
                if currentPhoto.isVideo {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(currentPhoto.id).mp4")
                    try? data.write(to: tmp)
                    items = [tmp]
                } else if let img = UIImage(data: data) {
                    items = [img]
                }
            } catch {
                KBLog.sync.kbError("PhotoFullscreen share: download failed photoId=\(currentPhoto.id)")
            }
        }
        
        if !items.isEmpty {
            await MainActor.run {
                shareItems = items
                showShare  = true
            }
        }
    }
    
    // MARK: - Delete
    
    private func deleteCurrentPhoto() {
        let photo = currentPhoto
        photo.isDeleted = true; photo.updatedAt = Date()
        try? modelContext.save()
        let photoId = photo.id; let fid = familyId
        Task {
            do { try await SyncCenter.photoRemote.softDeletePhoto(familyId: fid, photoId: photoId) }
            catch { KBLog.sync.kbError("softDeletePhoto: FAILED photoId=\(photoId) err=\(error.localizedDescription)") }
        }
        onDismiss()
    }
    
    // MARK: - Load original for editor
    
    private func loadOriginalForEditor(_ photo: KBFamilyPhoto) async {
        if let localPath = photo.localPath,
           FileManager.default.fileExists(atPath: localPath) {
            await MainActor.run { editorImagePath = IdentifiableImagePath(path: localPath) }
            return
        }
        guard !photo.storagePath.isEmpty else { return }
        do {
            let data = try await SyncCenter.photoRemote.download(
                storagePath: photo.storagePath, familyId: familyId, userId: userId)
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("KBPhotos", isDirectory: true)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let origURL = cacheDir.appendingPathComponent("\(photo.id)_orig.jpg")
            try? data.write(to: origURL, options: .atomic)
            await MainActor.run { editorImagePath = IdentifiableImagePath(path: origURL.path) }
        } catch {
            KBLog.sync.kbError("PhotoFullscreen: loadOriginalForEditor FAILED photoId=\(photo.id) err=\(error.localizedDescription)")
        }
    }
    
    // MARK: - Load (download + cache)
    
    private func load(_ photo: KBFamilyPhoto) async {
        let isVideo = photo.isVideo
        if isVideo  && videoURLCache[photo.id] != nil { return }
        if !isVideo && imageCache[photo.id]    != nil { return }
        
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KBPhotos", isDirectory: true)
        let ext      = isVideo ? "mp4" : "jpg"
        let localURL = cacheDir.appendingPathComponent("\(photo.id).\(ext)")
        
        if FileManager.default.fileExists(atPath: localURL.path) {
            if isVideo {
                await MainActor.run { videoURLCache[photo.id] = localURL }
            } else if let img = downscaleForDisplayFromURL(localURL) {
                await MainActor.run { addToImageCache(id: photo.id, image: img) }
            }
            return
        }
        
        guard !photo.storagePath.isEmpty else { return }
        do {
            let data = try await SyncCenter.photoRemote.download(
                storagePath: photo.storagePath, familyId: familyId, userId: userId)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            
            if isVideo {
                let rawTmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
                do { try data.write(to: rawTmp, options: .atomic) } catch { return }
                let playableURL: URL
                if let remuxed = await VideoCompressor.remux(from: rawTmp, to: localURL) {
                    playableURL = remuxed
                } else {
                    try? FileManager.default.copyItem(at: rawTmp, to: localURL)
                    playableURL = localURL
                }
                try? FileManager.default.removeItem(at: rawTmp)
                await MainActor.run { videoURLCache[photo.id] = playableURL }
                
                if photo.videoDurationSeconds == nil,
                   let dur = await VideoCompressor.videoDuration(url: playableURL) {
                    await MainActor.run {
                        photo.videoDurationSeconds = dur
                        if !photo.mimeType.hasPrefix("video/") { photo.mimeType = "video/mp4" }
                    }
                    Task {
                        try? await SyncCenter.photoRemote.upsertMetadata(dto: RemotePhotoDTO(
                            id: photo.id, familyId: familyId,
                            fileName: photo.fileName, mimeType: "video/mp4",
                            fileSize: photo.fileSize, storagePath: photo.storagePath,
                            downloadURL: photo.downloadURL, thumbnailBase64: photo.thumbnailBase64,
                            caption: photo.caption, albumIdsRaw: photo.albumIdsRaw,
                            videoDurationSeconds: dur, takenAt: photo.takenAt,
                            createdAt: photo.createdAt, updatedAt: photo.updatedAt,
                            createdBy: photo.createdBy, updatedBy: photo.updatedBy,
                            isDeleted: photo.isDeleted
                        ))
                    }
                }
            } else {
                try? data.write(to: localURL, options: .atomic)
                if let img = downscaleForDisplayFromURL(localURL) {
                    await MainActor.run { addToImageCache(id: photo.id, image: img) }
                }
            }
        } catch {
            KBLog.sync.kbError("PhotoFullscreen: load FAILED photoId=\(photo.id) err=\(error.localizedDescription)")
        }
    }
    
    // MARK: - Cache management (LRU, max 3)
    
    private func addToImageCache(id: String, image: UIImage) {
        if imageCache[id] != nil { imageCache[id] = image; return }
        if imageCacheOrder.count >= maxCachedImages, let oldest = imageCacheOrder.first {
            imageCache.removeValue(forKey: oldest)
            imageCacheOrder.removeFirst()
        }
        imageCache[id] = image
        imageCacheOrder.append(id)
    }
    
    // MARK: - Downscale helpers
    
    private func downscaleForDisplayFromURL(_ url: URL) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return Self.downscaleSource(src)
    }
    
    private static func downscaleSource(_ src: CGImageSource) -> UIImage? {
        let props   = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let origW   = (props?[kCGImagePropertyPixelWidth]  as? CGFloat) ?? 0
        let origH   = (props?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
        let origMax = max(origW, origH)
        let screen  = UIScreen.main.bounds.size
        let scale   = UIScreen.main.scale
        let target  = max(screen.width, screen.height) * scale * 1.5
        let maxPx   = origMax > 0 ? min(target, origMax) : target
        let opts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize:          maxPx,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform:   true
        ]
        guard let cgImg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImg)
    }
}

// MARK: - PhotoFullscreenCell

private struct PhotoFullscreenCell: View {
    
    let photo:    KBFamilyPhoto
    let image:    UIImage?
    let videoURL: URL?
    
    @State private var isPlaying   = false
    @State private var playerReady = false
    
    var body: some View {
        ZStack {
            Color.black
            if photo.isVideo {
                if !playerReady { thumbnailView }
                if isPlaying, let url = videoURL {
                    VideoPlayerCell(url: url, onReady: {
                        withAnimation(.easeIn(duration: 0.2)) { playerReady = true }
                    })
                    .opacity(playerReady ? 1 : 0)
                }
                if !playerReady {
                    if isPlaying {
                        ProgressView().tint(.white).scaleEffect(1.4)
                    } else {
                        Button { isPlaying = true } label: {
                            ZStack {
                                Circle().fill(.black.opacity(0.45)).frame(width: 72, height: 72)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.white).offset(x: 3)
                            }
                        }
                    }
                }
            } else {
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFit()
                } else {
                    thumbnailView.overlay(ProgressView().tint(.white))
                }
            }
        }
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private var thumbnailView: some View {
        if let td = photo.thumbnailData, let img = UIImage(data: td) {
            Image(uiImage: img).resizable().scaledToFit()
        } else {
            Color.black
        }
    }
}

// MARK: - VideoPlayerCell

private struct VideoPlayerCell: UIViewControllerRepresentable {
    let url:     URL
    let onReady: () -> Void
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        let vc     = AVPlayerViewController()
        vc.player = player; vc.showsPlaybackControls = true
        context.coordinator.observe(player: player, onReady: onReady)
        player.play()
        return vc
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator {
        private var observation: NSKeyValueObservation?
        private var didFire = false
        func observe(player: AVPlayer, onReady: @escaping () -> Void) {
            observation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
                guard let self, !self.didFire else { return }
                if p.timeControlStatus == .playing {
                    self.didFire = true
                    DispatchQueue.main.async { onReady() }
                }
            }
        }
    }
}

// MARK: - ActivityViewControllerPhoto

private struct ActivityViewControllerPhoto: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
