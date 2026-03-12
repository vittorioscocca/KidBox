//
//  PhotoAlbumDetailView.swift
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
    
    // Stesse foto del ViewModel globale — filtrate per album
    @Query private var allPhotos: [KBFamilyPhoto]
    
    @State private var fullscreenPhoto: KBFamilyPhoto?
    @State private var isSelectMode = false
    @State private var selectedIds: Set<String> = []
    @State private var dragSelectIsAdding = true
    @State private var showRemoveConfirm = false
    
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
        .confirmationDialog(
            "Rimuovi \(selectedIds.count) foto dall'album?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Rimuovi dall'album", role: .destructive) { removeSelectedFromAlbum() }
            Button("Annulla", role: .cancel) {}
        }
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
        ToolbarItem(placement: .navigationBarTrailing) {
            if isSelectMode {
                Button(selectedIds.count == photos.count ? "Deseleziona tutto" : "Seleziona tutto") {
                    withAnimation(.snappy) {
                        selectedIds = selectedIds.count == photos.count ? [] : Set(photos.map(\.id))
                    }
                }
                .font(.subheadline)
            } else {
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
            
            // Drag-select overlay
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
            // Rimuovi dall'album
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
            
            // Elimina definitivamente dalla libreria
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
            Text("Aggiungi foto a questo album dalla libreria.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
    }
    
    // MARK: - Actions
    
    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }
    
    /// Rimuove le foto selezionate dall'album (non le cancella dalla libreria)
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
    
    /// Cancella definitivamente dalla libreria (soft delete)
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
}

// MARK: - stableGridId (shared extension — già definito in FamilyPhotosView.swift)
// Non ridichiarare qui: è private extension in FamilyPhotosView.swift.
// Se necessario renderlo internal togliendo `private` in FamilyPhotosView.swift.
