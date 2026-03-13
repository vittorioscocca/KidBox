//
//  PhotoAlbumDetailView.swift  ← VERSIONE AGGIORNATA CON FOTOCAMERA
//  KidBox
//
//  Mostra le foto di un singolo album.
//  Riusa PhotoThumbnailCell e PhotoFullscreenView definiti in FamilyPhotosView.swift.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct PhotoAlbumDetailView: View {
    let familyId: String
    let albumId: String
    let albumTitle: String
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    
    @Query private var allPhotos: [KBFamilyPhoto]
    
    @State private var fullscreenPhoto: KBFamilyPhoto?
    @State private var isSelectMode = false
    @State private var selectedIds: Set<String> = []
    @State private var dragSelectIsAdding = true
    @State private var showRemoveConfirm = false
    
    // ── Camera ──────────────────────────────────────────────────────────────
    @State private var showCamera = false
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var uploadError: String?
    // ────────────────────────────────────────────────────────────────────────
    
    private var uid: String { Auth.auth().currentUser?.uid ?? "" }
    
    private var photos: [KBFamilyPhoto] {
        allPhotos
            .filter { !$0.isDeleted && $0.albumIds.contains(albumId) }
            .sorted { $0.takenAt > $1.takenAt }
    }
    
    private var bg: Color {
        colorScheme == .dark
        ? Color(red: 0.10, green: 0.10, blue: 0.10)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    init(familyId: String, albumId: String, albumTitle: String) {
        self.familyId   = familyId
        self.albumId    = albumId
        self.albumTitle = albumTitle
        _allPhotos = Query(
            filter: #Predicate<KBFamilyPhoto> { $0.familyId == familyId && $0.isDeleted == false },
            sort: \KBFamilyPhoto.takenAt, order: .reverse
        )
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            bg.ignoresSafeArea()
            
            if photos.isEmpty {
                emptyState
            } else {
                ScrollView {
                    photoGrid(photos)
                        .padding(.bottom, 24)
                }
            }
            
            // Banner upload (stesso stile di FamilyPhotosView)
            if isUploading {
                uploadBanner
            }
            
            if isSelectMode { selectionToolbar }
        }
        .navigationTitle(isSelectMode
                         ? (selectedIds.isEmpty ? "Seleziona"
                            : "\(selectedIds.count) selezionat\(selectedIds.count == 1 ? "o" : "i")")
                         : albumTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarItems }
        .animation(.snappy(duration: 0.22), value: isSelectMode)
        .fullScreenCover(item: $fullscreenPhoto) { photo in
            PhotoFullscreenView(
                startPhoto: photo, allPhotos: photos,
                familyId: familyId, userId: uid,
                onDismiss: { fullscreenPhoto = nil }
            )
        }
        // ── Fotocamera ───────────────────────────────────────────────────────
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { result in
                showCamera = false
                switch result {
                case .photo(let data):
                    Task { await uploadCapturedPhoto(data: data) }
                case .video(let url):
                    Task { await uploadCapturedVideo(url: url) }
                case .cancelled:
                    break
                }
            }
            .ignoresSafeArea()
        }
        // ── Alert errore upload ──────────────────────────────────────────────
        .alert("Errore caricamento", isPresented: Binding(
            get: { uploadError != nil },
            set: { if !$0 { uploadError = nil } }
        )) { Button("OK") { uploadError = nil } } message: { Text(uploadError ?? "") }
        // ────────────────────────────────────────────────────────────────────
            .confirmationDialog(
                "Rimuovi \(selectedIds.count) foto dall'album?",
                isPresented: $showRemoveConfirm,
                titleVisibility: .visible
            ) {
                Button("Rimuovi dall'album", role: .destructive) { removeSelectedFromAlbum() }
                Button("Annulla", role: .cancel) {}
            }
    }
    
    // MARK: - Upload banner (clone di FamilyPhotosView)
    
    private var uploadBanner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Caricamento…").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Text("\(Int(uploadProgress * 100))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
            }
            ProgressView(value: uploadProgress).tint(.white)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .background(Color.pink.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20).padding(.bottom, isSelectMode ? 90 : 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring, value: isUploading)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if isSelectMode {
                Button("Annulla") {
                    withAnimation(.snappy) { isSelectMode = false; selectedIds = [] }
                }
            }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if isSelectMode {
                Button(selectedIds.count == photos.count ? "Deseleziona tutto" : "Seleziona tutto") {
                    withAnimation(.snappy) {
                        selectedIds = selectedIds.count == photos.count ? [] : Set(photos.map(\.id))
                    }
                }
                .font(.subheadline)
            } else {
                // ── Fotocamera ──────────────────────────────────────────────
                if CameraCaptureView.isAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Image(systemName: "camera")
                    }
                }
                // ───────────────────────────────────────────────────────────
                Button {
                    withAnimation(.snappy) { isSelectMode = true; selectedIds = [] }
                } label: {
                    Text("Seleziona").font(.subheadline)
                }
            }
        }
    }
    
    // MARK: - Grid
    
    private func photoGrid(_ items: [KBFamilyPhoto]) -> some View {
        let spacing: CGFloat = 2
        let cols = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)
        let screenWidth = UIScreen.main.bounds.width
        let cellSize = floor((screenWidth - spacing * 2) / 3)
        let rows = Int(ceil(Double(items.count) / 3.0))
        let gridHeight = CGFloat(rows) * cellSize + CGFloat(max(rows - 1, 0)) * spacing
        
        return ZStack(alignment: .topLeading) {
            LazyVGrid(columns: cols, spacing: spacing) {
                ForEach(items, id: \.stableGridId) { photo in
                    let isSelected = selectedIds.contains(photo.id)
                    PhotoThumbnailCell(
                        photo: photo,
                        familyId: familyId,
                        userId: uid,
                        videoDurationSeconds: photo.videoDurationSeconds,
                        isVideo: photo.isVideo
                    )
                    .frame(width: cellSize, height: cellSize)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if photo.isVideo, let secs = photo.videoDurationSeconds {
                            Text(PhotoThumbnailCell.formatDuration(secs))
                                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                                .padding(4)
                        }
                    }
                    .overlay {
                        if isSelectMode {
                            Color.black.opacity(isSelected ? 0 : 0.28)
                                .animation(.easeInOut(duration: 0.12), value: isSelected)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isSelectMode {
                            ZStack {
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 1.5)
                                    .background(Circle().fill(isSelected ? Color.blue : Color.black.opacity(0.25)))
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 24, height: 24)
                            .padding(5)
                            .animation(.spring(duration: 0.2), value: isSelected)
                        }
                    }
                    .onTapGesture {
                        if isSelectMode { withAnimation(.snappy) { toggleSelection(photo.id) } }
                        else { fullscreenPhoto = photo }
                    }
                }
            }
            .frame(height: gridHeight)
            
            if isSelectMode {
                Color.clear
                    .frame(height: gridHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .local)
                            .onChanged { value in
                                let col = Int(value.location.x / (cellSize + spacing)).clamped(to: 0...2)
                                let row = Int(value.location.y / (cellSize + spacing))
                                let index = row * 3 + col
                                guard index >= 0, index < items.count else { return }
                                let photoId = items[index].id
                                if value.translation.width.magnitude < 6 && value.translation.height.magnitude < 6 {
                                    dragSelectIsAdding = !selectedIds.contains(photoId)
                                }
                                withAnimation(.snappy(duration: 0.1)) {
                                    if dragSelectIsAdding { selectedIds.insert(photoId) }
                                    else { selectedIds.remove(photoId) }
                                }
                            }
                            .simultaneously(with:
                                                SpatialTapGesture().onEnded { value in
                                                    let col = Int(value.location.x / (cellSize + spacing)).clamped(to: 0...2)
                                                    let row = Int(value.location.y / (cellSize + spacing))
                                                    let index = row * 3 + col
                                                    guard index >= 0, index < items.count else { return }
                                                    withAnimation(.snappy) { toggleSelection(items[index].id) }
                                                }
                                           )
                    )
            }
        }
    }
    
    // MARK: - Selection toolbar
    
    private var selectionToolbar: some View {
        HStack(spacing: 0) {
            Button {
                if !selectedIds.isEmpty { showRemoveConfirm = true }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "rectangle.stack.badge.minus")
                        .font(.system(size: 22))
                    Text("Rimuovi").font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(selectedIds.isEmpty ? .secondary : Color.orange)
            }
            .disabled(selectedIds.isEmpty)
            
            Button(role: .destructive) {
                let toDelete = photos.filter { selectedIds.contains($0.id) }
                withAnimation(.snappy) {
                    toDelete.forEach { softDeletePhoto($0) }
                    isSelectMode = false; selectedIds = []
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 22))
                    Text("Elimina").font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(selectedIds.isEmpty ? .secondary : Color.red)
            }
            .disabled(selectedIds.isEmpty)
        }
        .padding(.top, 10).padding(.bottom, 28)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Empty state
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 64)).foregroundStyle(.quaternary)
            Text("Album vuoto").font(.title3.weight(.semibold))
            Text("Aggiungi foto a questo album dalla libreria o scatta direttamente con la fotocamera.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            
            // ── Bottone fotocamera nello stato vuoto ─────────────────────────
            if CameraCaptureView.isAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label("Scatta una foto", systemImage: "camera.fill")
                        .font(.subheadline.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Color.pink, in: Capsule())
                }
            }
            // ─────────────────────────────────────────────────────────────────
            Spacer()
        }
        .padding(32)
    }
    
    // MARK: - Actions
    
    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }
    
    private func removeSelectedFromAlbum() {
        let toUpdate = photos.filter { selectedIds.contains($0.id) }
        for photo in toUpdate {
            photo.albumIds = photo.albumIds.filter { $0 != albumId }
            photo.updatedAt = Date()
        }
        try? modelContext.save()
        for photo in toUpdate {
            SyncCenter.shared.enqueuePhotoUpsert(photoId: photo.id, familyId: familyId, modelContext: modelContext)
        }
        Task { await SyncCenter.shared.flush(modelContext: modelContext, remote: TodoRemoteStore()) }
        withAnimation(.snappy) { isSelectMode = false; selectedIds = [] }
    }
    
    private func softDeletePhoto(_ photo: KBFamilyPhoto) {
        photo.isDeleted = true; photo.updatedAt = Date()
        try? modelContext.save()
        let photoId = photo.id; let fid = familyId
        Task {
            do {
                try await SyncCenter.photoRemote.softDeletePhoto(familyId: fid, photoId: photoId)
            } catch {
                KBLog.sync.kbError("AlbumDetail softDelete FAILED photoId=\(photoId) err=\(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Camera upload
    
    /// Foto scattata dalla fotocamera → inserisce nell'album corrente + libreria.
    private func uploadCapturedPhoto(data: Data) async {
        guard !uid.isEmpty else { return }
        let photoId     = UUID().uuidString
        let now         = Date()
        let fileName    = "photo_\(photoId).jpg"
        let thumbB64    = PhotoRemoteStore.makeThumbnail(from: data)?.base64EncodedString()
        let storagePath = "families/\(familyId)/photos/\(photoId)/original.enc"
        
        await MainActor.run { withAnimation { isUploading = true; uploadProgress = 0 } }
        
        let photo = KBFamilyPhoto(
            id: photoId, familyId: familyId,
            fileName: fileName,
            mimeType: "image/jpeg", fileSize: Int64(data.count),
            storagePath: storagePath,
            thumbnailBase64: thumbB64,
            takenAt: now, createdAt: now, updatedAt: now,
            createdBy: uid, updatedBy: uid
        )
        photo.syncState  = .synced
        photo.albumIdsRaw = albumId   // ← assegnato all'album corrente
        
        // Cache locale immagine (stessa logica di FamilyPhotosView)
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KBPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let localURL = cacheDir.appendingPathComponent("\(photoId).jpg")
        try? data.write(to: localURL, options: .atomic)
        
        await MainActor.run {
            modelContext.insert(photo)
            try? modelContext.save()
        }
        
        do {
            let dto = try await SyncCenter.photoRemote.upload(
                photoId: photoId, familyId: familyId, userId: uid,
                imageData: data, fileName: fileName,
                mimeType: "image/jpeg", takenAt: now,
                caption: nil, albumIds: [albumId],
                precomputedThumbnailB64: thumbB64,
                precomputedVideoDurationSeconds: nil,
                onProgress: { p in Task { @MainActor in uploadProgress = p } }
            )
            await MainActor.run {
                photo.downloadURL = dto.downloadURL
                photo.syncState = .synced
                try? modelContext.save()
            }
            KBLog.sync.kbInfo("AlbumDetail uploadCapturedPhoto: OK photoId=\(photoId) albumId=\(albumId)")
        } catch {
            await MainActor.run {
                photo.syncState = .pendingUpsert
                photo.lastSyncError = error.localizedDescription
                try? modelContext.save()
                uploadError = error.localizedDescription
            }
            KBLog.sync.kbError("AlbumDetail uploadCapturedPhoto: FAILED photoId=\(photoId) err=\(error.localizedDescription)")
        }
        
        await MainActor.run { withAnimation { isUploading = false; uploadProgress = 0 } }
    }
    
    /// Video registrato dalla fotocamera → comprimi + inserisce nell'album corrente + libreria.
    private func uploadCapturedVideo(url: URL) async {
        guard !uid.isEmpty else { return }
        await MainActor.run { withAnimation { isUploading = true; uploadProgress = 0 } }
        defer { try? FileManager.default.removeItem(at: url) }
        
        let videoURL = await VideoCompressor.compress(url: url) ?? url
        guard let data = try? Data(contentsOf: videoURL) else {
            await MainActor.run { withAnimation { isUploading = false }; uploadError = "Impossibile leggere il video." }
            return
        }
        
        let photoId     = UUID().uuidString
        let now         = Date()
        let fileName    = "video_\(photoId).mp4"
        let thumbData   = await PhotoRemoteStore.makeVideoThumbnail(url: videoURL)
        let thumbB64    = thumbData?.base64EncodedString()
        let durSecs     = await VideoCompressor.videoDuration(url: videoURL)
        let storagePath = "families/\(familyId)/photos/\(photoId)/original.enc"
        
        if videoURL != url { try? FileManager.default.removeItem(at: videoURL) }
        
        let photo = KBFamilyPhoto(
            id: photoId, familyId: familyId,
            fileName: fileName,
            mimeType: "video/mp4", fileSize: Int64(data.count),
            storagePath: storagePath,
            thumbnailBase64: thumbB64,
            takenAt: now, createdAt: now, updatedAt: now,
            createdBy: uid, updatedBy: uid
        )
        photo.syncState           = .synced
        photo.videoDurationSeconds = durSecs
        photo.albumIdsRaw          = albumId   // ← assegnato all'album corrente
        
        await MainActor.run {
            modelContext.insert(photo)
            try? modelContext.save()
        }
        
        do {
            let dto = try await SyncCenter.photoRemote.upload(
                photoId: photoId, familyId: familyId, userId: uid,
                imageData: data, fileName: fileName,
                mimeType: "video/mp4", takenAt: now,
                caption: nil, albumIds: [albumId],
                precomputedThumbnailB64: thumbB64,
                precomputedVideoDurationSeconds: durSecs,
                onProgress: { p in Task { @MainActor in uploadProgress = p } }
            )
            await MainActor.run {
                photo.downloadURL = dto.downloadURL
                photo.syncState = .synced
                try? modelContext.save()
            }
            KBLog.sync.kbInfo("AlbumDetail uploadCapturedVideo: OK photoId=\(photoId) albumId=\(albumId)")
        } catch {
            await MainActor.run {
                photo.syncState = .pendingUpsert
                photo.lastSyncError = error.localizedDescription
                try? modelContext.save()
                uploadError = error.localizedDescription
            }
            KBLog.sync.kbError("AlbumDetail uploadCapturedVideo: FAILED photoId=\(photoId) err=\(error.localizedDescription)")
        }
        
        await MainActor.run { withAnimation { isUploading = false; uploadProgress = 0 } }
    }
}
