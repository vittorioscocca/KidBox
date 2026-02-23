//
//  ChatBubble.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//


import SwiftUI
import AVKit
import AVFoundation

private enum AudioBubble {
    static let playW:   CGFloat = 32
    static let rateW:   CGFloat = 44
    static let spacing: CGFloat = 12
    static let inner:   CGFloat = 230
    static let waveW:   CGFloat = inner - playW - rateW - 2 * spacing  // 130
    static let total:   CGFloat = inner + 24  // + paddingH 12+12
}

struct ChatBubble: View {
    
    let message: KBChatMessage
    let isOwn: Bool
    let currentUID: String
    let onReactionTap: (String) -> Void
    let onLongPress: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let onReply: () -> Void
    let repliedTo: KBChatMessage?
    let onReplyContextTap: () -> Void
    let highlightedMessageId: String?
    let searchText: String
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    @State private var isPlayingAudio = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var proximityRouter = ProximityAudioRouter()
    @State private var audioDelegate = ChatBubbleAudioDelegate()
    @State private var playbackProgress: Double = 0.0
    @State private var progressTimer: Timer?
    @State private var isDraggingSlider = false
    @State private var dragProgress: Double = 0.0
    @State private var playbackRate: Float = 1.0
    
    @State private var showFullScreenPhoto = false
    @State private var showFullScreenVideo = false
    
    // Swipe-to-reply
    @State private var swipeX: CGFloat = 0
    
    private var maxBubbleWidth: CGFloat {
        let w = UIScreen.main.bounds.width
        switch dynamicTypeSize {
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return min(w * 0.68, 420)
        default:
            return min(w * 0.72, 420)
        }
    }
    
    private var isHighlighted: Bool {
        highlightedMessageId == message.id
    }
    
