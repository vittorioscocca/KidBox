//
//  ChatMediaGalleryView.swift
//  KidBox
//
//  • Si apre come sheet da ChatView
//  • Tab Media / Link / Doc + barra ricerca per tab
//  • .photo, .video, .mediaGroup (max 10 item)
//  • Fullscreen come overlay interno alla sheet (evita conflitti sheet-on-sheet)
//  • Elimina: scelta "per me / per tutti", naviga a successiva/precedente
//

import SwiftUI
import SwiftData
import QuickLook
import AVKit
import FirebaseAuth

// MARK: - Tab

enum ChatMediaGalleryTab: String, CaseIterable {
    case media = "Media"
    case link  = "Link"
    case doc   = "Doc"
}

// MARK: - ChatMediaGridItem

struct ChatMediaGridItem: Identifiable {
    let id:        String
    let message:   KBChatMessage
    let urlString: String
    let isVideo:   Bool
    let duration:  Int?
    
    var searchText: String {
        "\(message.senderName) \(message.createdAt.formatted(date: .abbreviated, time: .omitted))"
    }
    var videoCacheKey: String {
        guard isVideo else { return id }
        if var c = URLComponents(string: urlString) { c.query = nil; return c.string ?? urlString }
        return urlString
    }
}

// MARK: - ChatMediaGalleryView

struct ChatMediaGalleryView: View {
    
    let familyId: String
    var onGoToMessage: ((String) -> Void)? = nil
    var onReply:       ((KBChatMessage) -> Void)? = nil
    /// Bool = true → elimina per tutti, false → solo per me
    var onDelete:      ((ChatMediaGridItem, Bool) -> Void)? = nil
    
    @Environment(\.dismiss)     private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @Query private var allMessages: [KBChatMessage]
    
    @State private var selectedTab:          ChatMediaGalleryTab = .media
    @State private var searchMedia:          String = ""
    @State private var searchLink:           String = ""
    @State private var searchDoc:            String = ""
    @State private var previewURL:           URL?   = nil
    @State private var isLoadingPreview:     Bool   = false
    @State private var previewError:         String? = nil
    
    /// Fullscreen: stato locale, overlay interno alla sheet
    @State private var fullscreenStartIndex: Int?                 = nil
    @State private var frozenMediaItems:     [ChatMediaGridItem]? = nil
    
    @FocusState private var isSearchFocused: Bool
    
