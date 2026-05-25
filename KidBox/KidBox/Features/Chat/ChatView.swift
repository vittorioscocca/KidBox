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

struct GalleryDeleteRequest: Identifiable, Equatable {
    let id = UUID()
    let message: KBChatMessage
    let itemIndex: Int?      // nil se non è mediaGroup
    let forEveryone: Bool
    
    static func == (lhs: GalleryDeleteRequest, rhs: GalleryDeleteRequest) -> Bool {
        lhs.id == rhs.id
    }
}

private struct SelectedContactDraft: Identifiable {
    let id = UUID()
    let payload: ContactPayload
}
// MARK: - ChatView (entry point)

struct ChatView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    @State private var searchText: String = ""
    @State private var isSearchPresented: Bool = false
    @State private var showClearConfirm = false
    @State private var showMediaGallery = false
    @State private var galleryGoToMessageId: String? = nil
    @State private var galleryReplyMessage: KBChatMessage? = nil
    @State private var galleryDeleteRequest: GalleryDeleteRequest? = nil
    
    private var activeFamily: KBFamily? {
        ActiveFamilyResolver.family(from: families, activeFamilyId: coordinator.activeFamilyId)
    }
    
    private var activeFamilyId: String { activeFamily?.id ?? "" }
    
    private var chatNavigationTitle: String {
        let name = activeFamily?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Chat famiglia" : "Chat \(name)"
    }
    
    var body: some View {
        Group {
            if activeFamilyId.isEmpty {
                emptyNoFamily
            } else {
                ChatConversationView(
                    familyId: activeFamilyId,
                    searchText: searchText,
                    showClearConfirm: $showClearConfirm,
                    goToMessageId: $galleryGoToMessageId,
                    replyFromGallery: $galleryReplyMessage,
                    deleteFromGallery: $galleryDeleteRequest
                )
                .id(activeFamilyId)
            }
        }
        .navigationTitle(chatNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isSearchPresented {
                    Button {
                        searchText = ""
                        isSearchPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                } else {
                    Menu {
                        Button {
                            isSearchPresented = true
                        } label: {
                            Label("Cerca", systemImage: "magnifyingglass")
                        }
                        
                        Button {
                            showMediaGallery = true
                        } label: {
                            Label("Media, link e documenti", systemImage: "photo.on.rectangle")
                        }
                        
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("Svuota chat", systemImage: "trash")
                        }
                        
                        
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
        .sheet(isPresented: $showMediaGallery) {
            ChatMediaGalleryView(
                familyId: activeFamilyId,
                onGoToMessage: { msgId in
                    showMediaGallery = false
                    galleryGoToMessageId = msgId
                },
                onReply: { msg in
                    showMediaGallery = false
                    galleryReplyMessage = msg
                },
                onDelete: { item, forEveryone in
                    let itemIndex: Int? = item.message.type == .mediaGroup
                    ? Int(item.id.split(separator: "_").last ?? "")
                    : nil
                    galleryDeleteRequest = GalleryDeleteRequest(
                        message: item.message,
                        itemIndex: itemIndex,
                        forEveryone: forEveryone
                    )
                },
                onClose: { showMediaGallery = false }
            )
            .environment(\.modelContext, modelContext)
#if targetEnvironment(macCatalyst)
            .frame(minWidth: 640, minHeight: 520)
#endif
        }
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
        .background(backgroundColor)
    }
}

// MARK: - DayGroup

struct ChatDayGroup: Identifiable {
    let day: String
    let label: String
    let messages: [KBChatMessage]
    var id: String { day }
}

// MARK: - ChatMessageList

private struct ChatMessageList: View {
    
    let dayGroups: [ChatDayGroup]
    let isLoadingOlder: Bool
    let hasMoreMessages: Bool
    let messagesIsEmpty: Bool
    let lastMessageId: String?
    let isPaginating: Bool
    let searchScrollTarget: String?
    
    @Binding var messageForReaction: KBChatMessage?
    @Binding var highlightedMessageId: String?
    @Binding var isSelecting: Bool
    @Binding var selectedMessageIds: Set<String>
    
    let searchText: String
    
    let onNearTop: () -> Void
    let onMarkRead: () -> Void
    let onBubbleRow: (KBChatMessage, ScrollViewProxy) -> BubbleRowView
    
    @State private var showScrollToBottom = false
    @State private var floatingDateLabel: String = ""
    @State private var showFloatingDate: Bool = false
    @State private var hideDateTask: Task<Void, Never>? = nil
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                scrollBody(proxy: proxy)
                floatingDatePill
                scrollToBottomButton(proxy: proxy)
            }
        }
    }
    
    private func scrollBody(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if isLoadingOlder {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Caricamento messaggi…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .id("loadingOlder")
                } else if !hasMoreMessages && !messagesIsEmpty {
                    Text("Inizio della conversazione")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                
                ForEach(dayGroups) { group in
                    daySeparator(group: group)
                    ForEach(group.messages) { msg in
                        onBubbleRow(msg, proxy).equatable()
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
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height > 200
        } action: { _, shouldShow in
            withAnimation(.easeInOut(duration: 0.2)) {
                showScrollToBottom = shouldShow
            }
        }
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y < 80
        } action: { wasNearTop, isNearTop in
            if isNearTop && !wasNearTop { onNearTop() }
        }
        .onChange(of: lastMessageId) { _, id in
            guard id != nil, !isPaginating else { return }
            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            onMarkRead()
        }
        .onAppear {
            proxy.scrollTo("bottom", anchor: .bottom)
            onMarkRead()
        }
    }
    
    private func daySeparator(group: ChatDayGroup) -> some View {
        ChatDaySeparator(label: group.label)
            .id("day-\(group.day)")
            .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                if isVisible { showFloatingPill(label: group.label) }
            }
    }
    
    private func showFloatingPill(label: String) {
        guard floatingDateLabel != label else { return }
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
}

