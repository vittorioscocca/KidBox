//
//  FamilyPhotosView.swift
//  KidBox
//
//  Apple Photos-style shared family gallery.
//  Encryption: DocumentCryptoService (family master key via FamilyKeychainStore + iCloud Keychain).
//  Any family member with the synced key can view any photo.
//

import SwiftUI
import SwiftData
import PhotosUI
import FirebaseAuth
import AVFoundation
import AVKit
import UniformTypeIdentifiers
import Combine

// MARK: - VideoTransferable
// Wrapper per caricare video dal PhotosPicker come URL temporaneo.
struct VideoTransferable: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoTransferable(url: dest)
        }
    }
}

// MARK: - VideoCompressor
enum VideoCompressor {
    static func compress(url: URL) async -> URL? {
        let asset = AVURLAsset(url: url)
        let compatiblePresets = await AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset: String
        if compatiblePresets.contains(AVAssetExportPresetMediumQuality) {
            preset = AVAssetExportPresetMediumQuality
        } else if compatiblePresets.contains(AVAssetExportPresetLowQuality) {
            preset = AVAssetExportPresetLowQuality
        } else {
            KBLog.sync.kbError("VideoCompressor: no compatible export preset for \(url.lastPathComponent)")
            return nil
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        KBLog.sync.kbDebug("VideoCompressor: export start preset=\(preset) output=\(output.lastPathComponent)")
        do {
            let session = AVAssetExportSession(asset: asset, presetName: preset)
            try await session?.export(to: output, as: .mp4)
            let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            KBLog.sync.kbInfo("VideoCompressor: export OK bytes=\(size) preset=\(preset)")
            return output
        } catch {
            KBLog.sync.kbError("VideoCompressor: export FAILED err=\(error.localizedDescription)")
            try? FileManager.default.removeItem(at: output)
            return nil
        }
    }
    
    static func remux(from source: URL, to destination: URL) async -> URL? {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        do {
            let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
            try await session?.export(to: destination, as: .mp4)
            KBLog.sync.kbDebug("VideoCompressor.remux: OK \(source.lastPathComponent) → \(destination.lastPathComponent)")
            return destination
        } catch {
            KBLog.sync.kbError("VideoCompressor.remux: FAILED err=\(error.localizedDescription)")
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
    }
    
    static func videoDuration(url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let secs = CMTimeGetSeconds(duration)
        return secs.isFinite && secs > 0 ? secs : nil
    }
}

// MARK: - Root view

struct FamilyPhotosView: View {
    let familyId: String
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    
    @StateObject private var vm: FamilyPhotosViewModel
    
    init(familyId: String) {
        self.familyId = familyId
        _vm = StateObject(wrappedValue: FamilyPhotosViewModel(familyId: familyId))
    }
    
    @State private var tab: PhotoTab = .library
    @State private var grouping: PhotoGrouping = .day
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var uploadError: String?
    @State private var fullscreenPhoto: KBFamilyPhoto?
    @State private var showCreateAlbum = false
    @State private var newAlbumTitle = ""
    @State private var isSelectMode = false
    @State private var selectedIds: Set<String> = []
    @State private var dragSelectIsAdding = true
    @State private var isPreparingShare = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var isSendingToChat = false
    @State private var sendToChatError: String?
    @State private var showAddToAlbum = false
    @State private var showCreateAlbumFromSelection = false
    @State private var uploadTargetAlbumId: String? = nil
    @State private var isAlbumSelectMode = false
    @State private var selectedAlbumIds: Set<String> = []
    @State private var gridWidth: CGFloat = UIScreen.main.bounds.width
    @State private var showCamera = false
    
    private var photos: [KBFamilyPhoto] { vm.photos }
    private var albums: [KBPhotoAlbum]  { vm.albums }
    private var uid: String { Auth.auth().currentUser?.uid ?? "" }
    
    private var bg: Color {
        colorScheme == .dark
        ? Color(red: 0.10, green: 0.10, blue: 0.10)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(PhotoTab.allCases) { t in Text(t.label).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.vertical, 8)
                Divider()
                switch tab {
                case .library: libraryContent
                case .albums:  albumsContent
                }
            }
            if isUploading { uploadBanner }
            if isSelectMode { selectionToolbar }
            if isAlbumSelectMode { albumSelectionToolbar }
        }
        .navigationTitle({
            if isSelectMode {
                return selectedIds.isEmpty ? "Seleziona" : "\(selectedIds.count) selezionat\(selectedIds.count == 1 ? "o" : "i")"
            } else if isAlbumSelectMode {
                return selectedAlbumIds.isEmpty ? "Seleziona" : "\(selectedAlbumIds.count) album selezionat\(selectedAlbumIds.count == 1 ? "o" : "i")"
            } else {
                return "Foto e video"
            }
        }())
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarItems }
        .animation(.snappy(duration: 0.22), value: isSelectMode)
        .photosPicker(
            isPresented: .constant(false),
            selection: $pickerItems,
            maxSelectionCount: 30,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: tab) { _, _ in
            withAnimation(.snappy) {
                isSelectMode = false; selectedIds = []
                isAlbumSelectMode = false; selectedAlbumIds = []
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            let captured = items; pickerItems = []
            Task { await uploadItems(captured) }
        }
        .fullScreenCover(item: $fullscreenPhoto) { photo in
            PhotoFullscreenView(
                startPhoto: photo, allPhotos: photos, familyId: familyId, userId: uid,
                onDismiss: { fullscreenPhoto = nil }
            )
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { result in
                showCamera = false
                switch result {
                case .photo(let data):
                    Task { await uploadCapturedPhoto(data: data, targetAlbumId: uploadTargetAlbumId) }
                case .video(let url):
                    Task { await uploadCapturedVideo(url: url, targetAlbumId: uploadTargetAlbumId) }
                case .cancelled:
                    break
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCreateAlbum) { createAlbumSheet }
        .sheet(isPresented: $showAddToAlbum) { addToAlbumSheet }
        .sheet(isPresented: $showCreateAlbumFromSelection) { createAlbumFromSelectionSheet }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: shareItems)
        }
        .alert("Errore caricamento", isPresented: Binding(
            get: { uploadError != nil },
            set: { if !$0 { uploadError = nil } }
        )) { Button("OK") { uploadError = nil } } message: { Text(uploadError ?? "") }
            .alert("Errore invio in chat", isPresented: Binding(
                get: { sendToChatError != nil },
                set: { if !$0 { sendToChatError = nil } }
            )) { Button("OK") { sendToChatError = nil } } message: { Text(sendToChatError ?? "") }
            .task {
                vm.bind(modelContext: modelContext)
                SyncCenter.shared.startPhotosRealtime(familyId: familyId, modelContext: modelContext)
            }
            .onDisappear {
                SyncCenter.shared.stopPhotosRealtime()
                vm.cleanup()
            }
            .onReceive(coordinator.$pendingShareEncryptedMediaPath.compactMap { $0 }) { path in
                coordinator.pendingShareEncryptedMediaPath = nil
                let type = coordinator.pendingShareEncryptedMediaType ?? "image"
                coordinator.pendingShareEncryptedMediaType = nil
                Task { await uploadFromAppGroup(path: path, fileType: type) }
            }
            .onAppear {
                if let path = coordinator.pendingShareEncryptedMediaPath, !path.isEmpty {
                    coordinator.pendingShareEncryptedMediaPath = nil
                    let type = coordinator.pendingShareEncryptedMediaType ?? "image"
                    coordinator.pendingShareEncryptedMediaType = nil
                    Task { await uploadFromAppGroup(path: path, fileType: type) }
                }
            }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if isSelectMode || isAlbumSelectMode {
                Button("Annulla") {
                    withAnimation(.snappy) {
                        isSelectMode = false; selectedIds = []
                        isAlbumSelectMode = false; selectedAlbumIds = []
                    }
                }
            }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if isSelectMode {
                Button(selectedIds.count == photos.count ? "Deseleziona tutto" : "Seleziona tutto") {
                    withAnimation(.snappy) {
                        if selectedIds.count == photos.count { selectedIds = [] }
                        else { selectedIds = Set(photos.map(\.id)) }
                    }
                }
                .font(.subheadline)
            } else if isAlbumSelectMode {
                Button(selectedAlbumIds.count == albums.count ? "Deseleziona tutto" : "Seleziona tutto") {
                    withAnimation(.snappy) {
                        if selectedAlbumIds.count == albums.count { selectedAlbumIds = [] }
                        else { selectedAlbumIds = Set(albums.map(\.id)) }
                    }
                }
                .font(.subheadline)
            } else {
                if tab == .library {
                    Button {
                        withAnimation(.snappy) { isSelectMode = true; selectedIds = [] }
                    } label: {
                        Text("Seleziona").font(.subheadline)
                    }
                    Menu {
                        ForEach(PhotoGrouping.allCases) { g in
                            Button {
                                withAnimation(.snappy) { grouping = g }
                            } label: {
                                Label(g.label, systemImage: grouping == g ? "checkmark" : "")
                            }
                        }
                    } label: { Image(systemName: "slider.horizontal.3") }
                } else {
                    if !albums.isEmpty {
                        Button {
                            withAnimation(.snappy) { isAlbumSelectMode = true; selectedAlbumIds = [] }
                        } label: {
                            Text("Seleziona").font(.subheadline)
                        }
                    }
                }
                if tab == .library {
                    if CameraCaptureView.isAvailable {
                        Button {
                            uploadTargetAlbumId = nil
                            showCamera = true
                        } label: {
                            Image(systemName: "camera")
                        }
                    }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 30, matching: .any(of: [.images, .videos])) {
                        Image(systemName: "plus")
                    }
                    .simultaneousGesture(TapGesture().onEnded { uploadTargetAlbumId = nil })
                } else {
                    Button { showCreateAlbum = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
    
    // MARK: - Library
    
    @ViewBuilder
    private var libraryContent: some View {
        if photos.isEmpty {
            emptyLibrary
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedPhotos, id: \.key) { group in
                        Section {
                            photoGrid(group.photos).padding(.bottom, 4)
                        } header: {
                            Text(group.label)
                                .font(.system(size: 15, weight: .semibold))
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.ultraThinMaterial)
                        }
                    }
                }
                .padding(.bottom, 24)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: GridWidthKey.self, value: geo.size.width)
                    }
                )
                .onPreferenceChange(GridWidthKey.self) { w in
                    if w > 0 && w != gridWidth { gridWidth = w }
                }
            }
            .id(fullscreenPhoto == nil ? "grid-active" : "grid-covered")
        }
    }
    
    private func photoGrid(_ items: [KBFamilyPhoto]) -> some View {
        let spacing: CGFloat = 2
        let cellSize = floor((gridWidth - spacing * 2) / 3)
        let cols = Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: 3)
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
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
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
                        if isSelectMode {
                            withAnimation(.snappy) { toggleSelection(photo.id) }
                        } else {
                            fullscreenPhoto = photo
                        }
                    }
                    .contextMenu {
                        if !isSelectMode {
                            Button {
                                Task { await sendToChat(photo) }
                            } label: {
                                Label("Invia in chat", systemImage: "bubble.left.and.bubble.right")
                            }
                            Divider()
                            Button(role: .destructive) { softDeletePhoto(photo) } label: {
                                Label("Elimina", systemImage: "trash")
                            }
                        }
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
                                                SpatialTapGesture()
                                .onEnded { value in
                                    let col = Int(value.location.x / (cellSize + spacing)).clamped(to: 0...2)
                                    let row = Int(value.location.y / (cellSize + spacing))
                                    let index = row * 3 + col
                                    guard index >= 0, index < items.count else { return }
                                    let photoId = items[index].id
                                    withAnimation(.snappy) { toggleSelection(photoId) }
                                }
                                           )
                    )
            }
        }
    }
    
    // MARK: - Albums
    
    @ViewBuilder
    private var albumsContent: some View {
        let hPad: CGFloat = 16
        let spacing: CGFloat = 14
        let cellW = floor((UIScreen.main.bounds.width - hPad * 2 - spacing) / 2)
        
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.fixed(cellW), spacing: spacing),
                          GridItem(.fixed(cellW), spacing: spacing)],
                spacing: spacing
            ) {
                Button { showCreateAlbum = true } label: {
                    AlbumCreateCard(cellWidth: cellW)
                }
                .buttonStyle(.plain)
                .opacity(isAlbumSelectMode ? 0 : 1)
                .allowsHitTesting(!isAlbumSelectMode)
                
                ForEach(albums) { album in
                    let albumPhotos = photos.filter { $0.albumIds.contains(album.id) }
                    let isSelected = selectedAlbumIds.contains(album.id)
                    
                    AlbumCard(album: album,
                              previewPhotos: Array(albumPhotos.prefix(1)),
                              photoCount: albumPhotos.count,
                              cellWidth: cellW)
                    .overlay {
                        if isAlbumSelectMode {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(isSelected ? 0 : 0.28))
                                .animation(.easeInOut(duration: 0.12), value: isSelected)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isAlbumSelectMode {
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
                            .padding(8)
                            .animation(.spring(duration: 0.2), value: isSelected)
                        }
                    }
                    .onTapGesture {
                        if isAlbumSelectMode {
                            withAnimation(.snappy) {
                                if isSelected { selectedAlbumIds.remove(album.id) }
                                else { selectedAlbumIds.insert(album.id) }
                            }
                        } else {
                            coordinator.navigate(to: .photoAlbumDetail(
                                familyId: familyId,
                                albumId: album.id,
                                albumTitle: album.title
                            ))
                        }
                    }
                    .contextMenu {
                        if !isAlbumSelectMode {
                            Button(role: .destructive) { softDeleteAlbum(album) } label: {
                                Label("Elimina album", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, hPad)
            .padding(.vertical, 16)
        }
    }
    
    // MARK: - Empty state
    
    private var emptyLibrary: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 64)).foregroundStyle(.quaternary)
            Text("Nessuna foto").font(.title3.weight(.semibold))
            Text("Aggiungi le prime foto condivise della famiglia.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 30, matching: .any(of: [.images, .videos])) {
                Label("Aggiungi foto e video", systemImage: "plus.circle.fill")
                    .font(.subheadline.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.pink, in: Capsule())
            }
            if CameraCaptureView.isAvailable {
                Button {
                    uploadTargetAlbumId = nil
                    showCamera = true
                } label: {
                    Label("Scatta una foto", systemImage: "camera.fill")
                        .font(.subheadline.bold()).foregroundStyle(.pink)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(Color.pink.opacity(0.12), in: Capsule())
                }
            }
            Spacer()
        }
        .padding(32)
    }
    
    // MARK: - Upload banner
    
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
        .padding(.horizontal, 20).padding(.bottom, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring, value: isUploading)
    }
    
    // MARK: - Selection toolbar
    
    private var selectionToolbar: some View {
        HStack(spacing: 0) {
            Button {
                Task { await shareSelected() }
            } label: {
                VStack(spacing: 4) {
                    if isPreparingShare {
                        ProgressView().frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 22))
                    }
                    Text("Condividi").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedIds.isEmpty || isPreparingShare)
            
            Button { showAddToAlbum = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 22))
                    Text("Album").font(.caption2)
                }
                .frame(maxWidth: .infinity)
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
                    Image(systemName: "trash").font(.system(size: 22))
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
    
    // MARK: - Album selection toolbar
    
    private var albumSelectionToolbar: some View {
        HStack(spacing: 0) {
            Button(role: .destructive) {
                let toDelete = albums.filter { selectedAlbumIds.contains($0.id) }
                withAnimation(.snappy) {
                    toDelete.forEach { softDeleteAlbum($0) }
                    isAlbumSelectMode = false; selectedAlbumIds = []
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash").font(.system(size: 22))
                    Text("Elimina").font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(selectedAlbumIds.isEmpty ? .secondary : Color.red)
            }
            .disabled(selectedAlbumIds.isEmpty)
        }
        .padding(.top, 10).padding(.bottom, 28)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) { selectedIds.remove(id) }
        else { selectedIds.insert(id) }
    }
    
    // MARK: - Sheets
    
    private var createAlbumSheet: some View {
        NavigationStack {
            Form {
                Section("Nome album") {
                    TextField("Es. Vacanza estate 2025", text: $newAlbumTitle)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Nuovo album").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { showCreateAlbum = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") { createAlbum(); showCreateAlbum = false }
                        .disabled(newAlbumTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private var addToAlbumSheet: some View {
        NavigationStack {
            List {
                Button {
                    showAddToAlbum = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showCreateAlbumFromSelection = true
                    }
                } label: {
                    Label("Nuovo album…", systemImage: "plus.rectangle.on.folder")
                        .foregroundStyle(.primary)
                }
                if !vm.albums.isEmpty {
                    Section("Album esistenti") {
                        ForEach(vm.albums) { album in
                            Button {
                                showAddToAlbum = false
                                addSelectedPhotos(toAlbum: album.id)
                            } label: {
                                let count = photos.filter { $0.albumIds.contains(album.id) }.count
                                HStack {
                                    Label(album.title, systemImage: "rectangle.stack")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(count)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Aggiungi ad album").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { showAddToAlbum = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private var createAlbumFromSelectionSheet: some View {
        NavigationStack {
            Form {
                Section("Nome album") {
                    TextField("Es. Vacanza estate 2025", text: $newAlbumTitle)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("Verranno aggiunte \(selectedIds.count) foto/video al nuovo album.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nuovo album").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { showCreateAlbumFromSelection = false; newAlbumTitle = "" }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") {
                        let t = newAlbumTitle; newAlbumTitle = ""
                        showCreateAlbumFromSelection = false
                        createAlbumAndAddSelected(title: t)
                    }
                    .disabled(newAlbumTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Grouped photos
    
    private var groupedPhotos: [PhotoGroup] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "it_IT")
        
        func group(keyFor: (KBFamilyPhoto) -> Date, labelFor: (Date) -> String) -> [PhotoGroup] {
            var dict: [Date: [KBFamilyPhoto]] = [:]
            photos.forEach { dict[keyFor($0), default: []].append($0) }
            return dict.keys.sorted(by: >).map { date in
                PhotoGroup(key: date, label: labelFor(date),
                           photos: dict[date]!.sorted { $0.takenAt > $1.takenAt })
            }
        }
        
        switch grouping {
        case .day:
            fmt.dateFormat = "EEEE d MMMM yyyy"
            return group(keyFor: { cal.startOfDay(for: $0.takenAt) }) { fmt.string(from: $0).capitalized }
        case .month:
            fmt.dateFormat = "MMMM yyyy"
            return group(keyFor: {
                let c = cal.dateComponents([.year, .month], from: $0.takenAt)
                return cal.date(from: c) ?? $0.takenAt
            }) { fmt.string(from: $0).capitalized }
        case .year:
            return group(keyFor: {
                let c = cal.dateComponents([.year], from: $0.takenAt)
                return cal.date(from: c) ?? $0.takenAt
            }) { String(cal.component(.year, from: $0)) }
        }
    }
    
    // MARK: - Upload
    
    private func uploadItems(_ items: [PhotosPickerItem]) async {
        guard !uid.isEmpty else { return }
        let total = Double(items.count); var done = 0.0
        await MainActor.run { withAnimation { isUploading = true; uploadProgress = 0 } }
        
        for item in items {
            let isVideo = item.supportedContentTypes.contains(where: {
                $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.identifier == "public.mpeg-4"
            })
            let mediaData: Data?
            let mimeType: String
            let fileExt: String
            var thumbB64FromURL: String? = nil
            var videoDurationSecs: Double? = nil
            
            if isVideo {
                guard let rawURL = try? await item.loadTransferable(type: VideoTransferable.self)?.url else {
                    KBLog.sync.kbError("uploadItems: VideoTransferable load failed")
                    done += 1; continue
                }
                KBLog.sync.kbInfo("uploadItems: compressing video rawURL=\(rawURL.lastPathComponent)")
                let videoURL = await VideoCompressor.compress(url: rawURL) ?? rawURL
                KBLog.sync.kbInfo("uploadItems: videoURL ready=\(videoURL.lastPathComponent)")
                mediaData = try? Data(contentsOf: videoURL)
                let thumbData  = await PhotoRemoteStore.makeVideoThumbnail(url: videoURL)
                let durSeconds = await VideoCompressor.videoDuration(url: videoURL)
                thumbB64FromURL   = thumbData?.base64EncodedString()
                videoDurationSecs = durSeconds
                KBLog.sync.kbDebug("uploadItems: video thumb=\(thumbB64FromURL != nil) duration=\(durSeconds ?? -1)s")
                if videoURL != rawURL { try? FileManager.default.removeItem(at: videoURL) }
                try? FileManager.default.removeItem(at: rawURL)
                mimeType = "video/mp4"; fileExt = "mp4"
            } else {
                mediaData = try? await item.loadTransferable(type: Data.self)
                mimeType = "image/jpeg"; fileExt = "jpg"
            }
            
            guard let data = mediaData else {
                KBLog.sync.kbError("uploadItems: mediaData nil isVideo=\(isVideo)")
                done += 1; continue
            }
            
            let photoId  = UUID().uuidString
            let now      = Date()
            let fileName = "\(isVideo ? "video" : "photo")_\(photoId).\(fileExt)"
            
            let thumbB64: String?
            if isVideo {
                if let t = thumbB64FromURL {
                    thumbB64 = t
                } else {
                    KBLog.sync.kbError("uploadItems: video thumb from URL nil, retry from Data photoId=\(photoId)")
                    thumbB64 = await PhotoRemoteStore.makeVideoThumbnail(from: data)?.base64EncodedString()
                }
            } else {
                thumbB64 = PhotoRemoteStore.makeThumbnail(from: data)?.base64EncodedString()
            }
            
            let storagePath = "families/\(familyId)/photos/\(photoId)/original.enc"
            let photo = KBFamilyPhoto(
                id: photoId, familyId: familyId, fileName: fileName,
                mimeType: mimeType, fileSize: Int64(data.count),
                storagePath: storagePath, thumbnailBase64: thumbB64,
                takenAt: now, createdAt: now, updatedAt: now,
                createdBy: uid, updatedBy: uid
            )
            photo.syncState = .synced
            photo.videoDurationSeconds = isVideo ? videoDurationSecs : nil
            if let albumId = uploadTargetAlbumId { photo.albumIdsRaw = albumId }
            if !isVideo { cacheLocally(data: data, photoId: photoId, photo: photo) }
            
            await MainActor.run { modelContext.insert(photo); try? modelContext.save() }
            
            do {
                let albumIdsForUpload = uploadTargetAlbumId.map { [$0] } ?? []
                let dto = try await SyncCenter.photoRemote.upload(
                    photoId: photoId, familyId: familyId, userId: uid,
                    imageData: data, fileName: fileName,
                    mimeType: mimeType, takenAt: now,
                    caption: nil, albumIds: albumIdsForUpload,
                    precomputedThumbnailB64: thumbB64,
                    precomputedVideoDurationSeconds: isVideo ? videoDurationSecs : nil,
                    onProgress: { p in Task { @MainActor in uploadProgress = (done + p) / total } }
                )
                await MainActor.run {
                    photo.downloadURL = dto.downloadURL
                    photo.syncState = .synced
                    try? modelContext.save()
                }
                KBLog.sync.kbInfo("uploadItems: \(isVideo ? "video" : "photo") OK photoId=\(photoId)")
            } catch {
                await MainActor.run {
                    photo.syncState = .pendingUpsert
                    photo.lastSyncError = error.localizedDescription
                    try? modelContext.save()
                    uploadError = error.localizedDescription
                }
                KBLog.sync.kbError("uploadItems: FAILED photoId=\(photoId) err=\(error.localizedDescription)")
            }
            
            done += 1
            await MainActor.run { uploadProgress = done / total }
        }
        
        await MainActor.run { withAnimation { isUploading = false; uploadProgress = 0 } }
    }
    
    private func uploadFromAppGroup(path: String, fileType: String) async {
        guard !uid.isEmpty else { KBLog.sync.kbError("uploadFromAppGroup: uid empty — abort"); return }
        let fileURL  = URL(fileURLWithPath: path)
        let ext      = fileURL.pathExtension.lowercased()
        let isVideo  = ["mp4", "mov", "m4v"].contains(ext) || fileType == "video"
        let mimeType = isVideo ? "video/mp4" : "image/jpeg"
        let photoId  = UUID().uuidString
        let now      = Date()
        let fileName = "\(isVideo ? "video" : "photo")_\(photoId).\(isVideo ? "mp4" : "jpg")"
        
        KBLog.sync.kbInfo("uploadFromAppGroup: START isVideo=\(isVideo) photoId=\(photoId)")
        await MainActor.run { withAnimation { isUploading = true; uploadProgress = 0 } }
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        do {
            guard let mediaData = try? Data(contentsOf: fileURL), !mediaData.isEmpty else {
                KBLog.sync.kbError("uploadFromAppGroup: cannot read data path=\(path)")
                await MainActor.run { withAnimation { isUploading = false }; uploadError = "Impossibile leggere il file." }
                return
            }
            let thumbB64: String?
            var videoDurationSecs: Double? = nil
            if isVideo {
                let t1 = await PhotoRemoteStore.makeVideoThumbnail(url: fileURL)
                let t2 = t1 == nil ? await PhotoRemoteStore.makeVideoThumbnail(from: mediaData) : nil
                thumbB64 = (t1 ?? t2)?.base64EncodedString()
                videoDurationSecs = await VideoCompressor.videoDuration(url: fileURL)
            } else {
                thumbB64 = PhotoRemoteStore.makeThumbnail(from: mediaData)?.base64EncodedString()
            }
            let storagePath = "families/\(familyId)/photos/\(photoId)/original.enc"
            let photo = KBFamilyPhoto(
                id: photoId, familyId: familyId, fileName: fileName, mimeType: mimeType,
                fileSize: Int64(mediaData.count), storagePath: storagePath,
                thumbnailBase64: thumbB64, takenAt: now, createdAt: now, updatedAt: now,
                createdBy: uid, updatedBy: uid
            )
            photo.syncState = .synced
            photo.videoDurationSeconds = isVideo ? videoDurationSecs : nil
            if !isVideo { cacheLocally(data: mediaData, photoId: photoId, photo: photo) }
            await MainActor.run { modelContext.insert(photo); try? modelContext.save() }
            
            let dto = try await SyncCenter.photoRemote.upload(
                photoId: photoId, familyId: familyId, userId: uid,
                imageData: mediaData, fileName: fileName, mimeType: mimeType, takenAt: now,
                caption: nil, albumIds: [], precomputedThumbnailB64: thumbB64,
                precomputedVideoDurationSeconds: isVideo ? videoDurationSecs : nil,
                onProgress: { p in Task { @MainActor in uploadProgress = p } }
            )
            await MainActor.run { photo.downloadURL = dto.downloadURL; photo.syncState = .synced; try? modelContext.save() }
            
            if isVideo {
                let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("KBPhotos", isDirectory: true)
                try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                let cachedVideoURL = cacheDir.appendingPathComponent("\(photoId).mp4")
                if (try? FileManager.default.copyItem(at: fileURL, to: cachedVideoURL)) != nil {
                    await MainActor.run { photo.localPath = cachedVideoURL.path; try? modelContext.save() }
                }
            }
            KBLog.sync.kbInfo("uploadFromAppGroup: OK photoId=\(photoId) isVideo=\(isVideo)")
        } catch {
            await MainActor.run {
                uploadError = error.localizedDescription
                KBLog.sync.kbError("uploadFromAppGroup: FAILED photoId=\(photoId) err=\(error.localizedDescription)")
            }
        }
        await MainActor.run { withAnimation { isUploading = false; uploadProgress = 0 } }
    }
    
    private func uploadCapturedPhoto(data: Data, targetAlbumId: String?) async {
        guard !uid.isEmpty else { return }
        let photoId  = UUID().uuidString; let now = Date()
        let fileName = "photo_\(photoId).jpg"
        let thumbB64 = PhotoRemoteStore.makeThumbnail(from: data)?.base64EncodedString()
        let storagePath = "families/\(familyId)/photos/\(photoId)/original.enc"
        await MainActor.run { withAnimation { isUploading = true; uploadProgress = 0 } }
        let photo = KBFamilyPhoto(
            id: photoId, familyId: familyId, fileName: fileName,
            mimeType: "image/jpeg", fileSize: Int64(data.count),
            storagePath: storagePath, thumbnailBase64: thumbB64,
            takenAt: now, createdAt: now, updatedAt: now, createdBy: uid, updatedBy: uid
        )
        photo.syncState = .synced
        if let albumId = targetAlbumId { photo.albumIdsRaw = albumId }
        cacheLocally(data: data, photoId: photoId, photo: photo)
        await MainActor.run { modelContext.insert(photo); try? modelContext.save() }
        do {
            let dto = try await SyncCenter.photoRemote.upload(
                photoId: photoId, familyId: familyId, userId: uid,
                imageData: data, fileName: fileName, mimeType: "image/jpeg", takenAt: now,
                caption: nil, albumIds: targetAlbumId.map { [$0] } ?? [],
                precomputedThumbnailB64: thumbB64, precomputedVideoDurationSeconds: nil,
                onProgress: { p in Task { @MainActor in uploadProgress = p } }
            )
            await MainActor.run { photo.downloadURL = dto.downloadURL; photo.syncState = .synced; try? modelContext.save() }
            KBLog.sync.kbInfo("uploadCapturedPhoto: OK photoId=\(photoId)")
        } catch {
            await MainActor.run {
                photo.syncState = .pendingUpsert; photo.lastSyncError = error.localizedDescription
                try? modelContext.save(); uploadError = error.localizedDescription
            }
            KBLog.sync.kbError("uploadCapturedPhoto: FAILED photoId=\(photoId) err=\(error.localizedDescription)")
        }
        await MainActor.run { withAnimation { isUploading = false; uploadProgress = 0 } }
    }
    
    private func uploadCapturedVideo(url: URL, targetAlbumId: String?) async {
        guard !uid.isEmpty else { return }
        await MainActor.run { withAnimation { isUploading = true; uploadProgress = 0 } }
        defer { try? FileManager.default.removeItem(at: url) }
        let videoURL = await VideoCompressor.compress(url: url) ?? url
        guard let data = try? Data(contentsOf: videoURL) else {
            await MainActor.run { withAnimation { isUploading = false }; uploadError = "Impossibile leggere il video." }
            return
        }
        let photoId = UUID().uuidString; let now = Date()
        let fileName    = "video_\(photoId).mp4"
        let thumbB64    = await PhotoRemoteStore.makeVideoThumbnail(url: videoURL)?.base64EncodedString()
        let durSecs     = await VideoCompressor.videoDuration(url: videoURL)
        let storagePath = "families/\(familyId)/photos/\(photoId)/original.enc"
        if videoURL != url { try? FileManager.default.removeItem(at: videoURL) }
        let photo = KBFamilyPhoto(
            id: photoId, familyId: familyId, fileName: fileName,
            mimeType: "video/mp4", fileSize: Int64(data.count),
            storagePath: storagePath, thumbnailBase64: thumbB64,
            takenAt: now, createdAt: now, updatedAt: now, createdBy: uid, updatedBy: uid
        )
        photo.syncState = .synced; photo.videoDurationSeconds = durSecs
        if let albumId = targetAlbumId { photo.albumIdsRaw = albumId }
        await MainActor.run { modelContext.insert(photo); try? modelContext.save() }
        do {
            let dto = try await SyncCenter.photoRemote.upload(
                photoId: photoId, familyId: familyId, userId: uid,
                imageData: data, fileName: fileName, mimeType: "video/mp4", takenAt: now,
                caption: nil, albumIds: targetAlbumId.map { [$0] } ?? [],
                precomputedThumbnailB64: thumbB64, precomputedVideoDurationSeconds: durSecs,
                onProgress: { p in Task { @MainActor in uploadProgress = p } }
            )
            await MainActor.run { photo.downloadURL = dto.downloadURL; photo.syncState = .synced; try? modelContext.save() }
            KBLog.sync.kbInfo("uploadCapturedVideo: OK photoId=\(photoId)")
        } catch {
            await MainActor.run {
                photo.syncState = .pendingUpsert; photo.lastSyncError = error.localizedDescription
                try? modelContext.save(); uploadError = error.localizedDescription
            }
            KBLog.sync.kbError("uploadCapturedVideo: FAILED photoId=\(photoId) err=\(error.localizedDescription)")
        }
        await MainActor.run { withAnimation { isUploading = false; uploadProgress = 0 } }
    }
    
    private func cacheLocally(data: Data, photoId: String, photo: KBFamilyPhoto) {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KBPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(photoId).jpg")
        try? data.write(to: url, options: .atomic)
        photo.localPath = url.path
    }
    
    private func softDeletePhoto(_ photo: KBFamilyPhoto) {
        photo.isDeleted = true; photo.updatedAt = Date()
        try? modelContext.save()
        vm.reloadLocal()
        let photoId = photo.id; let fid = familyId
        Task {
            do { try await SyncCenter.photoRemote.softDeletePhoto(familyId: fid, photoId: photoId) }
            catch { KBLog.sync.kbError("softDeletePhoto: FAILED photoId=\(photoId) err=\(error.localizedDescription)") }
        }
    }
    
    private func createAlbum() {
        let title = newAlbumTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !uid.isEmpty else { return }
        let album = KBPhotoAlbum(familyId: familyId, title: title, sortOrder: vm.albums.count, createdBy: uid, updatedBy: uid)
        modelContext.insert(album); try? modelContext.save()
        vm.reloadLocal()
        SyncCenter.shared.uploadAlbumDirectly(albumId: album.id, familyId: familyId, modelContext: modelContext)
        newAlbumTitle = ""
    }
    
    private func addSelectedPhotos(toAlbum albumId: String) {
        let toUpdate = photos.filter { selectedIds.contains($0.id) }
        for photo in toUpdate {
            var ids = photo.albumIds
            if !ids.contains(albumId) { ids.append(albumId) }
            photo.albumIdsRaw = ids.joined(separator: ",")
            photo.updatedAt = Date()
        }
        try? modelContext.save()
        for photo in toUpdate {
            SyncCenter.shared.enqueuePhotoUpsert(photoId: photo.id, familyId: familyId, modelContext: modelContext)
        }
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        withAnimation(.snappy) { isSelectMode = false; selectedIds = [] }
    }
    
    private func createAlbumAndAddSelected(title: String) {
        guard !title.isEmpty, !uid.isEmpty else { return }
        let album = KBPhotoAlbum(familyId: familyId, title: title, sortOrder: vm.albums.count, createdBy: uid, updatedBy: uid)
        modelContext.insert(album); try? modelContext.save()
        vm.reloadLocal()
        SyncCenter.shared.uploadAlbumDirectly(albumId: album.id, familyId: familyId, modelContext: modelContext)
        addSelectedPhotos(toAlbum: album.id)
    }
    
    private func softDeleteAlbum(_ album: KBPhotoAlbum) {
        album.isDeleted = true; album.updatedAt = Date()
        try? modelContext.save()
        vm.reloadLocal()
        SyncCenter.shared.deleteAlbumDirectly(albumId: album.id, familyId: familyId, modelContext: modelContext)
    }
    
    private func shareSelected() async {
        guard !selectedIds.isEmpty else { return }
        await MainActor.run { isPreparingShare = true }
        var items: [Any] = []
        for photo in photos.filter({ selectedIds.contains($0.id) }) {
            if let path = photo.localPath, FileManager.default.fileExists(atPath: path) {
                if photo.isVideo { items.append(URL(fileURLWithPath: path)) }
                else if let img = UIImage(contentsOfFile: path) { items.append(img) }
                continue
            }
            guard !photo.storagePath.isEmpty else { continue }
            do {
                let data = try await SyncCenter.photoRemote.download(storagePath: photo.storagePath, familyId: familyId, userId: uid)
                if photo.isVideo {
                    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(photo.id).mp4")
                    try? data.write(to: tmpURL); items.append(tmpURL)
                } else if let img = UIImage(data: data) { items.append(img) }
            } catch {
                KBLog.sync.kbError("shareSelected: download failed photoId=\(photo.id) err=\(error.localizedDescription)")
            }
        }
        await MainActor.run {
            isPreparingShare = false
            if !items.isEmpty { shareItems = items; showShareSheet = true }
        }
    }
    
    private func sendToChat(_ photo: KBFamilyPhoto) async {
        await MainActor.run { isSendingToChat = true }
        let ext    = photo.isVideo ? "mp4" : "jpg"
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(photo.id)_chat.\(ext)")
        do {
            let cacheDir  = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("KBPhotos", isDirectory: true)
            let cachedURL = cacheDir.appendingPathComponent("\(photo.id).\(ext)")
            if FileManager.default.fileExists(atPath: cachedURL.path) {
                try? FileManager.default.removeItem(at: tmpURL)
                try FileManager.default.copyItem(at: cachedURL, to: tmpURL)
            } else {
                guard !photo.storagePath.isEmpty else { await MainActor.run { isSendingToChat = false }; return }
                let data = try await SyncCenter.photoRemote.download(storagePath: photo.storagePath, familyId: familyId, userId: uid)
                try data.write(to: tmpURL, options: .atomic)
            }
            await MainActor.run {
                isSendingToChat = false
                coordinator.pendingShareImagePath = tmpURL.path
                coordinator.navigate(to: .chat)
            }
        } catch {
            await MainActor.run { isSendingToChat = false; sendToChatError = error.localizedDescription }
        }
    }
}

// MARK: - ActivityViewController

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - KBFamilyPhoto grid identity

extension KBFamilyPhoto {
    var stableGridId: String {
        if let dur = videoDurationSeconds { return "\(id)-\(Int(dur * 1000))" }
        return id
    }
}


// MARK: - IdentifiableImagePath (per sheet(item:) in PhotoFullscreenView)
// Wrapper Identifiable attorno al PATH del JPEG su disco.
// Passare il path invece dei Data evita di tenere il JPEG (~34MB)
// nello @State del parent view e in PhotoEditorView.imageData contemporaneamente.
// PhotoEditorView legge i bytes dal disco solo quando necessario (flattenToJPEG).

struct IdentifiableImagePath: Identifiable {
    let id   = UUID()
    let path: String   // percorso assoluto del JPEG su disco
}
// MARK: - PhotoThumbnailCell
//
// ╔══════════════════════════════════════════════════════════════════╗
// ║  FIX 1 — IOSurface crash / memoria GPU esaurita                ║
// ║    Causa: il vecchio loadFull() scaricava il file intero        ║
// ║    (34 MB) per ogni cella visibile nella griglia, esaurendo     ║
// ║    la memoria GPU → IOSurface creation failed: e00002c2.        ║
// ║    Fix: la griglia mostra SOLO photo.thumbnailData (max 200 px, ║
// ║    già in memoria, pochi KB). Il file intero viene scaricato    ║
// ║    solo in PhotoFullscreenView quando l'utente apre la foto.    ║
// ║                                                                  ║
// ║  FIX 2 — download triplicato/quadruplicato                     ║
// ║    Causa: loadFull() scaricava il file intero ad ogni .task     ║
// ║    rilanciato da reloadLocal() (vedi FamilyPhotosViewModel).    ║
// ║    Fix: rimosso completamente il .task e il download.           ║
// ║                                                                  ║
// ║  FIX 3 — _log() di debug attivo in produzione                  ║
// ║    Causa: Self._log() chiamato in ogni body, su ogni render,    ║
// ║    per ogni cella. Scriveva su KBLog ad ogni frame.             ║
// ║    Fix: rimosso.                                                ║
// ╚══════════════════════════════════════════════════════════════════╝

struct PhotoThumbnailCell: View {
    @Bindable var photo: KBFamilyPhoto
    let familyId: String
    let userId: String
    let videoDurationSeconds: Double?
    let isVideo: Bool
    
    var body: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            
            if let td = photo.thumbnailData, let img = UIImage(data: td) {
                // Thumbnail già in memoria (max 200 px, pochi KB).
                // Nessun download, nessuna allocazione GPU grande.
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                // Placeholder finché il thumbnail non arriva da Firestore.
                Image(systemName: isVideo ? "video" : "photo")
                    .font(.title3)
                    .foregroundStyle(.quaternary)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        // Nessun .task: non scarichiamo nulla nella griglia.
        // Il file completo viene scaricato solo in PhotoFullscreenView.load().
    }
    
    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - AlbumCard / AlbumCreateCard

private struct AlbumCard: View {
    let album: KBPhotoAlbum
    let previewPhotos: [KBFamilyPhoto]
    let photoCount: Int
    let cellWidth: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color.secondary.opacity(0.12)
                if let cover = previewPhotos.first,
                   let td = cover.thumbnailData, let img = UIImage(data: td) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Image(systemName: "rectangle.stack.fill").font(.largeTitle).foregroundStyle(.quaternary)
                }
            }
            .frame(width: cellWidth, height: cellWidth)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(album.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text("\(photoCount) foto").font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: cellWidth)
    }
}

private struct AlbumCreateCard: View {
    let cellWidth: CGFloat
    
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: cellWidth, height: cellWidth)
                .overlay(
                    Image(systemName: "plus").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                )
            Text("Nuovo album").font(.subheadline.weight(.semibold))
            Text(" ").font(.caption)
        }
        .frame(width: cellWidth)
    }
}

// MARK: - Full-screen viewer

struct PhotoFullscreenView: View {
    let startPhoto: KBFamilyPhoto
    let allPhotos: [KBFamilyPhoto]
    let familyId: String
    let userId: String
    let onDismiss: () -> Void
    
    @State private var currentIndex: Int
    // FIX OOM — imageCache tiene al massimo 3 immagini in memoria simultaneamente.
    // Ogni UIImage da 34 MB decodificata occupa ~100 MB di bitmap non compressa.
    // Con 3 foto il picco è ~300 MB, entro il limite dei device supportati.
    // Le immagini vengono ridimensionate alla dimensione dello schermo (vedi downscaleForDisplay)
    // prima di entrare in cache: ~6 MB invece di ~100 MB ciascuna.
    @State private var imageCache: [String: UIImage] = [:]
    // Ordine di inserimento per LRU eviction
    @State private var imageCacheOrder: [String] = []
    @State private var videoURLCache: [String: URL] = [:]
    // editorImageData: nil = sheet chiusa, non-nil = sheet aperta con quei JPEG bytes.
    // Passare Data invece di UIImage evita di tenere il bitmap (~12MB) nello @State.
    // sheet(item:) crea la sheet solo quando è non-nil → nessun race condition.
    @State private var editorImagePath: IdentifiableImagePath? = nil
    
    // Dimensione massima cache in memoria: 3 foto ridimensionate
    private let maxCachedImages = 3
    
    init(startPhoto: KBFamilyPhoto, allPhotos: [KBFamilyPhoto],
         familyId: String, userId: String, onDismiss: @escaping () -> Void) {
        self.startPhoto = startPhoto; self.allPhotos = allPhotos
        self.familyId = familyId; self.userId = userId; self.onDismiss = onDismiss
        _currentIndex = State(initialValue: allPhotos.firstIndex { $0.id == startPhoto.id } ?? 0)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $currentIndex) {
                ForEach(allPhotos.indices, id: \.self) { i in
                    let p = allPhotos[i]
                    FullscreenMediaCell(photo: p, image: imageCache[p.id], videoURL: videoURLCache[p.id])
                        .tag(i)
                        .task(id: p.id) { await load(p) }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30)).foregroundStyle(.white).shadow(radius: 6)
                    }
                    .padding(20).padding(.top, 44)
                }
                Spacer()
                let currentPhoto = allPhotos[currentIndex]
                if !currentPhoto.isVideo, imageCache[currentPhoto.id] != nil {
                    HStack {
                        Spacer()
                        Button {
                            // Carica l'immagine originale (non ridimensionata) per l'editor
                            Task { await loadOriginalForEditor(currentPhoto) }
                        } label: {
                            Label("Modifica", systemImage: "slider.horizontal.3")
                                .font(.subheadline.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(.trailing, 20).padding(.bottom, 52)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .sheet(item: $editorImagePath) { item in
            // sheet(item:) garantisce che la sheet venga creata SOLO quando
            // editorImageData è non-nil, eliminando il race condition dove la sheet
            // si apriva prima che i dati fossero disponibili.
            // Passare imagePath: String invece di Data evita di tenere il JPEG (~34MB)
            // nello @State. PhotoEditorView legge i bytes dal disco solo quando serve.
            let currentPhoto = allPhotos[currentIndex]
            PhotoEditorView(
                photo: currentPhoto, imagePath: item.path,
                familyId: familyId, userId: userId,
                onSaved: { newPhoto in
                    KBLog.sync.kbInfo("PhotoEditor: saved new photo id=\(newPhoto.id)")
                }
            )
        }
        .onDisappear {
            // FIX OOM — svuota la cache immagini quando si chiude il fullscreen.
            // I file rimangono su disco (Caches/KBPhotos) e vengono ricaricati
            // se l'utente riapre lo stesso fullscreen.
            imageCache.removeAll()
            imageCacheOrder.removeAll()
        }
    }
    
    // MARK: - Cache management (LRU, max 3 immagini)
    
    private func addToImageCache(id: String, image: UIImage) {
        // Se già presente aggiorna solo l'immagine (evita duplicati in order)
        if imageCache[id] != nil {
            imageCache[id] = image
            return
        }
        // Evict la più vecchia se la cache è piena
        if imageCacheOrder.count >= maxCachedImages, let oldest = imageCacheOrder.first {
            imageCache.removeValue(forKey: oldest)
            imageCacheOrder.removeFirst()
            KBLog.sync.kbDebug("PhotoFullscreen: evicted imageCache id=\(oldest.prefix(8)) (LRU)")
        }
        imageCache[id] = image
        imageCacheOrder.append(id)
    }
    
    // MARK: - Ridimensionamento per display (FIX OOM principale)
    //
    // Una foto da 34 MB (es. 4032×3024 HEIC) decodificata in UIImage
    // occupa width × height × 4 bytes ≈ 48 MB di bitmap.
    // Ridimensionata a 1170×877 (iPhone screen) occupa ~4 MB.
    // Questo riduce il picco di memoria GPU di ~12x.
    //
    // IMPORTANTE: questa immagine ridimensionata va bene per il visualizzatore
    // ma NON per PhotoEditorView, che ha bisogno della risoluzione originale
    // per un flatten() di qualità. Per questo usiamo loadOriginalForEditor().
    
    private func downscaleForDisplay(_ data: Data) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return Self.downscaleSource(src)
    }
    
    /// Versione URL: NON carica il file in Data — legge solo l'header necessario.
    /// CGImageSourceCreateWithURL usa lazy I/O: decodifica solo i byte necessari
    /// per produrre il thumbnail, senza mai allocare il JPEG intero in RAM.
    /// Risparmio: 34MB per ogni foto caricata nel fullscreen viewer.
    private func downscaleForDisplayFromURL(_ url: URL) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return Self.downscaleSource(src)
    }
    
    private static func downscaleSource(_ src: CGImageSource) -> UIImage? {
        let props     = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let origW     = (props?[kCGImagePropertyPixelWidth]  as? CGFloat) ?? 0
        let origH     = (props?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
        let origMax   = max(origW, origH)
        let screen    = UIScreen.main.bounds.size
        let scale     = UIScreen.main.scale
        let targetMax = max(screen.width, screen.height) * scale * 1.5
        let maxPx     = origMax > 0 ? min(targetMax, origMax) : targetMax
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
    
    // MARK: - Carica immagine originale per editor
    //
    // Priorità di lettura:
    //   1. photo.localPath  — scritto da cacheLocally() all'upload (foto/rullino/camera)
    //   2. Caches/KBPhotos/{id}.jpg — scritto da load() dopo il download fullscreen
    //   3. Download fresco da Firebase (edge case: entrambi mancanti)
    //
    // editorImage viene impostato prima di essere presentato come item della sheet.
    
    // Carica l'immagine originale a piena risoluzione per l'editor.
    //
    // IMPORTANTE: non usa mai il file in Caches/KBPhotos/{id}.jpg perché
    // quel file è scritto da downscaleForDisplay() ed è ridimensionato alla
    // dimensione dello schermo (~1/12 dei pixel originali). Usarlo nell'editor
    // produce foto "stracchate" e salvataggi a bassa risoluzione.
    //
    // Strategia:
    //   1. photo.localPath — JPEG originale scritto da cacheLocally() all'upload.
    //      È a piena risoluzione. Usato direttamente leggendo i byte dal disco.
    //   2. Download fresco — se localPath è assente o il file è sparito da Caches.
    //
    // I JPEG bytes vengono passati a PhotoEditorView che gestisce internamente
    // la normalizzazione dell'orientamento EXIF.
    
    private func loadOriginalForEditor(_ photo: KBFamilyPhoto) async {
        // Passa i JPEG bytes originali direttamente a PhotoEditorView come Data.
        // PhotoEditorView li riceve come imageData: Data e:
        //   - genera una preview ridimensionata (~4MB) per la UI
        //   - usa i bytes originali solo in flattenToJPEG() al salvataggio
        // Questo evita di allocare il bitmap non compresso (~12-27MB) nello @State.
        
        // 1. photo.localPath — JPEG locale scritto da cacheLocally() all'upload
        if let localPath = photo.localPath,
           FileManager.default.fileExists(atPath: localPath),
           FileManager.default.fileExists(atPath: localPath) {
            // Passa solo il path — PhotoEditorView legge i bytes dal disco quando serve.
            // Evita di tenere 34MB in RAM nello @State.
            KBLog.sync.kbDebug("PhotoFullscreen: editor path from localPath photoId=\(photo.id)")
            await MainActor.run { editorImagePath = IdentifiableImagePath(path: localPath) }
            return
        }
        
        // 2. Download fresco da Firebase Storage
        guard !photo.storagePath.isEmpty else {
            KBLog.sync.kbError("PhotoFullscreen: loadOriginalForEditor storagePath empty photoId=\(photo.id)")
            return
        }
        KBLog.sync.kbDebug("PhotoFullscreen: editor downloading photoId=\(photo.id)")
        do {
            let data = try await SyncCenter.photoRemote.download(
                storagePath: photo.storagePath, familyId: familyId, userId: userId
            )
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("KBPhotos", isDirectory: true)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let origURL = cacheDir.appendingPathComponent("\(photo.id)_orig.jpg")
            try? data.write(to: origURL, options: .atomic)
            // Passa il path sul disco — non i Data in RAM.
            KBLog.sync.kbDebug("PhotoFullscreen: editor path from download photoId=\(photo.id)")
            await MainActor.run { editorImagePath = IdentifiableImagePath(path: origURL.path) }
        } catch {
            KBLog.sync.kbError("PhotoFullscreen: loadOriginalForEditor FAILED photoId=\(photo.id) err=\(error.localizedDescription)")
        }
    }
    
    private func load(_ photo: KBFamilyPhoto) async {
        let isVideo = photo.isVideo
        if isVideo && videoURLCache[photo.id] != nil { return }
        if !isVideo && imageCache[photo.id] != nil { return }
        
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KBPhotos", isDirectory: true)
        let ext      = isVideo ? "mp4" : "jpg"
        let localURL = cacheDir.appendingPathComponent("\(photo.id).\(ext)")
        
        if FileManager.default.fileExists(atPath: localURL.path) {
            if isVideo {
                await MainActor.run { videoURLCache[photo.id] = localURL }
            } else if let img = downscaleForDisplayFromURL(localURL) {
                // FIX OOM — CGImageSourceCreateWithURL legge solo i byte necessari
                // senza caricare il JPEG intero in RAM (risparmio ~34MB per foto).
                await MainActor.run { addToImageCache(id: photo.id, image: img) }
            }
            return
        }
        
        guard !photo.storagePath.isEmpty else { return }
        KBLog.sync.kbDebug("PhotoFullscreen: start download photoId=\(photo.id) isVideo=\(isVideo)")
        do {
            let data = try await SyncCenter.photoRemote.download(storagePath: photo.storagePath, familyId: familyId, userId: userId)
            KBLog.sync.kbDebug("PhotoFullscreen: download OK bytes=\(data.count) photoId=\(photo.id)")
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            if isVideo {
                let rawTmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
                do { try data.write(to: rawTmp, options: .atomic) } catch {
                    KBLog.sync.kbError("PhotoFullscreen: write tmp failed photoId=\(photo.id)"); return
                }
                let playableURL: URL
                if let remuxed = await VideoCompressor.remux(from: rawTmp, to: localURL) {
                    playableURL = remuxed
                } else {
                    try? FileManager.default.copyItem(at: rawTmp, to: localURL)
                    playableURL = localURL
                }
                try? FileManager.default.removeItem(at: rawTmp)
                await MainActor.run { videoURLCache[photo.id] = playableURL }
                KBLog.sync.kbDebug("PhotoFullscreen: video cached photoId=\(photo.id)")
                
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
                        KBLog.sync.kbDebug("PhotoFullscreen: persisted dur=\(dur)s photoId=\(photo.id)")
                    }
                }
            } else {
                try? data.write(to: localURL, options: .atomic)
                // FIX OOM — downscale prima di mettere in cache GPU.
                // kCGImageSourceCreateThumbnailFromImageAlways non alloca mai
                // il bitmap originale, decodifica direttamente alla dimensione target.
                // Scrivi prima su disco, poi decodifica dall'URL — evita di tenere
                // data (34MB) e il bitmap contemporaneamente in RAM.
                if let img = downscaleForDisplayFromURL(localURL) {
                    await MainActor.run { addToImageCache(id: photo.id, image: img) }
                } else {
                    KBLog.sync.kbError("PhotoFullscreen: UIImage init failed photoId=\(photo.id)")
                }
            }
        } catch {
            KBLog.sync.kbError("PhotoFullscreen: FAILED photoId=\(photo.id) err=\(error.localizedDescription)")
        }
    }
}

// MARK: - FullscreenMediaCell

private struct FullscreenMediaCell: View {
    let photo: KBFamilyPhoto
    let image: UIImage?
    let videoURL: URL?
    
    @State private var isPlaying  = false
    @State private var playerReady = false
    
    private var isVideo: Bool { photo.isVideo }
    
    var body: some View {
        ZStack {
            Color.black
            if isVideo {
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
                                    .font(.system(size: 28, weight: .bold)).foregroundStyle(.white).offset(x: 3)
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
    let url: URL
    let onReady: () -> Void
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        let vc = AVPlayerViewController()
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
            observation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                guard let self, !self.didFire else { return }
                if player.timeControlStatus == .playing {
                    self.didFire = true
                    DispatchQueue.main.async { onReady() }
                }
            }
        }
    }
}

// MARK: - GridWidthKey

private struct GridWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Supporting types

enum PhotoTab: String, CaseIterable, Identifiable {
    case library, albums
    var id: Self { self }
    var label: String { self == .library ? "Libreria" : "Album" }
}

enum PhotoGrouping: String, CaseIterable, Identifiable {
    case day, month, year
    var id: Self { self }
    var label: String {
        switch self { case .day: "Giorno"; case .month: "Mese"; case .year: "Anno" }
    }
}

struct PhotoGroup { let key: Date; let label: String; let photos: [KBFamilyPhoto] }
