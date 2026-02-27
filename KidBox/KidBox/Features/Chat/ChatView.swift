//
//  ChatView.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import FirebaseAuth
import Combine
import UniformTypeIdentifiers
import MapKit

// MARK: - ChatView (entry point)


struct ChatView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    
    @State private var searchText: String = ""
    @State private var isSearchPresented: Bool = false
    
    private var familyId: String { families.first?.id ?? "" }
    
    var body: some View {
        Group {
            if familyId.isEmpty {
                emptyNoFamily
            } else {
                ChatConversationView(
                    familyId: familyId,
                    searchText: searchText
                )
            }
        }
        .navigationTitle("Chat famiglia")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    isSearchPresented = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                // opzionale: chiudi/clear quando la search è aperta
                if isSearchPresented {
                    Button {
                        searchText = ""
                        isSearchPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Cerca messaggi"
        )
    }
    
    private var emptyNoFamily: some View {
        VStack(spacing: 14) {
            Image(systemName: "message.fill")
                .font(.title2).foregroundStyle(.secondary)
            Text("Prima crea o unisciti a una famiglia.")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - ChatConversationView

private struct ChatConversationView: View {
    
    let familyId: String
    let searchText: String
    
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: ChatViewModel
    
    // Media picker
    @State private var showMediaPicker = false
    @State private var mediaPickerItems: [PhotosPickerItem] = []
    @State private var showLocationSheet = false
    
    // Camera
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var cameraVideoURL: URL?
    
    // Document picker
    @State private var showDocumentPicker = false
    
    // Reaction picker
    @State private var messageForReaction: KBChatMessage?
    
    // Clear chat
    @State private var showClearConfirm = false
    
    // Scroll
    @State private var showScrollToBottom = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showDeleteBar: Bool = false
    
    // Date pill floating (stile WhatsApp)
    @State private var floatingDateLabel: String = ""
    @State private var showFloatingDate: Bool = false
    @State private var hideDateTask: Task<Void, Never>? = nil
    
    @State private var highlightedMessageId: String? = nil
    @State private var isSearching: Bool = false
    @State private var searchScrollTarget: String?
    
    @State private var isSelecting: Bool = false
    @State private var selectedMessageIds: Set<String> = []
    
    init(familyId: String, searchText: String) {
        self.familyId = familyId
        self.searchText = searchText
        _viewModel = StateObject(wrappedValue: ChatViewModel(familyId: familyId))
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            messageList
            errorBanner
            uploadProgress
            typingBanner
            if viewModel.isEditing {
                editingBar
            }
            if viewModel.isReplying {
                replyBar
            }
            if isSelecting {
                ZStack(alignment: .bottom) {
                    selectionBar
                    
                    if showDeleteBar {
                        deleteOverlayBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(100)
                    }
                }
            } else {
                Divider()
                inputBar
            }
        }
        .onAppear {
            viewModel.bind(modelContext: modelContext)
            viewModel.startListening()
            Task {
                await CountersService.shared.reset(familyId: familyId, field: .chat)
                await MainActor.run {
                    BadgeManager.shared.clearChat()
                }
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .toolbar {
            // trashButton
            if isSelecting {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Annulla") { resetSelection() }
                }
            }
        }
        .confirmationDialog(
            "Svuota chat",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Elimina tutti i messaggi", role: .destructive) { viewModel.clearChat() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Questa azione eliminerà tutti i messaggi per tutti i membri della famiglia. Non è reversibile.")
        }
        .sheet(item: $messageForReaction) { msg in
            ReactionPickerSheet(message: msg) { emoji in
                viewModel.toggleReaction(emoji, on: msg)
            }
            .presentationDetents([.height(120)])
        }
        .photosPicker(
            isPresented: $showMediaPicker,
            selection: $mediaPickerItems,
            maxSelectionCount: 1,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: mediaPickerItems) { _, items in
            guard let item = items.first else { return }
            Task { await handlePickedMedia(item) }
            mediaPickerItems = []
        }
        .sheet(isPresented: $showCamera) { cameraSheet }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url in
                viewModel.sendDocument(url: url)
            }
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Subviews estratte
    
    /// Lista messaggi con scroll, floating pill e freccia in basso.
    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                scrollContent(proxy: proxy)
                floatingDatePill
                scrollToBottomButton(proxy: proxy)
            }
        }
    }
    
    private var editingBar: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3)
                .clipShape(Capsule())
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Modifica messaggio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(viewModel.editingOriginalText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
            
            Button {
                viewModel.cancelEditing()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private func scrollContent(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if viewModel.isLoadingOlder {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Caricamento messaggi…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .id("loadingOlder")       // ← id fisso, non rimbalza
                } else if !viewModel.hasMoreMessages && !viewModel.messages.isEmpty {
                    Text("Inizio della conversazione")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                
                ForEach(groupedMessages, id: \.day) { group in
                    daySeparator(group: group)
                    ForEach(group.messages) { msg in
                        BubbleRowView(
                            msg: msg,
                            proxy: proxy,
                            viewModel: viewModel,
                            messageForReaction: $messageForReaction,
                            highlightedMessageId: $highlightedMessageId,
                            isSelecting: $isSelecting,
                            selectedMessageIds: $selectedMessageIds,
                            searchText: searchText,
                            onScrollAndHighlight: scrollToAndHighlight
                        )
                    }
                }
                Color.clear.frame(height: 1).id("bottom")
            }
            .padding(.vertical, 10)
            .onChange(of: searchScrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
        .coordinateSpace(name: "scrollArea")
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height
        } action: { _, distanceFromBottom in
            withAnimation(.easeInOut(duration: 0.2)) {
                showScrollToBottom = distanceFromBottom > 200
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { oldOffset, newOffset in
            // ✅ Carica older solo se si sta scrollando VERSO l'alto (offset decresce)
            // e solo se non è già in caricamento — evita trigger ripetuti
            if newOffset < 80 && newOffset < oldOffset && !viewModel.isLoadingOlder {
                viewModel.loadOlderMessages()
            }
        }
        // ✅ Scroll in fondo SOLO quando arriva un nuovo messaggio in coda (non durante la paginazione)
        .onChange(of: viewModel.messages.last?.id) { _, lastId in
            guard lastId != nil, !viewModel.isPaginating else { return }
            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            viewModel.markVisibleMessagesAsRead()
        }
        .onAppear {
            proxy.scrollTo("bottom", anchor: .bottom)
            viewModel.markVisibleMessagesAsRead()
        }
    }
    
    /// Separatore giorno con rilevamento posizione per la floating pill.
    private func daySeparator(group: DayGroup) -> some View {
        ChatDaySeparator(label: group.label)
            .id("day-\(group.day)")
            .background(daySeparatorDetector(label: group.label))
    }
    
    private func daySeparatorDetector(label: String) -> some View {
        GeometryReader { geo -> Color in
            let frame = geo.frame(in: .named("scrollArea"))
            if frame.minY < 60 && frame.minY > -frame.height {
                DispatchQueue.main.async { showFloatingPill(label: label) }
            }
            return Color.clear
        }
    }
    
    private struct BubbleRowView: View {
        let msg: KBChatMessage
        let proxy: ScrollViewProxy
        @ObservedObject var viewModel: ChatViewModel
        @Binding var messageForReaction: KBChatMessage?
        @Binding var highlightedMessageId: String?
        @Binding var isSelecting: Bool
        @Binding var selectedMessageIds: Set<String>
        let searchText: String
        let onScrollAndHighlight: (String, ScrollViewProxy) -> Void
        
        var body: some View {
            let repliedTo = viewModel.messages.first(where: { $0.id == msg.replyToId })
            let uid = Auth.auth().currentUser?.uid ?? ""
            let isOwn = msg.senderId == uid
            let canAct = isOwn && viewModel.canEditOrDelete(msg)
            
            HStack(spacing: 8) {
                
                if isSelecting {
                    Image(systemName: selectedMessageIds.contains(msg.id)
                          ? "checkmark.circle.fill"
                          : "circle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        selectedMessageIds.contains(msg.id) ? Color.accentColor : .secondary
                    )
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleSelection(msg.id)
                    }
                }
                ChatBubble(
                    message: msg,
                    isOwn: isOwn,
                    currentUID: uid,
                    onReactionTap: {
                        emoji in viewModel.toggleReaction(emoji, on: msg)
                    },
                    onLongPress: { messageForReaction = msg },
                    onEdit: canAct ? { viewModel.startEditing(msg) } : nil,
                    onDelete: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isSelecting = true
                        selectedMessageIds.insert(msg.id)
                    },
                    onReply: { viewModel.startReply(to: msg) },
                    repliedTo: repliedTo,
                    onReplyContextTap: {
                        guard let rid = msg.replyToId else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            onScrollAndHighlight(rid, proxy)
                        }
                    },
                    highlightedMessageId: highlightedMessageId,
                    searchText: searchText
                )
                .id(msg.id)
            }
        }
        
        private func toggleSelection(_ id: String) {
            if selectedMessageIds.contains(id) {
                selectedMessageIds.remove(id)
            } else {
                selectedMessageIds.insert(id)
            }
        }
    }
    
    private func scrollToAndHighlight(_ id: String, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: .center)
        }
        
        // Flash highlight
        highlightedMessageId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            // evita di spegnere un highlight diverso se nel frattempo l’utente ha tappato altro
            if highlightedMessageId == id {
                highlightedMessageId = nil
            }
        }
    }
    
    // MARK: - Reply bar (WhatsApp style)
    
    private var replyBar: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Rispondi a \(viewModel.replyingPreviewName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                
                replyPreviewLine
            }
            
            Spacer(minLength: 0)
            
            Button { viewModel.cancelReply() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
        .fixedSize(horizontal: false, vertical: true)
    }
    
    @ViewBuilder
    private var replyPreviewLine: some View {
        let kind = viewModel.replyingPreviewKind
        
        switch kind {
        case .photo:
            HStack(spacing: 8) {
                if let urlString = viewModel.replyingPreviewMediaURL,
                   let url = URL(string: urlString) {
                    // usa la tua CachedAsyncImage già in progetto
                    CachedAsyncImage(url: url, contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemBackground))
                        .frame(width: 36, height: 36)
                }
                
                Text("Foto")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
        case .audio:
            Text(viewModel.replyingPreviewText) // già "Messaggio vocale • 0:12"
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
        case .video:
            Text(viewModel.replyingPreviewText.isEmpty ? "🎬 Video" : viewModel.replyingPreviewText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
        case .text, .none:
            Text(viewModel.replyingPreviewText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
        case .document:
            HStack(spacing: 6) {
                Image(systemName: "doc.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(viewModel.replyingPreviewText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .location:
            HStack(spacing: 8) {
                if let lat = viewModel.replyingPreviewLatitude,
                   let lon = viewModel.replyingPreviewLongitude {
                    MiniLocationThumb(latitude: lat, longitude: lon)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemBackground))
                        .frame(width: 36, height: 36)
                }
                
                Text("Posizione condivisa")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
    struct MiniLocationThumb: View {
        let latitude: Double
        let longitude: Double
        
        private var center: CLLocationCoordinate2D {
            .init(latitude: latitude, longitude: longitude)
        }
        
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
    
    /// Pill data flottante stile WhatsApp.
    @ViewBuilder
    private var floatingDatePill: some View {
        if showFloatingDate {
            Text(floatingDateLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 1)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .animation(.easeInOut(duration: 0.2), value: showFloatingDate)
                .allowsHitTesting(false)
                .zIndex(10)
        }
    }
    
    /// Freccia "vai in fondo" stile WhatsApp.
    @ViewBuilder
    private func scrollToBottomButton(proxy: ScrollViewProxy) -> some View {
        if showScrollToBottom {
            VStack {
                Spacer()
                Button {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                }
                .padding(.bottom, 10)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
            .zIndex(9)
        }
    }
    
    @ViewBuilder
    private var errorBanner: some View {
        if let error = viewModel.errorText {
            Text(error)
                .font(.caption).foregroundStyle(.red)
                .padding(.horizontal).padding(.top, 4)
        }
    }
    
    @ViewBuilder
    private var uploadProgress: some View {
        if viewModel.isCompressingMedia {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Compressione in corso…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if viewModel.isUploadingMedia {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Invio in corso…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.uploadProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: viewModel.uploadProgress)
                    .tint(.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private var typingBanner: some View {
        if !viewModel.typingUsers.isEmpty {
            HStack(spacing: 6) {
                // Tre puntini animati
                TypingDotsView()
                Text(typingLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.2), value: viewModel.typingUsers)
        }
    }
    
    private var typingLabel: String {
        switch viewModel.typingUsers.count {
        case 1: return "\(viewModel.typingUsers[0]) sta scrivendo…"
        case 2: return "\(viewModel.typingUsers[0]) e \(viewModel.typingUsers[1]) stanno scrivendo…"
        default: return "Tutti stanno scrivendo…"
        }
    }
    
    private var inputBar: some View {
        ChatInputBar(
            text: $viewModel.inputText,
            isRecording: viewModel.isRecording,
            recordingDuration: viewModel.recordingDuration,
            isSending: viewModel.isSending,
            onSendText: { viewModel.sendText() },
            onStartRecord: { viewModel.startRecording() },
            onStopRecord: { viewModel.stopAndSendRecording() },
            onCancelRecord: { viewModel.cancelRecording() },
            onMediaTap: { showMediaPicker = true },
            onCameraTap: { showCamera = true },
            onDocumentTap: { showDocumentPicker = true },
            onTextChange: { viewModel.userIsTyping() },
            onLocationTap: { showLocationSheet = true }
        )
        .sheet(isPresented: $showLocationSheet) {
            LocationPickerSheet { lat, lon in
                viewModel.sendLocation(latitude: lat, longitude: lon)  // ✅ qui
            }
        }
    }
    
    private func sendLocation() {
        ChatLocationService.shared.requestLocation { location in
            guard let location else { return }
            
            viewModel.sendLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
    }
    
    private var deleteOverlayBar: some View {
        VStack(spacing: 0) {
            
            HStack {
                Text("Eliminare \(selectedMessageIds.count) messaggi?")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        showDeleteBar = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            Divider()
            
            VStack(spacing: 0) {
                
                Button {
                    deleteForMe()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        showDeleteBar = false
                    }
                } label: {
                    HStack {
                        Text("Elimina \(selectedMessageIds.count) messaggi per me")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                
                if canDeleteForEveryone {
                    Divider()
                    
                    Button {
                        deleteForEveryone()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            showDeleteBar = false
                        }
                    } label: {
                        HStack {
                            Text("Elimina \(selectedMessageIds.count) messaggi per tutti")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: -2)
        .padding(.horizontal, 12)
        .padding(.bottom, 8) // sta “sopra” la selection bar
    }
    
    private var selectionBar: some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    showDeleteBar = true
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(selectedMessageIds.isEmpty)
            
            Spacer()
            
            Text("\(selectedMessageIds.count) selezionati")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }
    
    private var canDeleteForEveryone: Bool {
        
        guard !selectedMessageIds.isEmpty else { return false }
        
        let selected = viewModel.messages.filter {
            selectedMessageIds.contains($0.id)
        }
        
        // tutti devono essere miei
        guard selected.allSatisfy({ $0.senderId == currentUID }) else {
            return false
        }
        
        let now = Date()
        
        // tutti entro 5 minuti
        return selected.allSatisfy {
            now.timeIntervalSince($0.createdAt) <= 300
        }
    }
    
    private func deleteForMe() {
        viewModel.deleteMessagesLocally(ids: Array(selectedMessageIds))
        resetSelection()
    }
    
    private func deleteForEveryone() {
        viewModel.deleteMessagesRemotely(ids: Array(selectedMessageIds))
        resetSelection()
    }
    
    private func resetSelection() {
        selectedMessageIds.removeAll()
        isSelecting = false
        showDeleteBar = false
    }
    
    private var trashButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showClearConfirm = true } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .disabled(viewModel.messages.isEmpty)
        }
    }
    
    private var cameraSheet: some View {
        CameraPicker(image: $cameraImage, videoURL: $cameraVideoURL)
            .ignoresSafeArea()
            .onDisappear {
                if let img = cameraImage, let data = img.jpegData(compressionQuality: 0.85) {
                    viewModel.sendMedia(data: data, type: .photo)
                } else if let url = cameraVideoURL, let data = try? Data(contentsOf: url) {
                    viewModel.sendMedia(data: data, type: .video)
                }
                cameraImage = nil
                cameraVideoURL = nil
            }
    }
    
    // MARK: - Helpers
    
    private var currentUID: String {
        Auth.auth().currentUser?.uid ?? ""
    }
    
    // MARK: - Raggruppamento per giorno
    
    struct DayGroup: Identifiable {
        let day: String
        let label: String
        let messages: [KBChatMessage]
        var id: String { day }
    }
    
    private static func dayLabel(for date: Date, daysAgo: Int) -> String {
        switch daysAgo {
        case 0:  return "Oggi"
        case 1:  return "Ieri"
        case 2...6: return date.formatted(.dateTime.weekday(.wide)).capitalized
        default: return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).capitalized
        }
    }
    
    var groupedMessages: [DayGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let baseMessages = searchText.isEmpty
        ? viewModel.messages
        : viewModel.messages.filter {
            ($0.text ?? "").localizedCaseInsensitiveContains(searchText)
        }
        
        let grouped = Dictionary(grouping: baseMessages) { msg in
            calendar.startOfDay(for: msg.createdAt)
        }
        
        return grouped.keys.sorted().map { day in
            let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            let label = Self.dayLabel(for: day, daysAgo: daysAgo)
            return DayGroup(
                day: formatter.string(from: day),
                label: label,
                messages: grouped[day]!.sorted { $0.createdAt < $1.createdAt }
            )
        }
    }
    
    // MARK: - Floating pill
    
    private func showFloatingPill(label: String) {
        floatingDateLabel = label
        withAnimation(.easeInOut(duration: 0.2)) { showFloatingDate = true }
        hideDateTask?.cancel()
        hideDateTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) { showFloatingDate = false }
            }
        }
    }
    
    private func handlePickedMedia(_ item: PhotosPickerItem) async {
        // Controlla su TUTTI i contentTypes, non solo il primo
        let isVideo = item.supportedContentTypes.contains {
            $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .mpeg4Movie)
        }
        let type: KBChatMessageType = isVideo ? .video : .photo
        
        if let data = try? await item.loadTransferable(type: Data.self) {
            viewModel.sendMedia(data: data, type: type)
        }
    }
}

// MARK: - TypingDotsView

private struct TypingDotsView: View {
    @State private var phase = 0
    
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase == i ? 1.4 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - ChatDaySeparator

private struct ChatDaySeparator: View {
    let label: String
    
    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

// MARK: - CameraPicker

private struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var videoURL: URL?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.mediaTypes = ["public.image", "public.movie"]
        p.cameraCaptureMode = .photo
        p.videoQuality = .typeHigh
        p.videoMaximumDuration = 60
        p.delegate = context.coordinator
        return p
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            } else if let url = info[.mediaURL] as? URL {
                parent.videoURL = url
            }
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - DocumentPicker

private struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
    }
}