// MARK: - BubbleRowView

struct BubbleRowView: View, Equatable {
    static func == (lhs: BubbleRowView, rhs: BubbleRowView) -> Bool {
        lhs.msg.id == rhs.msg.id &&
        lhs.msg.text == rhs.msg.text &&
        lhs.msg.reactions == rhs.msg.reactions &&
        lhs.msg.syncState == rhs.msg.syncState &&
        lhs.msg.readBy == rhs.msg.readBy &&
        lhs.highlightedMessageId == rhs.highlightedMessageId &&
        lhs.isSelecting == rhs.isSelecting &&
        lhs.selectedMessageIds == rhs.selectedMessageIds
    }
    let msg: KBChatMessage
    let proxy: ScrollViewProxy
    let repliedTo: KBChatMessage?
    let isOwn: Bool
    let canAct: Bool
    @Binding var messageForReaction: KBChatMessage?
    @Binding var highlightedMessageId: String?
    @Binding var isSelecting: Bool
    @Binding var selectedMessageIds: Set<String>
    let searchText: String
    let onScrollAndHighlight: (String, ScrollViewProxy) -> Void
    let onReactionTap: (String) -> Void
    let onEdit: (() -> Void)?
    let onDelete: () -> Void
    let onSaveToApp: () -> Void
    let onReply: () -> Void
    