    private var highlightFill: Color {
        isOwn ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.12)
    }
    
    private var highlightStroke: Color {
        isOwn ? Color.white.opacity(0.85) : Color.accentColor.opacity(0.85)
    }
    
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
                
                if isOwn { Spacer(minLength: 0) }
                
                bubbleBody
                    .contextMenu { contextMenuItems }
                    .offset(x: swipeX)
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { v in
                                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                                guard v.translation.width > 0 else { return }
                                swipeX = min(28, v.translation.width / 3)
                            }
                            .onEnded { v in
                                let shouldTrigger = v.translation.width > 70 && abs(v.translation.width) > abs(v.translation.height)
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { swipeX = 0 }
                                if shouldTrigger { onReply() }
                            }
                    )
                
                if !isOwn { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 12)
            
            if !message.reactions.isEmpty {
                reactionRow.padding(.horizontal, isOwn ? 16 : 54)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
        .padding(.vertical, 2)
        .onDisappear { proximityRouter.stop(); stopProgressTimer() }
    }
    
    // MARK: - Bubble body
    
    @ViewBuilder
    private var bubbleBody: some View {
        if message.type == .audio {
            // Audio: larghezza fissa esatta
            VStack(alignment: .leading, spacing: 6) {
                replyContextHeader
                audioContent
                audioBottomRow
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: AudioBubble.total)
            .background(bubbleBackground)
            .overlay(highlightOverlay)
            .clipShape(bubbleShape)
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        } else {
            VStack(alignment: isOwn ? .trailing : .leading, spacing: 6) {
                replyContextHeader
                bubbleContent
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .background(bubbleBackground)
            .overlay(highlightOverlay)
            .clipShape(bubbleShape)
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        }
    }
    
    private var timeAndChecks: some View {
        HStack(spacing: 4) {
            Text(message.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
            if isOwn { syncIcon }
        }
        .fixedSize() // important: non deve espandere
    }

    
    @ViewBuilder
    private var highlightOverlay: some View {
        if isHighlighted {
            bubbleShape
                .fill(isOwn ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.12))
                .overlay(
                    bubbleShape.stroke(
                        isOwn ? Color.white.opacity(0.85) : Color.accentColor.opacity(0.85),
                        lineWidth: 2
                    )
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isHighlighted)
        }
    }
    
    // MARK: - Reply context header
    
    @ViewBuilder
    private var replyContextHeader: some View {
        if message.replyToId != nil {
            HStack(spacing: 8) {
                Capsule()
                    .fill(isOwn ? Color.white.opacity(0.85) : Color.accentColor)
                    .frame(width: 3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(replyTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isOwn ? Color.white.opacity(0.9) : Color.accentColor)
                        .lineLimit(1)
                    
                    replySubtitle
                        .font(.caption2)
                        .foregroundStyle(isOwn ? Color.white.opacity(0.75) : Color.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isOwn ? Color.white.opacity(0.12) : Color.accentColor.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(Rectangle())
            .onTapGesture { onReplyContextTap() }
        }
    }
    
    private var replyTitle: String {
        guard let repliedTo else { return "Risposta" }
        return repliedTo.senderId == currentUID ? "Tu" : (repliedTo.senderName.isEmpty ? "Utente" : repliedTo.senderName)
    }
    
    @ViewBuilder
    private var replySubtitle: some View {
        if let repliedTo {
            switch repliedTo.type {
                
            case .text:
                let t = (repliedTo.text ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                Text(t.isEmpty ? "Messaggio" : t)
                
            case .photo:
                HStack(spacing: 6) {
                    if let urlString = repliedTo.mediaURL,
                       let url = URL(string: urlString) {
                        CachedAsyncImage(url: url, contentMode: .fill)
                            .frame(width: 18, height: 18)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text("Foto")
                }
                
            case .video:
                HStack(spacing: 6) {
                    Image(systemName: "video.fill")
                        .font(.caption2)
                    Text("Video")
                }
                
            case .audio:
                let d = repliedTo.mediaDurationSeconds ?? 0
                let label = d > 0
                ? "Messaggio vocale • \(formatDuration(d))"
                : "Messaggio vocale"
                
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.caption2)
                    Text(label)
                }
            }
            
        } else {
            Text("Messaggio")
        }
    }
    
    func highlightedText(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        
        guard !searchText.isEmpty else { return attr }
        
        let lower = text.lowercased()
        let query = searchText.lowercased()
        
        var searchRange = lower.startIndex..<lower.endIndex
        
        while let range = lower.range(of: query, options: [], range: searchRange) {
            if let attrRange = Range(range, in: attr) {
                attr[attrRange].backgroundColor = .yellow.opacity(0.4)
            }
            searchRange = range.upperBound..<lower.endIndex
        }
        
        return attr
    }
    
    // MARK: - Bubble content (non-audio)
    
    @ViewBuilder
    private var bubbleContent: some View {
        switch message.type {
        case .text:
            let text = message.text ?? ""
            
            VStack(alignment: .leading, spacing: 4) {
                
                ViewThatFits(in: .horizontal) {
                    
                    // ✅ Tentativo 1: testo + footer INLINE (una riga)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(highlightedText(text))
                            .font(.body)
                            .foregroundStyle(isOwn ? .white : .primary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: true)
                        
                        timeAndChecks
                    }
                    .fixedSize(horizontal: true, vertical: true)
                    
                    // ✅ Fallback: testo wrappato + footer sotto
                    VStack(alignment: .leading, spacing: 6) {
                        Text(highlightedText(text))
                            .font(.body)
                            .foregroundStyle(isOwn ? .white : .primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        HStack {
                            Spacer(minLength: 0)
                            timeAndChecks
                        }
                    }
                    .frame(maxWidth: maxBubbleWidth - 24, alignment: .leading)
                }
                
                if let url = extractFirstURL(from: text) {
                    LinkPreviewView(url: url, isOwn: isOwn)
                }
            }
        case .photo:  photoContent
        case .video:  videoContent
        case .audio:  EmptyView()
        }
    }
    
    // MARK: - Photo / Video
    
    private var photoContent: some View {
        Group {
            if let urlString = message.mediaURL, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, contentMode: .fill)
                    .frame(width: 220, height: 160).clipped()
                    .overlay(highlightOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { showFullScreenPhoto = true }
                    .fullScreenCover(isPresented: $showFullScreenPhoto) { FullScreenPhotoView(url: url) }
            } else { mediaLoadingPlaceholder }
        }
    }
    
    private func copyTextToPasteboard() {
        let t = (message.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIPasteboard.general.string = t
    }
    
    private var videoContent: some View {
        Group {
            if let urlString = message.mediaURL, let url = URL(string: urlString) {
                ZStack {
                    VideoThumbnailView(videoURL: url, cacheKey: videoCacheKey(urlString: urlString))
                        .frame(width: 220, height: 160).clipped()
                        .overlay(highlightOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Image(systemName: "play.circle.fill").font(.system(size: 44))
                        .foregroundStyle(.white).shadow(radius: 6)
                }
                .contentShape(Rectangle())
                .onTapGesture { showFullScreenVideo = true }
                .fullScreenCover(isPresented: $showFullScreenVideo) { FullScreenVideoView(url: url) }
            } else { mediaLoadingPlaceholder }
        }
    }
    
    private func videoCacheKey(urlString: String) -> String {
        if var c = URLComponents(string: urlString) { c.query = nil; return c.string ?? urlString }
        return urlString
    }
    
    // MARK: - Audio content
    
    private var audioContent: some View {
        HStack(alignment: .center, spacing: AudioBubble.spacing) {
            Button { toggleAudio() } label: {
                Image(systemName: isPlayingAudio ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isOwn ? .white : .accentColor)
            }
            .buttonStyle(.plain)
            .frame(width: AudioBubble.playW, height: AudioBubble.playW)
            .accessibilityLabel(isPlayingAudio ? "Pausa audio" : "Riproduci audio")
            
            scrubbableWaveform
                .frame(width: AudioBubble.waveW, height: 24)
            
            Button { cyclePlaybackRate() } label: {
                Text(playbackRateLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isOwn ? .white : .accentColor)
                    .frame(width: AudioBubble.rateW, height: 28)
                    .background(Capsule().fill(
                        isOwn ? Color.white.opacity(0.25) : Color.accentColor.opacity(0.15)
                    ))
            }
            .buttonStyle(.plain)
            .frame(width: AudioBubble.rateW)
        }
        .frame(width: AudioBubble.inner, height: AudioBubble.playW)
        .padding(.top, 4)
    }
    
    private var scrubbableWaveform: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(0..<20, id: \.self) { i in
                        let played = Double(i) / 20.0 < (isDraggingSlider ? dragProgress : playbackProgress)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isOwn
                                  ? (played ? Color.white : Color.white.opacity(0.35))
                                  : (played ? Color.accentColor : Color.accentColor.opacity(0.3)))
                            .frame(width: 5, height: waveformHeight(index: i))
                    }
                }
                let prog = isDraggingSlider ? dragProgress : playbackProgress
                Circle()
                    .fill(isOwn ? Color.white : Color.accentColor)
                    .frame(width: isDraggingSlider ? 14 : 10, height: isDraggingSlider ? 14 : 10)
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                    .offset(x: prog * geo.size.width - (isDraggingSlider ? 7 : 5))
                    .animation(.easeInOut(duration: 0.1), value: isDraggingSlider)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = (v.location.x / geo.size.width).clamped(to: 0...1)
                    dragProgress = p; isDraggingSlider = true; stopProgressTimer()
                    audioPlayer?.currentTime = p * (audioPlayer?.duration ?? 0)
                }
                .onEnded { v in
                    let p = (v.location.x / geo.size.width).clamped(to: 0...1)
                    isDraggingSlider = false; playbackProgress = p
                    if let player = audioPlayer {
                        player.currentTime = p * player.duration
                        if isPlayingAudio { startProgressTimer() }
                    } else { Task { await loadPlayerAndSeek(to: p) } }
                }
            )
        }
    }
    
    private func waveformHeight(index: Int) -> CGFloat {
        CGFloat(6 + abs((message.id.hashValue ^ (index &* 31)) % 15))
    }
    
    // MARK: - Bottom rows
    
    // Audio: durata a sx, orario a dx — larghezza fissa
    private var audioBottomRow: some View {
        HStack(spacing: 4) {
            if let dur = message.mediaDurationSeconds {
                Text(isDraggingSlider
                     ? formatDuration(Int(dragProgress * Double(dur)))
                     : formatDuration(dur))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
                .animation(.none, value: isDraggingSlider)
            }
            Spacer(minLength: 0)
            Text(message.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
            if isOwn { syncIcon }
        }
        .frame(width: AudioBubble.inner)
    }
    
    // Testo/foto/video: NO Spacer — la bubble si restringe al contenuto
    private var bottomRow: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(message.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
            if isOwn { syncIcon }
        }
    }
    
    @ViewBuilder
    private var syncIcon: some View {
        switch message.syncState {
        case .pendingUpsert, .pendingDelete:
            Image(systemName: "clock").font(.caption2).foregroundStyle(.white.opacity(0.6))
        case .error:
            Image(systemName: "exclamationmark.circle.fill").font(.caption2).foregroundStyle(.red)
        case .synced:
            let isRead = !message.readBy.isEmpty
            HStack(spacing: -4) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isRead ? Color.white : Color.white.opacity(0.6))
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isRead ? Color.white : Color.clear)
            }
        }
    }
    
    // MARK: - Reactions
    
    private var reactionRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(message.reactions.keys.sorted()), id: \.self) { emoji in
                let count = message.reactions[emoji]?.count ?? 0
                Button { onReactionTap(emoji) } label: {
                    HStack(spacing: 2) {
                        Text(emoji).font(.caption)
                        if count > 1 { Text("\(count)").font(.caption2.bold()).foregroundStyle(.secondary) }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
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
        Button { onLongPress() } label: { Label("Reagisci", systemImage: "face.smiling") }
        
        if message.type == .text {
            Button { copyTextToPasteboard() } label: {
                Label("Copia", systemImage: "doc.on.doc")
            }
        }
        
        if isOwn, message.type == .text, let onEdit {
            Button { onEdit() } label: { Label("Modifica", systemImage: "pencil") }
        }
        
        if let onDelete {
            Button(role: .destructive) {
                onDelete()     // ✅ SOLO QUESTO
            } label: {
                Label("Elimina", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Placeholder
    
    private var mediaLoadingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground))
                .frame(width: 220, height: 140)
            ProgressView()
        }
    }
    
    // MARK: - Link helpers
    
    private func extractFirstURL(from text: String) -> URL? {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return d.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)).flatMap { $0.url }
    }
    
    private func makeAttributedText(_ text: String) -> AttributedString {
        var attr = (try? AttributedString(markdown: text)) ?? AttributedString(text)
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return attr }
        d.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { m, _, _ in
            guard let m, let url = m.url,
                  let sr = Range(m.range, in: text), let ar = Range(sr, in: attr) else { return }
            attr[ar].link = url
            attr[ar].foregroundColor = isOwn ? UIColor.white : UIColor.systemBlue
            attr[ar].underlineStyle = .single
        }
        return attr
    }
    
    // MARK: - Style
    
    private var bubbleBackground: Color { isOwn ? .accentColor : Color(.secondarySystemBackground) }
    
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
        return colors[abs(message.senderId.hashValue) % colors.count]
    }
    
    private var playbackRateLabel: String {
        switch playbackRate { case 1.5: return "1.5×"; case 2.0: return "2×"; default: return "1×" }
    }
    
    private func cyclePlaybackRate() {
        switch playbackRate { case 1.0: playbackRate = 1.5; case 1.5: playbackRate = 2.0; default: playbackRate = 1.0 }
        if let p = audioPlayer, isPlayingAudio { p.enableRate = true; p.rate = playbackRate }
    }
    
    // MARK: - Audio player
    
    private func toggleAudio() {
        if isPlayingAudio {
            audioPlayer?.pause(); isPlayingAudio = false; proximityRouter.stop(); stopProgressTimer(); return
        }
        if let player = audioPlayer {
            do { try configureAudioSession(); try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker); proximityRouter.start() } catch {}
            if player.currentTime >= player.duration - 0.05 { player.currentTime = 0; playbackProgress = 0 }
            player.play(); isPlayingAudio = true; startProgressTimer(); return
        }
        guard let us = message.mediaURL, let url = URL(string: us) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try configureAudioSession()
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                proximityRouter.start()
                let player = try AVAudioPlayer(data: data)
                player.enableRate = true; player.rate = playbackRate
                let router = proximityRouter
                audioDelegate.onFinish = { [router] in DispatchQueue.main.async {
                    router.stop(); self.stopProgressTimer(); isPlayingAudio = false
                    self.playbackProgress = 0; audioPlayer?.stop(); audioPlayer?.currentTime = 0
                }}
                player.delegate = audioDelegate; player.play()
                DispatchQueue.main.async { self.audioPlayer = player; self.isPlayingAudio = true; self.startProgressTimer() }
            } catch { DispatchQueue.main.async { proximityRouter.stop(); isPlayingAudio = false } }
        }
    }
    
    private func loadPlayerAndSeek(to progress: Double) async {
        guard let us = message.mediaURL, let url = URL(string: us) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try configureAudioSession()
            let player = try AVAudioPlayer(data: data)
            player.enableRate = true; player.rate = playbackRate; player.prepareToPlay()
            player.currentTime = progress * player.duration
            let router = proximityRouter
            audioDelegate.onFinish = { DispatchQueue.main.async {
                router.stop(); self.stopProgressTimer(); self.isPlayingAudio = false
                self.playbackProgress = 0; self.audioPlayer?.currentTime = 0
            }}
            player.delegate = audioDelegate
            DispatchQueue.main.async { self.audioPlayer = player; self.playbackProgress = progress }
        } catch {}
    }
    
    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let p = audioPlayer, p.duration > 0 else { return }
            DispatchQueue.main.async { playbackProgress = p.currentTime / p.duration }
        }
    }
    
    private func stopProgressTimer() { progressTimer?.invalidate(); progressTimer = nil }
    
    private func configureAudioSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetoothHFP, .allowBluetoothA2DP])
        try s.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func formatDuration(_ sec: Int) -> String { String(format: "%d:%02d", sec / 60, sec % 60) }
}

