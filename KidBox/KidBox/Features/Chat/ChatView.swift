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
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    @State private var searchText: String = ""
    @State private var isSearchPresented: Bool = false
    
    private var familyId: String { families.first?.id ?? "" }
    
    var body: some View {
        Group {
            if familyId.isEmpty {
                emptyNoFamily
            } else {
                ChatConversationView(familyId: familyId, searchText: searchText)
            }
        }
        .navigationTitle("Chat famiglia")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { isSearchPresented = true } label: {
                    Image(systemName: "magnifyingglass")
                }
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
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var viewModel: ChatViewModel
    @State private var dayGroups: [ChatDayGroup] = []
    @FocusState private var isInputFocused: Bool
    @State private var messageForSave: KBChatMessage? = nil
    
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
    
    // Delete
    @State private var showDeleteConfirm: Bool = false
    @State private var showDeleteBar: Bool = false
    
    // Highlight / search
    @State private var highlightedMessageId: String? = nil
    @State private var isSearching: Bool = false
    @State private var searchScrollTarget: String?
    
    // Selezione multipla
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
                inputBar
            }
        }
        .background(backgroundColor)
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
        .task(id: coordinator.pendingShareImagePath) {
            guard let filePath = coordinator.pendingShareImagePath else { return }
            coordinator.pendingShareImagePath = nil
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
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
        .onChange(of: searchText) { _, _ in dayGroups = buildGroups() }
        .onChange(of: viewModel.messages.last?.id) { _, _ in
            guard !viewModel.isPaginating else { return }
            dayGroups = buildGroups()
        }
        .onChange(of: viewModel.messages.count) { _, _ in
            guard !viewModel.isPaginating else { return }
            dayGroups = buildGroups()
        }
        .sheet(isPresented: $showCamera) { cameraSheet }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url in viewModel.sendDocument(url: url) }
                .ignoresSafeArea()
        }
        .sheet(item: $messageForSave) { msg in
            ChatSaveSheet(
                message: msg,
                onSelect: { action in handleSaveAction(action) },
                onDismiss: { messageForSave = nil }
            )
            .presentationDetents([.medium, .large])
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
        switch daysAgo {
        case 0: return "Oggi"
        case 1: return "Ieri"
        case 2...6:
            return date.formatted(
                Date.FormatStyle().weekday(.wide).locale(Locale(identifier: "it_IT"))
            ).capitalized
        default:
            return date.formatted(
                Date.FormatStyle()
                    .weekday(.wide).day().month(.abbreviated)
                    .locale(Locale(identifier: "it_IT"))
            ).capitalized
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
            coordinator.navigate(to: .notesHome(familyId: familyId))
            Task { @MainActor in
                let uid = Auth.auth().currentUser?.uid ?? ""
                let displayName = Auth.auth().currentUser?.displayName ?? ""
                let note = KBNote(
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
                let store = NotesRemoteStore()
                try? await store.upsert(note: note)
            }
            
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
                    updatedAt: Date(),
                    updatedBy: uid
                )
                try? await DocumentRemoteStore().upsert(dto: dto)
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
        ChatInputBar(
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
            onMediaTap: { showMediaPicker = true },
            onCameraTap: { showCamera = true },
            onDocumentTap: { showDocumentPicker = true },
            onTextChange: { viewModel.userIsTyping() },
            onLocationTap: { showLocationSheet = true }
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
    
    private func handlePickedMedia(_ item: PhotosPickerItem) async {
        let isVideo = item.supportedContentTypes.contains {
            $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .mpeg4Movie)
        }
        let type: KBChatMessageType = isVideo ? .video : .photo
        if let data = try? await item.loadTransferable(type: Data.self) {
            viewModel.sendMedia(data: data, type: type)
        }
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
