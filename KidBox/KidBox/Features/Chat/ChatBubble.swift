//
//  ChatBubble.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//


import SwiftUI
import AVKit
import AVFoundation

/// Bubble singolo della chat — gestisce tutti i tipi: testo, audio, foto, video.
struct ChatBubble: View {
    
    let message: KBChatMessage
    let isOwn: Bool
    let onReactionTap: (String) -> Void
    let onLongPress: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    @State private var isPlayingAudio = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var proximityRouter = ProximityAudioRouter()
    @State private var audioDelegate = ChatBubbleAudioDelegate()
    @State private var playbackProgress: Double = 0.0
    @State private var progressTimer: Timer?
    
    @State private var showFullScreenPhoto = false
    @State private var showFullScreenVideo = false
    
    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 2) {
            
            let name = message.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = isOwn ? "Tu" : (name.isEmpty ? "Utente" : name)
            
            Text(displayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, isOwn ? 0 : 46)
                .padding(.trailing, isOwn ? 12 : 0)
            
            HStack(alignment: .bottom, spacing: 8) {
                
                if !isOwn {
                    Circle()
                        .fill(avatarColor)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(message.senderName.prefix(1).uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        )
                }
                
                VStack(alignment: isOwn ? .trailing : .leading, spacing: 6) {
                    bubbleContent
                    bottomRow
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(bubbleBackground)
                .clipShape(bubbleShape)
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
                .overlay(
                    GeometryReader { geo in
                        Color.clear
                            .frame(
                                maxWidth: maxBubbleWidth(containerWidth: geo.size.width),
                                alignment: isOwn ? .trailing : .leading
                            )
                    }
                )
                .contextMenu { contextMenuItems }
                .onLongPressGesture { onLongPress() }
                
                if isOwn { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
            
            if !message.reactions.isEmpty {
                reactionRow
                    .padding(.horizontal, isOwn ? 16 : 54)
            }
        }
        .padding(.vertical, 2)
        .onDisappear {
            // safety: mai lasciare proximity attivo
            proximityRouter.stop()
            stopProgressTimer()
        }
    }
    
    // MARK: - Bubble content
    
    @ViewBuilder
    private var bubbleContent: some View {
        switch message.type {
        case .text:
            Text(message.text ?? "")
                .font(.body)
                .foregroundStyle(isOwn ? .white : .primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
        case .photo:
            photoContent
            
        case .video:
            videoContent
            
        case .audio:
            audioContent
        }
    }
    
    // MARK: - Photo
    
    private var photoContent: some View {
        Group {
            if let urlString = message.mediaURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .scaledToFill()
                            .frame(width: 220, height: 160)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .onTapGesture { showFullScreenPhoto = true }
                            .fullScreenCover(isPresented: $showFullScreenPhoto) {
                                FullScreenPhotoView(url: url)
                            }
                    case .failure:
                        mediaErrorPlaceholder(icon: "photo")
                    default:
                        mediaLoadingPlaceholder
                    }
                }
            } else {
                mediaLoadingPlaceholder
            }
        }
    }
    
    // MARK: - Video
    
    private var videoContent: some View {
        Group {
            if let urlString = message.mediaURL, let url = URL(string: urlString) {
                ZStack(alignment: .bottomTrailing) {
                    
                    // Player inline (muto, senza controlli) — funge da thumbnail animato
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(width: 220, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .disabled(true) // ✅ disabilita i controlli nativi inline
                    
                    // Overlay scuro semi-trasparente
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.25))
                        .frame(width: 220, height: 160)
                        .allowsHitTesting(false)
                    
                    // Tasto play centrale
                    Button { showFullScreenVideo = true } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
                    }
                    .frame(width: 220, height: 160)
                    
                    // Tasto fullscreen angolo in basso a destra
                    Button { showFullScreenVideo = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(8)
                }
                .fullScreenCover(isPresented: $showFullScreenVideo) {
                    FullScreenVideoView(url: url)
                }
            } else {
                mediaLoadingPlaceholder
            }
        }
    }
    
    // MARK: - Audio
    
    /// ✅ Fix: play button ancorato al bordo (sinistra per ricevuti, destra per inviati),
    /// niente più "troppo a destra" / centrato male.
    /// ✅ Fix: waveform stabile (non random ad ogni redraw).
    private var audioContent: some View {
        HStack(spacing: 10) {
            
            playButton // ✅ sempre a sinistra
            
            waveformView
                .frame(width: 130, alignment: .leading) // non si espande
            
            if let dur = message.mediaDurationSeconds {
                Text(formatDuration(dur))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isOwn ? .white.opacity(0.8) : .secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .frame(width: 220, alignment: .leading)
    }
    
    private var playButton: some View {
        Button {
            toggleAudio()
        } label: {
            Image(systemName: isPlayingAudio ? "pause.circle.fill" : "play.circle.fill")
                .font(.title2)
                .foregroundStyle(isOwn ? .white : .accentColor)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlayingAudio ? "Pausa audio" : "Riproduci audio")
    }
    
    private var waveformView: some View {
        HStack(spacing: 2) {
            ForEach(0..<20, id: \.self) { i in
                let barProgress = Double(i) / 20.0
                let isPlayed = barProgress < playbackProgress
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        isOwn
                        ? (isPlayed ? Color.white : Color.white.opacity(0.35))
                        : (isPlayed ? Color.accentColor : Color.accentColor.opacity(0.3))
                    )
                    .frame(width: 5, height: waveformHeight(index: i))
                    .animation(.linear(duration: 0.1), value: playbackProgress)
            }
        }
    }
    
    private func waveformHeight(index: Int) -> CGFloat {
        // Waveform deterministica (stabile tra redraw) basata su message.id + index
        // range 6...20
        let seed = abs((message.id.hashValue ^ (index &* 31)) % 15) // 0..14
        return CGFloat(6 + seed) // 6..20
    }
    
    // MARK: - Bottom row
    
    private var bottomRow: some View {
        HStack(spacing: 4) {
            Text(message.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
            
            if isOwn {
                syncIcon
            }
        }
    }
    
    @ViewBuilder
    private var syncIcon: some View {
        switch message.syncState {
        case .synced:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.white.opacity(0.7))
        case .pendingUpsert, .pendingDelete:
            Image(systemName: "clock")
                .font(.caption2).foregroundStyle(.white.opacity(0.6))
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2).foregroundStyle(.red)
        }
    }
    
    // MARK: - Reaction row
    
    private var reactionRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(message.reactions.keys.sorted()), id: \.self) { emoji in
                let count = message.reactions[emoji]?.count ?? 0
                Button {
                    onReactionTap(emoji)
                } label: {
                    HStack(spacing: 2) {
                        Text(emoji).font(.caption)
                        if count > 1 {
                            Text("\(count)").font(.caption2.bold()).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemBackground), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Context menu
    
    @ViewBuilder
    private var contextMenuItems: some View {
        Button { onLongPress() } label: {
            Label("Reagisci", systemImage: "face.smiling")
        }
        if isOwn {
            Button(role: .destructive) { onDelete() } label: {
                Label("Elimina", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Placeholder views
    
    private var mediaLoadingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground))
                .frame(width: 220, height: 140)
            ProgressView()
        }
    }
    
    private func mediaErrorPlaceholder(icon: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground))
                .frame(width: 220, height: 140)
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Style helpers
    
    private func maxBubbleWidth(containerWidth: CGFloat) -> CGFloat {
        let base = min(containerWidth * 0.72, 420)
        switch dynamicTypeSize {
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return min(containerWidth * 0.68, 420)
        default:
            return base
        }
    }
    
    private var bubbleBackground: Color {
        isOwn ? .accentColor : Color(.secondarySystemBackground)
    }
    
    private var bubbleShape: some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius:     isOwn ? 18 : 4,
            bottomLeadingRadius:  18,
            bottomTrailingRadius: isOwn ? 4 : 18,
            topTrailingRadius:    18
        )
    }
    
    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .purple, .orange, .pink, .teal]
        let index = abs(message.senderId.hashValue) % colors.count
        return colors[index]
    }
    
    // MARK: - Audio player
    
    private func toggleAudio() {
        if isPlayingAudio {
            audioPlayer?.pause()
            isPlayingAudio = false
            proximityRouter.stop()
            stopProgressTimer()
            return
        }
        
        // Se il player esiste già, riprendi (o riparti se era finito)
        if let player = audioPlayer {
            do {
                try configureVoicePlaybackSession()
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                proximityRouter.start()
            } catch {}
            
            if player.currentTime >= player.duration - 0.05 {
                player.currentTime = 0
                playbackProgress = 0
            }
            
            player.play()
            isPlayingAudio = true
            startProgressTimer()
            return
        }
        
        guard let urlString = message.mediaURL,
              let url = URL(string: urlString) else { return }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                try configureVoicePlaybackSession()
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                
                proximityRouter.start()
                
                let player = try AVAudioPlayer(data: data)
                let router = proximityRouter
                
                audioDelegate.onFinish = { [router] in
                    DispatchQueue.main.async {
                        router.stop()
                        self.stopProgressTimer()
                        isPlayingAudio = false
                        self.playbackProgress = 0
                        audioPlayer?.stop()
                        audioPlayer?.currentTime = 0
                        // se preferisci “hard reset”:
                        // audioPlayer = nil
                    }
                }
                player.delegate = audioDelegate
                
                player.play()
                
                DispatchQueue.main.async {
                    self.audioPlayer = player
                    self.isPlayingAudio = true
                    self.startProgressTimer()
                }
            } catch {
                DispatchQueue.main.async {
                    proximityRouter.stop()
                    isPlayingAudio = false
                }
            }
        }
    }
    
    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player = audioPlayer, player.duration > 0 else { return }
            DispatchQueue.main.async {
                playbackProgress = player.currentTime / player.duration
            }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func configureVoicePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetoothHFP, .allowBluetoothA2DP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - FullScreenPhotoView

private struct FullScreenPhotoView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFit()
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundStyle(.white)
                    .padding()
            }
        }
    }
}

// MARK: - FullScreenVideoView

private struct FullScreenVideoView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    @State private var player: AVPlayer
    
    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            
            VideoPlayer(player: player)
                .ignoresSafeArea()
            
            Button {
                player.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4)
                    .padding()
            }
        }
        .onAppear { player.play() }
        .onDisappear { player.pause() }
    }
}

// MARK: - ChatBubbleAudioDelegate

final class ChatBubbleAudioDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinish?()
    }
}
