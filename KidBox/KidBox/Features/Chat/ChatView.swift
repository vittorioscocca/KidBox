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

// MARK: - ChatView (entry point)

struct ChatView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    
    private var familyId: String { families.first?.id ?? "" }
    
    var body: some View {
        Group {
            if familyId.isEmpty {
                emptyNoFamily
            } else {
                ChatConversationView(familyId: familyId)
            }
        }
        .navigationTitle("Chat famiglia")
        .navigationBarTitleDisplayMode(.inline)
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
    
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: ChatViewModel
    
    // Media picker
    @State private var showMediaPicker = false
    @State private var mediaPickerItems: [PhotosPickerItem] = []
    
    // Camera
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var cameraVideoURL: URL?
    
    // Reaction picker
    @State private var messageForReaction: KBChatMessage?
    
    // Clear chat
    @State private var showClearConfirm = false
    
    // Scroll
    @State private var showScrollToBottom = false
    
    // Date pill floating (stile WhatsApp)
    @State private var floatingDateLabel: String = ""
    @State private var showFloatingDate: Bool = false
    @State private var hideDateTask: Task<Void, Never>? = nil
    
    init(familyId: String) {
        self.familyId = familyId
        _viewModel = StateObject(wrappedValue: ChatViewModel(familyId: familyId))
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            messageList
            errorBanner
            uploadProgress
            Divider()
            inputBar
        }
        .onAppear {
            viewModel.bind(modelContext: modelContext)
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .toolbar { trashButton }
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
    
    private func scrollContent(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(groupedMessages, id: \.day) { group in
                    daySeparator(group: group)
                    ForEach(group.messages) { msg in
                        bubbleRow(msg: msg)
                    }
                }
                Color.clear.frame(height: 1).id("bottom")
            }
            .padding(.vertical, 10)
        }
        .coordinateSpace(name: "scrollArea")
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height
        } action: { _, distanceFromBottom in
            withAnimation(.easeInOut(duration: 0.2)) {
                showScrollToBottom = distanceFromBottom > 200
            }
        }
        .onChange(of: viewModel.messages.count) { _, _ in
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
    
    /// Singola bolla messaggio.
    private func bubbleRow(msg: KBChatMessage) -> some View {
        ChatBubble(
            message: msg,
            isOwn: msg.senderId == currentUID,
            onReactionTap: { emoji in viewModel.toggleReaction(emoji, on: msg) },
            onLongPress: { messageForReaction = msg },
            onDelete: { viewModel.deleteMessage(msg) }
        )
        .id(msg.id)
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
        if viewModel.isUploadingMedia {
            ProgressView(value: viewModel.uploadProgress)
                .tint(.accentColor)
                .padding(.horizontal)
                .padding(.top, 4)
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
            onCameraTap: { showCamera = true }
        )
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
        
        let grouped = Dictionary(grouping: viewModel.messages) { msg in
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
        if let data = try? await item.loadTransferable(type: Data.self) {
            let type: KBChatMessageType = item.supportedContentTypes
                .first?.identifier.contains("video") == true ? .video : .photo
            viewModel.sendMedia(data: data, type: type)
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