    init(familyId: String,
         onGoToMessage: ((String) -> Void)? = nil,
         onReply:       ((KBChatMessage) -> Void)? = nil,
         onDelete:      ((ChatMediaGridItem, Bool) -> Void)? = nil) {
        self.familyId      = familyId
        self.onGoToMessage = onGoToMessage
        self.onReply       = onReply
        self.onDelete      = onDelete
        _allMessages = Query(
            filter: #Predicate<KBChatMessage> {
                $0.familyId == familyId && $0.isDeleted == false
            },
            sort: [SortDescriptor(\KBChatMessage.createdAt, order: .reverse)]
        )
    }
    
    // MARK: - Media items
    
    var allMediaItems: [ChatMediaGridItem] {
        var items: [ChatMediaGridItem] = []
        for msg in allMessages {
            switch msg.type {
            case .photo:
                guard let url = msg.mediaURL else { continue }
                items.append(.init(id: msg.id, message: msg,
                                   urlString: url, isVideo: false, duration: nil))
            case .video:
                guard let url = msg.mediaURL else { continue }
                items.append(.init(id: msg.id, message: msg,
                                   urlString: url, isVideo: true,
                                   duration: msg.mediaDurationSeconds))
            case .mediaGroup:
                let urls  = msg.mediaGroupURLs
                let types = msg.mediaGroupTypes
                for (i, url) in urls.enumerated() {
                    let isVid = (types.indices.contains(i) ? types[i] : "photo") == "video"
                    items.append(.init(id: "\(msg.id)_\(i)", message: msg,
                                       urlString: url, isVideo: isVid, duration: nil))
                }
            default: continue
            }
        }
        return items
    }
    
    private var filteredMediaItems: [ChatMediaGridItem] {
        let q = searchMedia.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return allMediaItems }
        return allMediaItems.filter { $0.searchText.localizedCaseInsensitiveContains(q) }
    }
    
    // MARK: - Link
    
    private var allLinkMessages: [KBChatMessage] {
        allMessages.filter { msg in
            guard msg.type == .text, let t = msg.text else { return false }
            return extractFirstURL(from: t) != nil
        }
    }
    
    private var filteredLinkMessages: [KBChatMessage] {
        let q = searchLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return allLinkMessages }
        return allLinkMessages.filter { msg in
            let url = msg.text.flatMap { extractFirstURL(from: $0) }
            return (url?.host ?? "").localizedCaseInsensitiveContains(q)
            || (url?.absoluteString ?? "").localizedCaseInsensitiveContains(q)
            || msg.senderName.localizedCaseInsensitiveContains(q)
        }
    }
    
    // MARK: - Doc
    
    private var allDocMessages: [KBChatMessage] {
        allMessages.filter { $0.type == .document }
    }
    
    private var filteredDocMessages: [KBChatMessage] {
        let q = searchDoc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return allDocMessages }
        return allDocMessages.filter { msg in
            (msg.text ?? "").localizedCaseInsensitiveContains(q)
            || msg.senderName.localizedCaseInsensitiveContains(q)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                segmentedHeader
                Divider()
                searchBar
                Divider()
                contentArea
            }
            .background(pageBackground.ignoresSafeArea())
            .navigationTitle("Media, link e doc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        // QuickLook doc
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let url = previewURL { GalleryQLPreview(urls: [url]) }
        }
        .overlay {
            if isLoadingPreview {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.5)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let err = previewError {
                Text(err)
                    .font(.caption).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.red.opacity(0.88), in: Capsule())
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            withAnimation { previewError = nil }
                        }
                    }
            }
        }
        // ── Fullscreen overlay interno alla sheet ────────────────────────────
        // Usare overlay invece di fullScreenCover/sheet evita il warning
        // "only presenting a single sheet is supported"
        .overlay {
            if let idx = fullscreenStartIndex, let frozen = frozenMediaItems {
                ChatMediaFullscreenView(
                    items: frozen,
                    startIndex: idx,
                    onDismiss: {
                        withAnimation(.easeIn(duration: 0.2)) {
                            fullscreenStartIndex = nil
                            frozenMediaItems = nil
                        }
                    },
                    onGoToMessage: { msgId in
                        fullscreenStartIndex = nil
                        frozenMediaItems = nil
                        onGoToMessage?(msgId)
                    },
                    onReply: { msg in
                        fullscreenStartIndex = nil
                        frozenMediaItems = nil
                        onReply?(msg)
                    },
                    onDelete: { item, forEveryone in
                        onDelete?(item, forEveryone)
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: fullscreenStartIndex != nil)
    }
    
    // MARK: - Segmented header
    
    private var segmentedHeader: some View {
        HStack(spacing: 0) {
            ForEach(ChatMediaGalleryTab.allCases, id: \.self) { tab in
                let sel = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                        isSearchFocused = false
                    }
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(sel ? .semibold : .regular))
                            .foregroundStyle(sel ? Color.accentColor : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        Rectangle()
                            .fill(sel ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(headerBackground)
    }
    
    // MARK: - Search bar
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary).font(.system(size: 15))
            TextField(searchPlaceholder, text: currentSearchBinding)
                .font(.subheadline)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !currentSearchText.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { clearCurrentSearch() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary).font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(searchBarBackground, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(headerBackground)
    }
    
    private var searchPlaceholder: String {
        switch selectedTab {
        case .media: return "Cerca per mittente o data"
        case .link:  return "Cerca link o sito"
        case .doc:   return "Cerca documento o mittente"
        }
    }
    private var currentSearchText: String {
        switch selectedTab {
        case .media: return searchMedia
        case .link:  return searchLink
        case .doc:   return searchDoc
        }
    }
    private var currentSearchBinding: Binding<String> {
        switch selectedTab {
        case .media: return $searchMedia
        case .link:  return $searchLink
        case .doc:   return $searchDoc
        }
    }
    private func clearCurrentSearch() {
        switch selectedTab {
        case .media: searchMedia = ""
        case .link:  searchLink  = ""
        case .doc:   searchDoc   = ""
        }
    }
    
    // MARK: - Content area
    
    @ViewBuilder
    private var contentArea: some View {
        switch selectedTab {
        case .media: mediaGrid
        case .link:  linkList
        case .doc:   docList
        }
    }
    
    // MARK: - Media grid
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    
    @ViewBuilder
    private var mediaGrid: some View {
        if allMediaItems.isEmpty {
            emptyState(icon: "photo.on.rectangle.angled", label: "Nessun media condiviso")
        } else if filteredMediaItems.isEmpty {
            emptySearchState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(filteredMediaItems) { item in
                        MediaThumbCell(item: item) {
                            isSearchFocused = false
                            // Congela la lista al momento del tap
                            let snapshot = allMediaItems
                            if let idx = snapshot.firstIndex(where: { $0.id == item.id }) {
                                frozenMediaItems     = snapshot
                                fullscreenStartIndex = idx
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }
    
    // MARK: - Link list
    
    @ViewBuilder
    private var linkList: some View {
        if allLinkMessages.isEmpty {
            emptyState(icon: "link", label: "Nessun link condiviso")
        } else if filteredLinkMessages.isEmpty {
            emptySearchState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredLinkMessages) { msg in
                        if let text = msg.text, let url = extractFirstURL(from: text) {
                            GalleryLinkRow(message: msg, url: url)
                                .padding(.horizontal, 16)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }
    
    // MARK: - Doc list
    
    @ViewBuilder
    private var docList: some View {
        if allDocMessages.isEmpty {
            emptyState(icon: "doc.fill", label: "Nessun documento condiviso")
        } else if filteredDocMessages.isEmpty {
            emptySearchState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredDocMessages) { msg in
                        GalleryDocRow(message: msg) { Task { await downloadDoc(msg) } }
                            .padding(.horizontal, 16)
                        Divider().padding(.leading, 16)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }
    
    // MARK: - Empty states
    
    private func emptyState(icon: String, label: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.quaternary)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var emptySearchState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(.quaternary)
            Text("Nessun risultato").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text("Prova con un termine diverso").font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Doc download
    
    private func downloadDoc(_ msg: KBChatMessage) async {
        guard let urlString = msg.mediaURL, let remote = URL(string: urlString) else { return }
        let raw = msg.text ?? "file"
        let e   = URL(fileURLWithPath: raw).pathExtension
        let ext = e.isEmpty ? "pdf" : e
        isLoadingPreview = true; previewError = nil
        defer { isLoadingPreview = false }
        do {
            let (tmp, _) = try await URLSession.shared.download(from: remote)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(msg.text ?? "file.\(ext)")
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tmp, to: dest)
            previewURL = dest
        } catch {
            withAnimation { previewError = "Apertura fallita: \(error.localizedDescription)" }
        }
    }
    
    // MARK: - URL extraction
    
    func extractFirstURL(from text: String) -> URL? {
        guard let det = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return nil }
        return det.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.url
    }
    
    // MARK: - Theme
    
    private var pageBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(.systemGroupedBackground)
    }
    private var headerBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.secondarySystemBackground)
    }
    private var searchBarBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.26, green: 0.26, blue: 0.26)
        : Color(.tertiarySystemFill)
    }
}

// MARK: - MediaThumbCell

private struct MediaThumbCell: View {
    
    let item:  ChatMediaGridItem
    let onTap: () -> Void
    
    private var side: CGFloat { (UIScreen.main.bounds.width - 4) / 3 }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if item.isVideo, let url = URL(string: item.urlString) {
                VideoThumbnailView(videoURL: url, cacheKey: item.videoCacheKey)
                    .frame(width: side, height: side).clipped()
            } else if let url = URL(string: item.urlString) {
                CachedAsyncImage(url: url, contentMode: .fill)
                    .frame(width: side, height: side).clipped()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: side, height: side)
                    .overlay(Image(systemName: "photo").foregroundStyle(.quaternary))
            }
            if item.isVideo {
                HStack(spacing: 3) {
                    Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                    if let d = item.duration, d > 0 {
                        Text(formatDur(d)).font(.system(size: 10, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(5)
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
    
    private func formatDur(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}

// MARK: - ChatMediaFullscreenView

struct ChatMediaFullscreenView: View {
    
    let items:         [ChatMediaGridItem]
    let startIndex:    Int
    let onDismiss:     () -> Void
    var onGoToMessage: ((String) -> Void)? = nil
    var onReply:       ((KBChatMessage) -> Void)? = nil
    var onDelete:      ((ChatMediaGridItem, Bool) -> Void)? = nil
    
    @State private var localItems:   [ChatMediaGridItem]
    @State private var currentIndex: Int
    @State private var imageCache:   [String: UIImage] = [:]
    @State private var playerCache:  [String: AVPlayer] = [:]
    @State private var showChrome:   Bool    = true
    @State private var dragOffset:   CGFloat = 0
    
    @State private var shareItems:        [Any]  = []
    @State private var showShare:         Bool   = false
    @State private var showDeleteConfirm: Bool   = false
    
    init(items: [ChatMediaGridItem],
         startIndex: Int,
         onDismiss: @escaping () -> Void,
         onGoToMessage: ((String) -> Void)? = nil,
         onReply:       ((KBChatMessage) -> Void)? = nil,
         onDelete:      ((ChatMediaGridItem, Bool) -> Void)? = nil) {
        self.items         = items
        self.startIndex    = startIndex
        self.onDismiss     = onDismiss
        self.onGoToMessage = onGoToMessage
        self.onReply       = onReply
        self.onDelete      = onDelete
        let safeIndex      = max(0, min(startIndex, items.count - 1))
        _localItems        = State(initialValue: items)
        _currentIndex      = State(initialValue: safeIndex)
    }
    
    private var current: ChatMediaGridItem {
        guard localItems.indices.contains(currentIndex) else { return localItems[0] }
        return localItems[currentIndex]
    }
    
    private var canDeleteForEveryone: Bool {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return false }
        let msg = current.message
        guard msg.senderId == uid else { return false }
        return Date().timeIntervalSince(msg.createdAt) <= 300
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $currentIndex) {
                ForEach(Array(localItems.enumerated()), id: \.element.id) { idx, item in
                    FullscreenCell(
                        item:   item,
                        image:  imageCache[item.id],
                        player: playerCache[item.id]
                    )
                    .tag(idx)
                    .task(id: item.id) { await loadItem(item) }
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: dragOffset)
            
            if showChrome {
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        .padding(.leading, 16).padding(.top, 60)
                        
                        Spacer()
                        
                        VStack(spacing: 2) {
                            Text(current.message.senderName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white).lineLimit(1)
                            Text(current.message.createdAt.formatted(
                                date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.white.opacity(0.72))
                        }
                        .padding(.top, 60)
                        
                        Spacer()
                        
                        Text("\(currentIndex + 1) / \(localItems.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.4), in: Capsule())
                            .padding(.trailing, 16).padding(.top, 60)
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(colors: [.black.opacity(0.65), .clear],
                                       startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .top)
                    )
                    
                    Spacer()
                    
                    VStack(spacing: 0) {
                        if localItems.count > 1 {
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 3) {
                                        ForEach(Array(localItems.enumerated()), id: \.element.id) { idx, item in
                                            thumbStrip(item: item, idx: idx, proxy: proxy)
                                        }
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 6)
                                }
                                .onChange(of: currentIndex) { _, newIdx in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        proxy.scrollTo("thumb_\(newIdx)", anchor: .center)
                                    }
                                }
                            }
                        }
                        
                        Divider().overlay(Color.white.opacity(0.15))
                        
                        HStack(spacing: 0) {
                            toolbarButton(icon: "square.and.arrow.up", label: "Condividi") {
                                Task { await prepareShare() }
                            }
                            toolbarButton(icon: "arrowshape.turn.up.left", label: "Rispondi") {
                                onReply?(current.message); onDismiss()
                            }
                            toolbarButton(icon: "arrow.up.message", label: "Messaggio") {
                                onGoToMessage?(current.message.id); onDismiss()
                            }
                            toolbarButton(icon: "trash", label: "Elimina", tint: .red) {
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
        .sheet(isPresented: $showShare) {
            ActivityViewController(activityItems: shareItems).ignoresSafeArea()
        }
        .confirmationDialog("Elimina questo media?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Elimina per me", role: .destructive) {
                deleteAndNavigate(forEveryone: false)
            }
            if canDeleteForEveryone {
                Button("Elimina per tutti", role: .destructive) {
                    deleteAndNavigate(forEveryone: true)
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(canDeleteForEveryone
                 ? "Scegli se eliminare il media solo per te o per tutti i membri."
                 : "Il media verrà rimosso dalla tua chat.")
        }
    }
    
    // MARK: - Delete & navigate
    
    private func deleteAndNavigate(forEveryone: Bool) {
        guard localItems.indices.contains(currentIndex) else { return }
        let itemToDelete = current
        let removedIndex = currentIndex
        
        if localItems.count == 1 {
            onDelete?(itemToDelete, forEveryone)
            onDismiss()
            return
        }
        
        if currentIndex < localItems.count - 1 {
            withAnimation(.easeInOut(duration: 0.2)) { currentIndex += 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                localItems.remove(at: removedIndex)
                currentIndex = max(0, currentIndex - 1)
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { currentIndex -= 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                localItems.remove(at: removedIndex)
            }
        }
        
        onDelete?(itemToDelete, forEveryone)
    }
    
    // MARK: - Thumbnail strip
    
    @ViewBuilder
    private func thumbStrip(item: ChatMediaGridItem,
                            idx: Int,
                            proxy: ScrollViewProxy) -> some View {
        let isSelected = idx == currentIndex
        ZStack {
            if item.isVideo, let url = URL(string: item.urlString) {
                VideoThumbnailView(videoURL: url, cacheKey: "strip_\(item.videoCacheKey)")
                    .frame(width: 52, height: 52).clipped()
            } else if let url = URL(string: item.urlString) {
                CachedAsyncImage(url: url, contentMode: .fill)
                    .frame(width: 52, height: 52).clipped()
            }
            if item.isVideo {
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
        .id("thumb_\(idx)")
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { currentIndex = idx }
        }
    }
    
    // MARK: - Toolbar button
    
    private func toolbarButton(icon: String,
                               label: String,
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
    
    private func prepareShare() async {
        guard let remote = URL(string: current.urlString) else { return }
        do {
            let (tmp, _) = try await URLSession.shared.download(from: remote)
            let ext  = current.isVideo ? "mp4" : "jpg"
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".\(ext)")
            try? FileManager.default.moveItem(at: tmp, to: dest)
            await MainActor.run { shareItems = [dest]; showShare = true }
        } catch {}
    }
    
    // MARK: - Load
    
    private func loadItem(_ item: ChatMediaGridItem) async {
        guard let remote = URL(string: item.urlString) else { return }
        if item.isVideo {
            guard playerCache[item.id] == nil else { return }
            let p = AVPlayer(url: remote)
            await MainActor.run { playerCache[item.id] = p }
        } else {
            guard imageCache[item.id] == nil else { return }
            do {
                let (tmp, _) = try await URLSession.shared.download(from: remote)
                if let img = UIImage(contentsOfFile: tmp.path) {
                    let scaled = await downscale(img)
                    await MainActor.run { imageCache[item.id] = scaled }
                }
            } catch {}
        }
    }
    
    private func downscale(_ img: UIImage) async -> UIImage {
        let maxSide: CGFloat = UIScreen.main.bounds.width * UIScreen.main.scale * 1.5
        let s = img.size
        guard Swift.max(s.width, s.height) > maxSide else { return img }
        let r = maxSide / Swift.max(s.width, s.height)
        let t = CGSize(width: s.width * r, height: s.height * r)
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let out = UIGraphicsImageRenderer(size: t).image { _ in
                    img.draw(in: .init(origin: .zero, size: t))
                }
                cont.resume(returning: out)
            }
        }
    }
}

// MARK: - ActivityViewController

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - FullscreenCell

private struct FullscreenCell: View {
    let item:   ChatMediaGridItem
    let image:  UIImage?
    let player: AVPlayer?
    
    var body: some View {
        ZStack {
            Color.black
            if item.isVideo {
                if let player {
                    VideoPlayer(player: player).ignoresSafeArea()
                } else if let url = URL(string: item.urlString) {
                    VideoThumbnailView(videoURL: url, cacheKey: item.videoCacheKey)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(ProgressView().tint(.white))
                }
            } else {
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let url = URL(string: item.urlString) {
                    CachedAsyncImage(url: url, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

// MARK: - GalleryLinkRow

private struct GalleryLinkRow: View {
    let message: KBChatMessage
    let url: URL
    
    var body: some View {
        Button { UIApplication.shared.open(url) } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: "safari.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(url.host ?? url.absoluteString)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(url.absoluteString)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 6) {
                        Text(message.senderName)
                            .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary).font(.caption2)
                        Text(message.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GalleryDocRow

private struct GalleryDocRow: View {
    let message: KBChatMessage
    let onTap:   () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: iconName)
                        .font(.system(size: 22))
                        .foregroundStyle(accentColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(message.text ?? "Documento")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    HStack(spacing: 8) {
                        if let sz = message.mediaFileSize {
                            Text(ByteCountFormatter.string(fromByteCount: sz, countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Text(message.senderName).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.circle").font(.title3).foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var ext: String { (message.text ?? "").lowercased() }
    private var iconName: String {
        if ext.hasSuffix(".pdf")                            { return "doc.richtext.fill" }
        if ext.hasSuffix(".doc") || ext.hasSuffix(".docx") { return "doc.text.fill" }
        if ext.hasSuffix(".xls") || ext.hasSuffix(".xlsx") { return "tablecells.fill" }
        if ext.hasSuffix(".ppt") || ext.hasSuffix(".pptx") { return "rectangle.on.rectangle.fill" }
        if ext.hasSuffix(".zip") || ext.hasSuffix(".rar")  { return "archivebox.fill" }
        return "doc.fill"
    }
    private var accentColor: Color {
        if ext.hasSuffix(".pdf")                            { return .red }
        if ext.hasSuffix(".doc") || ext.hasSuffix(".docx") { return .blue }
        if ext.hasSuffix(".xls") || ext.hasSuffix(".xlsx") { return .green }
        if ext.hasSuffix(".ppt") || ext.hasSuffix(".pptx") { return .orange }
        if ext.hasSuffix(".zip") || ext.hasSuffix(".rar")  { return .purple }
        return .accentColor
    }
}

// MARK: - GalleryQLPreview

private struct GalleryQLPreview: UIViewControllerRepresentable {
    let urls: [URL]
    func makeCoordinator() -> Coordinator { Coordinator(urls: urls) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: QLPreviewController, context: Context) {
        context.coordinator.urls = urls; vc.reloadData()
    }
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        var urls: [URL]
        init(urls: [URL]) { self.urls = urls }
        func numberOfPreviewItems(in c: QLPreviewController) -> Int { urls.count }
        func previewController(_ c: QLPreviewController,
                               previewItemAt i: Int) -> QLPreviewItem { urls[i] as NSURL }
    }
}
