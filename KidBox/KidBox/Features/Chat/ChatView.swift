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

/// Entry point della chat familiare.
/// Viene chiamata da HomeView tramite coordinator.navigate(to: .calendar) (provvisorio).
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

/// La conversazione vera e propria.
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
    
    // Scroll
    @Namespace private var bottomAnchor
    
    init(familyId: String) {
        self.familyId = familyId
        _viewModel = StateObject(wrappedValue: ChatViewModel(familyId: familyId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // ── Lista messaggi ──────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.messages) { msg in
                            ChatBubble(
                                message: msg,
                                isOwn: msg.senderId == currentUID,
                                onReactionTap: { emoji in
                                    viewModel.toggleReaction(emoji, on: msg)
                                },
                                onLongPress: {
                                    messageForReaction = msg
                                },
                                onDelete: {
                                    viewModel.deleteMessage(msg)
                                }
                            )
                            .id(msg.id)
                        }
                        
                        // Anchor per scroll automatico
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 10)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            
            // ── Errore ──────────────────────────────────────────────────────
            if let error = viewModel.errorText {
                Text(error)
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal).padding(.top, 4)
            }
            
            // ── Upload progress ─────────────────────────────────────────────
            if viewModel.isUploadingMedia {
                ProgressView(value: viewModel.uploadProgress)
                    .tint(.accentColor)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            
            Divider()
            
            // ── Input bar ───────────────────────────────────────────────────
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
        .onAppear {
            viewModel.bind(modelContext: modelContext)
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        // Reaction picker sheet
        .sheet(item: $messageForReaction) { msg in
            ReactionPickerSheet(message: msg) { emoji in
                viewModel.toggleReaction(emoji, on: msg)
            }
            .presentationDetents([.height(120)])
        }
        // Media picker
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
        // Camera
        .sheet(isPresented: $showCamera) {
            CameraPicker(image: $cameraImage, videoURL: $cameraVideoURL)
                .ignoresSafeArea()
                .onDisappear {
                    if let img = cameraImage,
                       let data = img.jpegData(compressionQuality: 0.85) {
                        // ✅ Foto
                        viewModel.sendMedia(data: data, type: .photo)
                    } else if let url = cameraVideoURL,
                              let data = try? Data(contentsOf: url) {
                        // ✅ Video registrato dalla fotocamera
                        viewModel.sendMedia(data: data, type: .video)
                    }
                    cameraImage = nil
                    cameraVideoURL = nil
                }
        }
    }
    
    // MARK: - Helpers
    
    private var currentUID: String {
        Auth.auth().currentUser?.uid ?? ""
    }
    
    private func handlePickedMedia(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            // Determina tipo dal contentType
            let type: KBChatMessageType = item.supportedContentTypes
                .first?.identifier.contains("video") == true ? .video : .photo
            viewModel.sendMedia(data: data, type: type)
        }
    }
}

// MARK: - CameraPicker

private struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var videoURL: URL?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.mediaTypes = ["public.image", "public.movie"]   // ✅ foto + video
        p.cameraCaptureMode = .photo                       // default foto; hold → video nativo
        p.videoQuality = .typeHigh
        p.videoMaximumDuration = 60                        // max 60s
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
                // ✅ Foto
                parent.image = img
            } else if let url = info[.mediaURL] as? URL {
                // ✅ Video
                parent.videoURL = url
            }
            picker.dismiss(animated: true)
        }
    }
}