    var body: some View {
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
                .onTapGesture { toggleSelection(msg.id) }
            }
            ChatBubble(
                message: msg,
                isOwn: isOwn,
                currentUID: Auth.auth().currentUser?.uid ?? "",
                onReactionTap: onReactionTap,
                onLongPress: { messageForReaction = msg },
                onEdit: canAct ? onEdit : nil,
                onDelete: onDelete,
                onSaveToApp: onSaveToApp,
                onReply: onReply,
                repliedTo: repliedTo,
                onReplyContextTap: {
                    guard let rid = msg.replyToId else { return }
                    onScrollAndHighlight(rid, proxy)
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

// MARK: - ChatConversationView

private struct ChatConversationView: View {
    let familyId: String
    let searchText: String
    @Binding private var showClearConfirm: Bool
    @Binding private var goToMessageId: String?
    @Binding private var replyFromGallery: KBChatMessage?
    @Binding private var deleteFromGallery: GalleryDeleteRequest?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var viewModel: ChatViewModel
    @Query private var familyMembers: [KBFamilyMember]
    @State private var dayGroups: [ChatDayGroup] = []
    @FocusState private var isInputFocused: Bool
    @State private var messageForSave: KBChatMessage? = nil
    @State private var isLoadingMedia = false
    
    // MARK: - Theme
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    private var barBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.secondarySystemBackground)
    }
    
    private var pillBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.22, green: 0.22, blue: 0.22)
        : Color(.tertiarySystemBackground)
    }
    
    private var changeHandlers1: some View {
        Color.clear
            .onChange(of: mediaPickerItems) { _, items in handleMediaPickerChange(items) }
            .onChange(of: searchText) { _, _ in dayGroups = buildGroups() }
            .onChange(of: viewModel.messages.last?.id) { _, _ in handleMessagesChange() }
            .onChange(of: viewModel.messages.count) { _, _ in handleMessagesChange() }
    }
    
    private var changeHandlers2: some View {
        Color.clear
            .onChange(of: goToMessageId) { _, msgId in handleGalleryGoToMessage(msgId) }
            .onChange(of: replyFromGallery) { _, msg in handleGalleryReply(msg) }
            .onChange(of: deleteFromGallery) { _, req in handleGalleryDelete(req) }
            .onChange(of: familyMembers.map { "\($0.userId)|\($0.displayName ?? "")" }) { _, _ in
                refreshMentionCandidates()
            }
            .onAppear { refreshMentionCandidates() }
    }

    /// Calcola la lista di candidati alle menzioni a partire dai `KBFamilyMember`
    /// attivi della famiglia, escludendo l'utente corrente (non ha senso citare
    /// se stessi). Mantiene l'ordine alfabetico per stabilità del picker.
    private func refreshMentionCandidates() {
        let myUID = Auth.auth().currentUser?.uid ?? ""
        let candidates: [ChatMentionCandidate] = familyMembers
            .filter { !$0.userId.isEmpty && $0.userId != myUID }
            .compactMap { member in
                let name = (member.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return ChatMentionCandidate(uid: member.userId, displayName: name, photoURL: member.photoURL)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        viewModel.mentionCandidates = candidates
    }
    
    // Media picker
    @State private var showMediaPicker = false
    @State private var mediaPickerItems: [PhotosPickerItem] = []
    struct PendingMediaItem: Identifiable, Equatable {
        let id = UUID()
        let data: Data
        let type: KBChatMessageType
    }
    @State private var pendingGroupItems: [PendingMediaItem] = []
    @State private var showLocationSheet = false
    
    // Camera
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var cameraVideoURL: URL?
    
    // Document picker
    @State private var showDocumentPicker    = false
    @State private var showDocSourceDialog   = false
    @State private var showKidBoxDocPicker   = false
    @State private var showContactPicker     = false
    @State private var selectedContactDraft: SelectedContactDraft?
    
    // Storage upgrade
    @State private var showStorageUpgrade = false
    
    // Reaction picker
    @State private var messageForReaction: KBChatMessage?
    
    // Clear chat
    
    
    // Delete
    @State private var showDeleteConfirm: Bool = false
    @State private var showDeleteBar: Bool = false
    
#if targetEnvironment(macCatalyst)
    // Drag & drop (Mac only)
    @State private var isDragTargeted: Bool = false
#endif
    
    // Highlight / search
    @State private var highlightedMessageId: String? = nil
    @State private var isSearching: Bool = false
    @State private var searchScrollTarget: String?
    
    // Selezione multipla
    @State private var isSelecting: Bool = false
    @State private var selectedMessageIds: Set<String> = []
    
    init(familyId: String,
         searchText: String,
         showClearConfirm: Binding<Bool>,
         goToMessageId: Binding<String?>,
         replyFromGallery: Binding<KBChatMessage?>,
         deleteFromGallery: Binding<GalleryDeleteRequest?>) {
        self.familyId = familyId
        self.searchText = searchText
        self._showClearConfirm = showClearConfirm
        self._goToMessageId = goToMessageId
        self._replyFromGallery = replyFromGallery
        _viewModel = StateObject(wrappedValue: ChatViewModel(familyId: familyId))
        self._deleteFromGallery = deleteFromGallery
        // Filtra i membri della famiglia attiva — solo non eliminati, così il
        // picker delle menzioni mostra solo chi effettivamente fa parte della chat.
        _familyMembers = Query(
            filter: #Predicate<KBFamilyMember> {
                $0.familyId == familyId && $0.isDeleted == false
            }
        )
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            ChatMessageList(
                dayGroups: dayGroups,
                isLoadingOlder: viewModel.isLoadingOlder,
                hasMoreMessages: viewModel.hasMoreMessages,
                messagesIsEmpty: viewModel.messages.isEmpty,
                lastMessageId: viewModel.messages.last?.id,
                isPaginating: viewModel.isPaginating,
                searchScrollTarget: searchScrollTarget,
                messageForReaction: $messageForReaction,
                highlightedMessageId: $highlightedMessageId,
                isSelecting: $isSelecting,
                selectedMessageIds: $selectedMessageIds,
                searchText: searchText,
                onNearTop: {
                    if !viewModel.isLoadingOlder { viewModel.loadOlderMessages() }
                },
                onMarkRead: {
                    viewModel.markVisibleMessagesAsRead()
                },
                onBubbleRow: { msg, proxy in
                    makeBubbleRow(msg: msg, proxy: proxy)
                }
            )
            .contentShape(Rectangle())
            .onTapGesture { isInputFocused = false }
            .scrollDismissesKeyboard(.interactively)
            
            errorBanner
            uploadProgress
            typingBanner
            
            if viewModel.isEditing { editingBar }
            if viewModel.isReplying { replyBar }
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
                if isLoadingMedia {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Caricamento media…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                mediaGroupPreviewStrip
                inputBar
            }
        }
        .background(backgroundColor)
#if targetEnvironment(macCatalyst)
        .overlay {
            if isDragTargeted {
                ZStack {
                    Color.accentColor.opacity(0.12).ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentColor)
                        Text("Rilascia per allegare")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
        .onDrop(of: [.image, .video, .movie, .fileURL, .url, .data], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
#endif
        .environmentObject(LinkPreviewStore.shared)
        .onAppear {
            BadgeManager.shared.activeSections.insert("chat")
            viewModel.bind(modelContext: modelContext)
            viewModel.startListening()
            dayGroups = buildGroups()
            Task {
                await CountersService.shared.reset(familyId: familyId, field: .chat)
                await MainActor.run { BadgeManager.shared.clearChat() }
            }
            if let text = coordinator.pendingShareText {
                coordinator.pendingShareText = nil
                viewModel.inputText = text
            }
        }
        .onReceive(coordinator.$pendingShareVideoPath.compactMap { $0 }) { path in
            coordinator.pendingShareVideoPath = nil
            let url = URL(fileURLWithPath: path)
            Task { await viewModel.sendVideo(from: url) }
        }
        .task(id: coordinator.pendingChatMentionMessageId) {
            guard let msgId = coordinator.pendingChatMentionMessageId else { return }
            // Aspetta che i messaggi siano caricati e la lista sia montata.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            coordinator.pendingChatMentionMessageId = nil
            await MainActor.run {
                searchScrollTarget = msgId
                highlightedMessageId = msgId
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    if highlightedMessageId == msgId { highlightedMessageId = nil }
                }
            }
        }
        .task(id: coordinator.pendingChatDocumentURL) {
            guard let url = coordinator.pendingChatDocumentURL else { return }
            // Piccolo delay per assicurarsi che ChatView sia mounted
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            coordinator.pendingChatDocumentURL = nil
            viewModel.sendDocument(url: url)
        }
        .task(id: coordinator.pendingShareImagePath) {
            guard let filePath = coordinator.pendingShareImagePath else { return }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            coordinator.pendingShareImagePath = nil
            viewModel.resetUploadStateIfStuck()
            let fileURL = URL(fileURLWithPath: filePath)
            let ext = fileURL.pathExtension.lowercased()
            guard let data = try? Data(contentsOf: fileURL) else {
                KBLog.data.kbError("ShareChat: impossibile leggere il file path=\(filePath)")
                return
            }
            let imageExts = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"]
            let videoExts = ["mp4", "mov", "m4v"]
            if imageExts.contains(ext) {
                viewModel.sendMedia(data: data, type: .photo)
            } else if videoExts.contains(ext) {
                viewModel.sendMedia(data: data, type: .video)
            } else {
                viewModel.sendDocument(url: fileURL)
            }
            try? FileManager.default.removeItem(at: fileURL)
        }
        .onDisappear {
            viewModel.stopListening()
            BadgeManager.shared.activeSections.remove("chat")
        }
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Annulla") { resetSelection() }
                }
            }
        }
        .confirmationDialog("Svuota chat", isPresented: $showClearConfirm, titleVisibility: .visible) {
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
        // MODIFICATO: maxSelectionCount 1 → 10
        .photosPicker(
            isPresented: $showMediaPicker,
            selection: $mediaPickerItems,
            maxSelectionCount: 10,
            matching: .any(of: [.images, .videos])
        )
        .background(changeHandlers1)
        .background(changeHandlers2)
        .sheet(isPresented: $showCamera) { cameraSheet }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url in viewModel.sendDocument(url: url) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showDocSourceDialog) {
            ChatDocumentSourcePickerSheet(
                tint: KBTheme.bubbleTint,
                onPhoneDocument: {
                    showDocSourceDialog = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showDocumentPicker = true
                    }
                },
                onKidBoxDocument: {
                    showDocSourceDialog = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showKidBoxDocPicker = true
                    }
                }
            )
        }
        .sheet(isPresented: $showKidBoxDocPicker) {
            KidBoxDocumentPickerSheet(familyId: familyId) { url in
                viewModel.sendDocument(url: url)
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPickerRepresentable(
                onPick: { payload in
                    showContactPicker = false
                    selectedContactDraft = SelectedContactDraft(payload: payload)
                },
                onCancel: { showContactPicker = false }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $selectedContactDraft) { draft in
            ContactPreviewSheet(
                payload: draft.payload,
                onSend: {
                    viewModel.sendContact(draft.payload)
                    selectedContactDraft = nil
                },
                onCancel: {
                    selectedContactDraft = nil
                }
            )
            .presentationDetents([.medium])
        }
        .storageUpgradeSheet($showStorageUpgrade)
        .sheet(item: $messageForSave) { msg in
            ChatSaveSheet(
                message: msg,
                onSelect: { action in handleSaveAction(action) },
                onDismiss: { messageForSave = nil }
            )
            .presentationDetents([.medium, .large])
        }
    }
    
#if targetEnvironment(macCatalyst)
    // MARK: - Drag & Drop (Mac only)
    //
    // Su Mac Catalyst i file droppati da Finder arrivano come fileURL.
    // NSItemProvider.loadObject(ofClass: URL.self) è il modo più affidabile
    // per ricevere il path del file, poi distinguiamo per estensione.
    // loadDataRepresentation per le immagini è un fallback se il file URL non funziona.
    
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            
            // Strategia primaria: prova sempre a caricare come file URL
            // (funziona per tutti i tipi droppati da Finder su Mac)
            if provider.hasItemConformingToTypeIdentifier("public.file-url") ||
                provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url, error == nil else { return }
                    // Richiedi accesso al file (necessario su Mac Catalyst)
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    
                    let ext = url.pathExtension.lowercased()
                    let imageExts = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff"]
                    let videoExts = ["mp4", "mov", "m4v", "avi", "mkv"]
                    
                    if imageExts.contains(ext) {
                        guard let data = try? Data(contentsOf: url) else { return }
                        DispatchQueue.main.async {
                            checkUploadAllowed(modelContext: modelContext, familyId: familyId, showUpgrade: $showStorageUpgrade) {
                                let item = PendingMediaItem(data: data, type: .photo)
                                if pendingGroupItems.isEmpty {
                                    viewModel.sendMedia(data: data, type: .photo)
                                } else if pendingGroupItems.count < 10 {
                                    withAnimation { pendingGroupItems.append(item) }
                                }
                            }
                        }
                    } else if videoExts.contains(ext) {
                        // Per i video copiamo in una directory temporanea accessibile
                        let tmpURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.copyItem(at: url, to: tmpURL)
                        DispatchQueue.main.async {
                            checkUploadAllowed(modelContext: modelContext, familyId: familyId, showUpgrade: $showStorageUpgrade) {
                                Task { await viewModel.sendVideo(from: tmpURL) }
                            }
                        }
                    } else {
                        // Documento generico — copiamo in temp per sicurezza
                        let tmpURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.copyItem(at: url, to: tmpURL)
                        DispatchQueue.main.async {
                            checkUploadAllowed(modelContext: modelContext, familyId: familyId, showUpgrade: $showStorageUpgrade) {
                                viewModel.sendDocument(url: tmpURL)
                            }
                        }
                    }
                }
                continue
            }
            
            // Fallback: immagine raw (es. drag da browser)
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async {
                        checkUploadAllowed(modelContext: modelContext, familyId: familyId, showUpgrade: $showStorageUpgrade) {
                            let item = PendingMediaItem(data: data, type: .photo)
                            if pendingGroupItems.isEmpty {
                                viewModel.sendMedia(data: data, type: .photo)
                            } else if pendingGroupItems.count < 10 {
                                withAnimation { pendingGroupItems.append(item) }
                            }
                        }
                    }
                }
            }
        }
    }