// MARK: - FullScreenPhotoView

private struct FullScreenPhotoView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            CachedAsyncImage(url: url, contentMode: .fit)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white).padding()
            }
        }
    }
}

// MARK: - FullScreenVideoView

private struct FullScreenVideoView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    init(url: URL) { self.url = url; let p = AVPlayer(url: url); p.volume = 1.0; _player = State(initialValue: p) }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player).ignoresSafeArea()
                .onAppear {
                    do {
                        let s = AVAudioSession.sharedInstance()
                        try s.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, AVAudioSession.CategoryOptions.allowBluetoothHFP])
                        try s.setActive(true)
                    } catch {}
                    player.play()
                }
                .onDisappear { player.pause() }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white).padding()
            }
        }
    }
}

// MARK: - ChatBubbleAudioDelegate

final class ChatBubbleAudioDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish?() }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { onFinish?() }
}

// MARK: - LinkPreviewView

private struct LinkPreviewView: View {
    let url: URL; let isOwn: Bool
    @State private var metadata: LinkMetadata?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                RoundedRectangle(cornerRadius: 10).fill(bg).frame(height: 60)
                    .overlay(ProgressView().tint(isOwn ? .white : .accentColor))
            } else if let meta = metadata {
                Button { UIApplication.shared.open(url) } label: { card(meta) }.buttonStyle(.plain)
            }
        }
        .task { await load() }
    }
    
    private func card(_ meta: LinkMetadata) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let iu = meta.imageURL {
                AsyncImage(url: iu) { p in
                    if case .success(let i) = p {
                        i.resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 110).clipped()
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(url.host ?? url.absoluteString).font(.caption2.weight(.semibold))
                    .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary).lineLimit(1)
                if let t = meta.title, !t.isEmpty {
                    Text(t).font(.caption.weight(.semibold))
                        .foregroundStyle(isOwn ? .white : .primary).lineLimit(2)
                }
                if let d = meta.description, !d.isEmpty {
                    Text(d).font(.caption2)
                        .foregroundStyle(isOwn ? .white.opacity(0.8) : .secondary).lineLimit(2)
                }
            }.padding(8)
        }
        .background(bg).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
    
    private var bg: Color { isOwn ? .white.opacity(0.15) : Color(.tertiarySystemBackground) }
    
    private func load() async {
        if let c = LinkMetadataCache.shared.get(url) { metadata = c; isLoading = false; return }
        guard let m = await fetch(url) else { isLoading = false; return }
        LinkMetadataCache.shared.set(m, for: url); metadata = m; isLoading = false
    }
    
    private func fetch(_ url: URL) async -> LinkMetadata? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let html = String(data: data, encoding: .utf8) else { return nil }
        func og(_ k: String) -> String? {
            for pat in [
                #"<meta[^>]+property=["\']og:\#(k)["\'][^>]+content=["\']([^"\']+)["\']"#,
                #"<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:\#(k)["\']"#
            ] {
                if let r = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
                   let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                   let rng = Range(m.range(at: 1), in: html) { return String(html[rng]).htmlDecoded }
            }; return nil
        }
        let title = og("title") ?? {
            let p = #"<title[^>]*>([^<]+)</title>"#
            if let r = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let rng = Range(m.range(at: 1), in: html) { return String(html[rng]).htmlDecoded }
            return nil
        }()
        let img: URL? = og("image").flatMap { URL(string: $0) }
        guard title != nil || img != nil else { return nil }
        return LinkMetadata(title: title, description: og("description"), imageURL: img)
    }
}

private struct LinkMetadata { let title: String?; let description: String?; let imageURL: URL? }

private final class LinkMetadataCache {
    static let shared = LinkMetadataCache()
    private var cache: [URL: LinkMetadata] = [:]
    private init() {}
    func get(_ u: URL) -> LinkMetadata? { cache[u] }
    func set(_ m: LinkMetadata, for u: URL) { cache[u] = m }
}

private extension String {
    var htmlDecoded: String {
        [("&amp;","&"),("&lt;","<"),("&gt;",">"),("&quot;","\""),("&#39;","'"),("&apos;","'"),("&nbsp;"," ")]
            .reduce(self) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}

private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