#endif
    
    private func handleMediaPickerChange(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task { await handlePickedMediaItems(items) }
        mediaPickerItems = []
    }
    
    private func handleMessagesChange() {
        guard !viewModel.isPaginating else { return }
        dayGroups = buildGroups()
    }
    
    private func handleGalleryGoToMessage(_ msgId: String?) {
        guard let msgId else { return }
        goToMessageId = nil
        searchScrollTarget = msgId
        highlightedMessageId = msgId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if highlightedMessageId == msgId { highlightedMessageId = nil }
        }
    }
    
    private func handleGalleryReply(_ msg: KBChatMessage?) {
        guard let msg else { return }
        replyFromGallery = nil
        viewModel.startReply(to: msg)
    }
    
    private func handleGalleryDelete(_ req: GalleryDeleteRequest?) {
        guard let req else { return }
        deleteFromGallery = nil
        
        if let index = req.itemIndex, req.message.type == .mediaGroup {
            // Rimuove solo il singolo media dal gruppo
            viewModel.removeMediaFromGroup(
                message: req.message,
                itemIndex: index,
                forEveryone: req.forEveryone
            )
        } else {
            if req.forEveryone {
                viewModel.deleteMessagesRemotely(ids: [req.message.id])
            } else {
                viewModel.deleteMessagesLocally(ids: [req.message.id])
            }
        }
    }
    
    private struct MediaGroupPreviewCell: View {
        let item: PendingMediaItem
        let onRemove: () -> Void
        
        /// Thumbnail generata async — usata solo per i video.
        @State private var videoThumbnail: UIImage? = nil
        
        var body: some View {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                
                if item.type == .video {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.55))
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 18, height: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 4)
                    .padding(.bottom, 4)
                }
                
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .padding(2)
            }
            .frame(width: 60, height: 60)
            .task(id: item.id) {
                guard item.type == .video, videoThumbnail == nil else { return }
                videoThumbnail = await generateVideoThumbnail(from: item.data)
            }
        }
        
        @ViewBuilder
        private var thumbnailView: some View {
            // Per i video usa la thumbnail generata da AVAssetImageGenerator;
            // per le foto usa direttamente UIImage(data:).
            let image: UIImage? = item.type == .video
            ? videoThumbnail
            : UIImage(data: item.data)
            
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // Placeholder: spinner per i video in attesa, icona per le foto senza dati
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 60, height: 60)
                    .overlay {
                        if item.type == .video {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "photo").foregroundColor(.secondary)
                        }
                    }
            }
        }
        
        /// Scrive i byte del video in un file temporaneo, estrae il primo frame
        /// con AVAssetImageGenerator e restituisce l'UIImage risultante.
        private func generateVideoThumbnail(from data: Data) async -> UIImage? {
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            do {
                try data.write(to: tmpURL)
            } catch {
                return nil
            }
            defer { try? FileManager.default.removeItem(at: tmpURL) }
            
            let asset = AVURLAsset(url: tmpURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 120, height: 120)
            
            do {
                let (cgImage, _) = try await generator.image(at: .zero)
                return UIImage(cgImage: cgImage)
            } catch {
                return nil
            }
        }
    }
    
    @ViewBuilder
    private var mediaGroupPreviewStrip: some View {
        if !pendingGroupItems.isEmpty {
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(pendingGroupItems) { item in
                                MediaGroupPreviewCell(item: item) {
                                    removePendingItem(item)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    
                    VStack(spacing: 4) {
                        Text("\(pendingGroupItems.count)/10")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                        
                        Button {
                            let snapshot = pendingGroupItems.map { (data: $0.data, type: $0.type) }
                            pendingGroupItems.removeAll()
                            viewModel.sendMediaGroup(items: snapshot)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(KBTheme.bubbleTint)
                        }
                        
                        Button {
                            withAnimation {
                                pendingGroupItems.removeAll()
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                        
                    }
                    .padding(.trailing, 12)
                }
                .background(.ultraThinMaterial)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: pendingGroupItems.count)
        }
    }
    
    private func removePendingItem(_ item: PendingMediaItem) {
        withAnimation {
            pendingGroupItems.removeAll { $0.id == item.id }
        }
    }
    // MARK: - buildGroups
    
    private func buildGroups() -> [ChatDayGroup] {
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
            return ChatDayGroup(
                day: formatter.string(from: day),
                label: label,
                messages: (grouped[day] ?? []).sorted { $0.createdAt < $1.createdAt }
            )
        }
    }
    
    private static func dayLabel(for date: Date, daysAgo: Int) -> String {
        let locale = kbDeviceLocale()
        switch daysAgo {
        case 0, 1:
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.locale = locale
            relativeFormatter.unitsStyle = .full
            let label = relativeFormatter.localizedString(for: date, relativeTo: Date())
            return label.capitalized(with: locale)
        case 2...6:
            return date.formatted(
                Date.FormatStyle().weekday(.wide).locale(locale)
            ).capitalized(with: locale)
        default:
            return date.formatted(
                Date.FormatStyle()
                    .weekday(.wide).day().month(.abbreviated)
                    .locale(locale)
            ).capitalized(with: locale)
        }
    }
    
    // MARK: - makeBubbleRow
    
    private func makeBubbleRow(msg: KBChatMessage, proxy: ScrollViewProxy) -> BubbleRowView {
        let uid = Auth.auth().currentUser?.uid ?? ""
        let isOwn = msg.senderId == uid
        let canAct = isOwn && viewModel.canEditOrDelete(msg)
        return BubbleRowView(
            msg: msg,
            proxy: proxy,
            repliedTo: viewModel.messages.first(where: { $0.id == msg.replyToId }),
            isOwn: isOwn,
            canAct: canAct,
            messageForReaction: $messageForReaction,
            highlightedMessageId: $highlightedMessageId,
            isSelecting: $isSelecting,
            selectedMessageIds: $selectedMessageIds,
            searchText: searchText,
            onScrollAndHighlight: scrollToAndHighlight,
            onReactionTap: { emoji in viewModel.toggleReaction(emoji, on: msg) },
            onEdit: canAct ? { viewModel.startEditing(msg) } : nil,
            onDelete: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isSelecting = true
                selectedMessageIds.insert(msg.id)
            },
            onSaveToApp: { messageForSave = msg },
            onReply: { viewModel.startReply(to: msg) }
        )
    }
    
    // MARK: - scrollToAndHighlight
    
    private func scrollToAndHighlight(_ id: String, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: .center)
        }
        highlightedMessageId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if highlightedMessageId == id { highlightedMessageId = nil }
        }
    }
    
    // MARK: - handlePickedMediaItems (NUOVO — sostituisce handlePickedMedia)
    
    private func handlePickedMediaItems(_ items: [PhotosPickerItem]) async {
        await MainActor.run {
            isLoadingMedia = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        var loaded: [(data: Data, type: KBChatMessageType)] = []
        for item in items {
            let isVideo = item.supportedContentTypes.contains {
                $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .mpeg4Movie)
            }
            let msgType: KBChatMessageType = isVideo ? .video : .photo
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append((data: data, type: msgType))
            }
        }
        await MainActor.run {
            isLoadingMedia = false
            guard !loaded.isEmpty else { return }
            if loaded.count == 1 && pendingGroupItems.isEmpty {
                viewModel.sendMedia(data: loaded[0].data, type: loaded[0].type)
            } else {
                let freeSlots = 10 - pendingGroupItems.count
                let toAdd = loaded
                    .prefix(freeSlots)
                    .map { PendingMediaItem(data: $0.data, type: $0.type) }
                withAnimation {
                    pendingGroupItems.append(contentsOf: toAdd)
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
    
    // MARK: - handleSaveAction
    
    private func handleSaveAction(_ action: KBSaveAction) {
        guard !familyId.isEmpty else { return }
        
        switch action {
            
        case .todo(let title):
            coordinator.pendingShareTodoDraft = AppCoordinator.PendingShareTodoDraft(title: title)
            coordinator.navigate(to: .todo)
            
        case .event(let title, let date):
            coordinator.pendingShareEventDraft = AppCoordinator.PendingShareEventDraft(
                title: title,
                notes: "",
                startDate: date,
                targetFamilyId: familyId
            )
            coordinator.navigate(to: .calendar(familyId: familyId, highlightEventId: nil))
            
        case .grocery(let lines):
            let uid = Auth.auth().currentUser?.uid ?? "local"
            let now = Date()
            for line in lines {
                let item = KBGroceryItem(
                    familyId: familyId, name: line,
                    category: nil, notes: nil,
                    createdAt: now, updatedAt: now,
                    updatedBy: uid, createdBy: uid
                )
                item.syncState = KBSyncState.pendingUpsert
                modelContext.insert(item)
                SyncCenter.shared.enqueueGroceryUpsert(
                    itemId: item.id, familyId: familyId, modelContext: modelContext)
            }
            try? modelContext.save()
            Task { await SyncCenter.shared.flushGrocery(modelContext: modelContext) }
            
        case .note(let title, let body):
            let noteId = UUID().uuidString
            let uid = Auth.auth().currentUser?.uid ?? ""
            let displayName = Auth.auth().currentUser?.displayName ?? ""
            let note = KBNote(
                id: noteId,
                familyId: familyId,
                title: title,
                body: body,
                createdBy: uid,
                createdByName: displayName,
                updatedBy: uid,
                updatedByName: displayName
            )
            note.syncState = .pendingUpsert
            modelContext.insert(note)
            try? modelContext.save()
            SyncCenter.shared.enqueueNoteUpsert(
                noteId: noteId, familyId: familyId, modelContext: modelContext
            )
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            coordinator.navigate(to: .noteDetail(familyId: familyId, noteId: noteId))
            
        case .document(let mediaURL, let fileName):
            coordinator.navigate(to: .documentsHome)
            Task { @MainActor in
                let uid = Auth.auth().currentUser?.uid ?? ""
                let docId = UUID().uuidString
                let mimeType = mimeTypeFromFileName(fileName)
                let storagePath = Self.extractStoragePath(from: mediaURL)
                ?? "families/\(familyId)/chat/\(fileName)"
                
                let doc = KBDocument(
                    id: docId,
                    familyId: familyId,
                    childId: nil,
                    categoryId: nil,
                    title: fileName,
                    fileName: fileName,
                    mimeType: mimeType,
                    fileSize: 0,
                    localPath: nil,
                    storagePath: storagePath,
                    downloadURL: mediaURL,
                    notes: "chat_plain",
                    visibilityScope: KBVisibilityScope.family,
                    visibilityMemberIds: [],
                    createdBy: uid.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedBy: uid
                )
                doc.syncState = .pendingUpsert
                modelContext.insert(doc)
                try? modelContext.save()
                
                let dto = RemoteDocumentDTO(
                    id: docId,
                    familyId: familyId,
                    childId: nil,
                    categoryId: nil,
                    title: fileName,
                    fileName: fileName,
                    mimeType: mimeType,
                    fileSize: 0,
                    storagePath: storagePath,
                    downloadURL: mediaURL,
                    isDeleted: false,
                    notes: "chat_plain",
                    extractedText: nil,
                    extractedTextUpdatedAt: nil,
                    extractionStatusRaw: nil,
                    extractionError: nil,
                    updatedAt: Date(),
                    updatedBy: uid,
                    visibilityScope: KBVisibilityScope.family,
                    visibilityMemberIds: [],
                    createdBy: uid.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                try? await DocumentRemoteStore().upsert(dto: dto)
            }
        case .encryptedMedia(let sourceURL, let fileName, let isVideo):
            let uid = Auth.auth().currentUser?.uid ?? ""
            guard !uid.isEmpty, !familyId.isEmpty else { return }
            
            let alreadyInStack = coordinator.path.contains {
                if case .familyPhotos(let fid) = $0 { return fid == familyId }
                return false
            }
            if !alreadyInStack {
                coordinator.navigate(to: .familyPhotos(familyId: familyId))
            }
            
            Task { @MainActor in
                let photoId  = UUID().uuidString
                let now      = Date()
                let mimeType = isVideo ? "video/mp4" : "image/jpeg"
                let safeFileName = fileName.isEmpty
                ? "\(isVideo ? "video" : "photo")_\(photoId).\(isVideo ? "mp4" : "jpg")"
                : fileName
                
                guard let remoteURL = URL(string: sourceURL),
                      let (mediaData, _) = try? await URLSession.shared.data(from: remoteURL),
                      !mediaData.isEmpty else {
                    KBLog.sync.kbError("handleSaveAction encryptedMedia: download failed url=\(sourceURL)")
                    return
                }
                
                let thumbB64: String?
                var videoDurationSecs: Double? = nil
                
                if isVideo {
                    let tmpURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(photoId)_thumb.mp4")
                    try? mediaData.write(to: tmpURL)
                    
                    async let thumbTask = PhotoRemoteStore.makeVideoThumbnail(url: tmpURL)
                    async let durationTask = VideoCompressor.videoDuration(url: tmpURL)
                    
                    let (primaryThumb, duration) = await (thumbTask, durationTask)
                    
                    if let thumb = primaryThumb {
                        thumbB64 = thumb.base64EncodedString()
                    } else {
                        let fallback = await PhotoRemoteStore.makeVideoThumbnail(from: mediaData)
                        thumbB64 = fallback?.base64EncodedString()
                    }
                    
                    videoDurationSecs = duration
                    try? FileManager.default.removeItem(at: tmpURL)
                } else {
                    thumbB64 = PhotoRemoteStore.makeThumbnail(from: mediaData)?.base64EncodedString()
                }
                
                let storagePath = "families/\(familyId)/photos/\(photoId)/original.enc"
                let photo = KBFamilyPhoto(
                    id: photoId, familyId: familyId,
                    fileName: safeFileName, mimeType: mimeType,
                    fileSize: Int64(mediaData.count),
                    storagePath: storagePath,
                    thumbnailBase64: thumbB64,
                    takenAt: now, createdAt: now, updatedAt: now,
                    createdBy: uid, updatedBy: uid
                )
                photo.syncState = .synced
                photo.videoDurationSeconds = isVideo ? videoDurationSecs : nil
                if !isVideo {
                    let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("KBPhotos", isDirectory: true)
                    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                    let cachedURL = cacheDir.appendingPathComponent("\(photoId).jpg")
                    try? mediaData.write(to: cachedURL, options: .atomic)
                    photo.localPath = cachedURL.path
                }
                modelContext.insert(photo)
                try? modelContext.save()
                
                do {
                    let dto = try await SyncCenter.photoRemote.upload(
                        photoId: photoId, familyId: familyId, userId: uid,
                        imageData: mediaData, fileName: safeFileName,
                        mimeType: mimeType, takenAt: now,
                        caption: nil, albumIds: [],
                        precomputedThumbnailB64: thumbB64,
                        precomputedVideoDurationSeconds: isVideo ? videoDurationSecs : nil,
                        onProgress: { _ in }
                    )
                    photo.downloadURL = dto.downloadURL
                    photo.syncState = .synced
                    if isVideo {
                        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent("KBPhotos", isDirectory: true)
                        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                        let cachedURL = cacheDir.appendingPathComponent("\(photoId).mp4")
                        try? mediaData.write(to: cachedURL, options: .atomic)
                        photo.localPath = cachedURL.path
                    }
                    try? modelContext.save()
                    KBLog.sync.kbInfo("handleSaveAction encryptedMedia: OK photoId=\(photoId) isVideo=\(isVideo)")
                } catch {
                    photo.syncState = .pendingUpsert
                    photo.lastSyncError = error.localizedDescription
                    try? modelContext.save()
                    KBLog.sync.kbError("handleSaveAction encryptedMedia: FAILED photoId=\(photoId) err=\(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func mimeTypeFromFileName(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":  return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png":  return "image/png"
        case "doc":  return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls":  return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "mp4":  return "video/mp4"
        case "mov":  return "video/quicktime"
        default:     return "application/octet-stream"
        }
    }
    
    private static func extractStoragePath(from downloadURL: String) -> String? {
        guard let url = URL(string: downloadURL),
              let pathComponent = url.pathComponents.firstIndex(of: "o").map({ url.pathComponents[$0 + 1] })
        else { return nil }
        return pathComponent.removingPercentEncoding
    }
    
    // MARK: - Editing bar
    
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
            Button { viewModel.cancelEditing() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(barBackground)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    // MARK: - Reply bar
    
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
        .background(barBackground)
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
                    CachedAsyncImage(url: url, contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(pillBackground)
                        .frame(width: 36, height: 36)
                }
                Text("Foto")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        case .audio:
            Text(viewModel.replyingPreviewText)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        case .video:
            HStack(spacing: 8) {
                if let urlString = viewModel.replyingPreviewMediaURL,
                   let url = URL(string: urlString) {
                    VideoThumbnailView(videoURL: url, cacheKey: "reply_" + urlString)
                        .frame(width: 36, height: 36)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(pillBackground)
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: "video.fill").font(.caption))
                }
                Text("Video")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        case .mediaGroup:
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(pillBackground)
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "photo.on.rectangle").font(.caption))
                Text(viewModel.replyingPreviewText)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        case .text, .none:
            HStack(spacing: 8) {
                if let url = ChatLinkDetector.firstURL(in: viewModel.replyingPreviewText) {
                    LinkPreviewThumb(
                        url: url,
                        size: ChatThumbStyle.composerReplySize,
                        corner: ChatThumbStyle.composerCorner
                    )
                }
                Text(viewModel.replyingPreviewText)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        case .document:
            HStack(spacing: 6) {
                Image(systemName: "doc.fill").font(.caption2).foregroundStyle(.secondary)
                Text(viewModel.replyingPreviewText)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        case .contact:
            HStack(spacing: 8) {
                replyContactThumb
                Text(viewModel.replyingPreviewText)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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
                        .fill(pillBackground)
                        .frame(width: 36, height: 36)
                }
                Text("Posizione condivisa")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
    
    @ViewBuilder
    private var replyContactThumb: some View {
        if let data = viewModel.replyingPreviewContactPayload?.avatarData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(pillBackground)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.crop.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                )
        }
    }
    
    // MARK: - Banners
    
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
                ProgressView().controlSize(.small)
                Text("Compressione in corso…")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if viewModel.isUploadingMedia {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Invio in corso…")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.uploadProgress * 100))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                ProgressView(value: viewModel.uploadProgress).tint(.accentColor)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private var typingBanner: some View {
        if !viewModel.typingUsers.isEmpty {
            HStack(spacing: 6) {
                HStack(spacing: -6) {
                    ForEach(viewModel.typingUsers.prefix(3), id: \.self) { name in
                        TypingAvatarView(name: name)
                    }
                }
                TypingDotsView()
                Text(typingLabel)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
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
    
    // MARK: - Input bar
    
    private var inputBar: some View {
        // Le menzioni sono utili solo nelle famiglie con più di due partecipanti
        // (sender + almeno due altri membri). Sotto questa soglia il picker
        // resta vuoto e l'input bar si comporta come prima.
        let candidates = viewModel.canMention ? viewModel.mentionCandidates : []
        return ChatInputBar(
            text: $viewModel.inputText,
            isRecording: viewModel.isRecording,
            isRecordingLocked: viewModel.isRecordingLocked,
            recordingDuration: viewModel.recordingDuration,
            waveformSamples: viewModel.waveformSamples,
            isSending: viewModel.isSending,
            onSendText: { viewModel.sendText() },
            onStartRecord: { viewModel.startRecording() },
            onStopRecord: { viewModel.stopAndSendRecording() },
            onLockRecording: { viewModel.lockRecording() },
            onSendLockedRecording: { viewModel.finishLockedRecording() },
            onCancelLockedRecording: { viewModel.cancelLockedRecording() },
            onCancelRecord: { viewModel.cancelRecording() },
            onMediaTap: {
                checkUploadAllowed(modelContext: modelContext, familyId: familyId, showUpgrade: $showStorageUpgrade) {
                    showMediaPicker = true
                }
            },
            onCameraTap: {
                checkUploadAllowed(modelContext: modelContext, familyId: familyId, showUpgrade: $showStorageUpgrade) {
                    showCamera = true
                }
            },
            onDocumentTap: {
                checkUploadAllowed(modelContext: modelContext, familyId: familyId, showUpgrade: $showStorageUpgrade) {
                    showDocSourceDialog = true
                }
            },
            onContactTap: { showContactPicker = true },
            onTextChange: { viewModel.userIsTyping() },
            onLocationTap: { showLocationSheet = true },
            mentionCandidates: candidates,
            onMentionPicked: { viewModel.registerMention($0) }
        )
        .focused($isInputFocused)
        .sheet(isPresented: $showLocationSheet) {
            LocationPickerSheet { lat, lon in
                viewModel.sendLocation(latitude: lat, longitude: lon)
            }
        }
    }
    
    // MARK: - Delete bars
    
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
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
            
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
                            .font(.body.weight(.semibold)).foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
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
                                .font(.body.weight(.semibold)).foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: -2)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }
    
    // MARK: - Selection helpers
    
    private var currentUID: String { Auth.auth().currentUser?.uid ?? "" }
    
    private var canDeleteForEveryone: Bool {
        guard !selectedMessageIds.isEmpty else { return false }
        let selected = viewModel.messages.filter { selectedMessageIds.contains($0.id) }
        guard selected.allSatisfy({ $0.senderId == currentUID }) else { return false }
        let now = Date()
        return selected.allSatisfy { now.timeIntervalSince($0.createdAt) <= 300 }
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
    
    private var cameraSheet: some View {
        CameraPicker(image: $cameraImage, videoURL: $cameraVideoURL)
            .ignoresSafeArea()
            .onDisappear {
                if let img = cameraImage,
                   let data = img.fixedOrientation().jpegData(compressionQuality: 0.85) {
                    viewModel.sendMedia(data: data, type: .photo)
                } else if let url = cameraVideoURL,
                          let data = try? Data(contentsOf: url) {
                    viewModel.sendMedia(data: data, type: .video)
                }
                cameraImage = nil
                cameraVideoURL = nil
            }
    }
}

// MARK: - Chat document source sheet (2 options)

private struct ChatDocumentSourcePickerSheet: View {
    let tint: Color
    let onPhoneDocument: () -> Void
    let onKidBoxDocument: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 16)
            
            Text("Aggiungi allegato")
                .font(.subheadline.bold())
                .padding(.bottom, 16)
            
            Divider()
            
            sourceRow(
                icon: "doc.fill",
                label: "File del telefono",
                action: onPhoneDocument,
            )
            
            Divider().padding(.leading, 64)
            
            sourceRow(
                icon: "folder.fill.badge.person.crop",
                label: "Da KidBox Documenti",
                action: onKidBoxDocument,
            )
        }
        .presentationDetents([.height(194)])
        .presentationDragIndicator(.visible)
    }
    
    @ViewBuilder
    private func sourceRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
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
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

// MARK: - TypingAvatarView

private struct TypingAvatarView: View {
    let name: String
    
    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1))
        }
        return String(name.prefix(2))
    }
    
    private var color: Color {
        let colors: [Color] = [
            .orange, .purple, .pink, .teal, .indigo, .green, .blue, .red
        ]
        let hash = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        return colors[hash % colors.count]
    }
    
    var body: some View {
        Text(initials.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color, in: Circle())
            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
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
