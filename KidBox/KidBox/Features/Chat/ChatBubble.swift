//
//  ChatBubble.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//

import AVFoundation
import AVKit
import FirebaseStorage
import MapKit
import SwiftUI
import SwiftData

private enum AudioBubble {
    static let playW: CGFloat = 32
    static let rateW: CGFloat = 44
    static let spacing: CGFloat = 12
    static let inner: CGFloat = 230
    static let waveW: CGFloat = inner - playW - rateW - 2 * spacing  // 130
    static let total: CGFloat = inner + 24  // + paddingH 12+12
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
    
    // Larghezza dello schermo calcolata una sola volta — evita @State containerWidth
    // che causava un secondo layout pass su ogni bubble al primo render
    // (measureBackwards nel LazyVStack).
    private static let screenWidth: CGFloat = UIScreen.main.bounds.width
    
    // Media QuickLook
    @State private var isDownloadingMedia = false
    @State private var downloadedMediaURL: URL?
    @State private var showMediaQuickLook = false
    @State private var mediaDownloadError: String?
    
    // Swipe-to-reply
    @State private var swipeX: CGFloat = 0
    
    // Valori precalcolati nell'init — mai ricalcolati nel body
    private let cachedLinkURL: URL?
    private let cachedHighlightedText: AttributedString
    // URL del messaggio citato in risposta — anche questo estratto nell'init
    // perché replySubtitle è un @ViewBuilder nel body e chiamarci extractFirstURL
    // causava DynamicBody.updateValue → NSDataDetector ad ogni layout pass.
    private let cachedReplyLinkURL: URL?
    // FIX 3: ora formattata una volta sola nell'init.
    // Text(date, style: .time) chiama ICUDateFormatter ad ogni layout pass
    // (visibile nel call stack: FormatStyleStorage → ICUDateFormatter → icu::SimpleDateFormat).
    private let cachedTimeString: String
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
    
    init(
        message: KBChatMessage,
        isOwn: Bool,
        currentUID: String,
        onReactionTap: @escaping (String) -> Void,
        onLongPress: @escaping () -> Void,
        onEdit: (() -> Void)?,
        onDelete: (() -> Void)?,
        onReply: @escaping () -> Void,
        repliedTo: KBChatMessage?,
        onReplyContextTap: @escaping () -> Void,
        highlightedMessageId: String?,
        searchText: String
    ) {
        self.message = message
        self.isOwn = isOwn
        self.currentUID = currentUID
        self.onReactionTap = onReactionTap
        self.onLongPress = onLongPress
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onReply = onReply
        self.repliedTo = repliedTo
        self.onReplyContextTap = onReplyContextTap
        self.highlightedMessageId = highlightedMessageId
        self.searchText = searchText
        
        // Calcolo fatto UNA SOLA VOLTA alla creazione della struct,
        // non ad ogni chiamata del body.
        let text = message.text ?? ""
        self.cachedLinkURL = Self.extractFirstURL(from: text)
        self.cachedHighlightedText = Self.buildHighlightedText(text, searchText: searchText)
        self.cachedTimeString = Self.timeFormatter.string(from: message.createdAt)
        // URL del replied-to message — calcolata qui, non nel body
        if let rt = repliedTo, rt.type == .text {
            let rt = (rt.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self.cachedReplyLinkURL = Self.extractFirstURL(from: rt)
        } else {
            self.cachedReplyLinkURL = nil
        }
    }
    
    // FIX 4: sostituisce ViewThatFits — decisione O(1) invece di doppia misurazione layout.
    // ViewThatFits causava specialized LazyStack measureBackwards nel call stack
    // (315ms su 5.69s totali di CPU durante lo scroll).
    private var textIsShort: Bool {
        let text = message.text ?? ""
        return text.count <= 30 && !text.contains("\n")
    }
    
    private var maxBubbleWidth: CGFloat {
        let w = Self.screenWidth
        switch dynamicTypeSize {
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return min(w * 0.68, 420)
        default:
            return min(w * 0.72, 420)
        }
    }
    
    private enum ChatMediaStyle {
        static let size = CGSize(width: 220, height: 160)
        static let corner: CGFloat = 14
    }
    
    private var isHighlighted: Bool { highlightedMessageId == message.id }
    
    private var hasLinkPreview: Bool {
        guard message.type == .text else { return false }
        return cachedLinkURL != nil
    }
    
    private var shouldConstrainToMaxWidth: Bool {
        (message.replyToId != nil) || hasLinkPreview
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
                    SenderAvatarView(
                        senderId: message.senderId,
                        familyId: message.familyId,
                        senderName: message.senderName,
                        fallbackColor: avatarColor
                    )
                }
                
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
                                let shouldTrigger = v.translation.width > 70
                                && abs(v.translation.width) > abs(v.translation.height)
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { swipeX = 0 }
                                if shouldTrigger { onReply() }
                            }
                    )
                    .frame(
                        maxWidth: .infinity,
                        alignment: isOwn ? .trailing : .leading
                    )
            }
            .padding(.horizontal, 12)
            
            if !message.reactions.isEmpty {
                reactionRow.padding(.horizontal, isOwn ? 16 : 54)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
        .padding(.vertical, 2)
        .onDisappear {
            proximityRouter.stop()
            stopProgressTimer()
        }
    }
    
    // MARK: - Bubble body
    
    @ViewBuilder
    private var bubbleBody: some View {
        if message.type == .audio {
            if message.type == .audio {
                VStack(alignment: .leading, spacing: 8) {
                    replyContextHeader
                    audioContent
                    
                    if !isOwn && message.shouldShowTranscript {
                        transcriptSection
                    }
                    
                    audioBottomRow
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(width: maxBubbleWidth, alignment: .leading)
                .background(bubbleBackground)
                .overlay(highlightOverlay)
                .clipShape(bubbleShape)
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
            }
        } else if message.type == .photo || message.type == .video {
            if message.replyToId != nil {
                VStack(alignment: isOwn ? .trailing : .leading, spacing: 0) {
                    replyContextHeader
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .frame(maxWidth: maxBubbleWidth)
                        .background(bubbleBackground)
                    bubbleContent
                }
                .overlay(highlightOverlay)
                .clipShape(bubbleShape)
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
            } else {
                bubbleContent
                    .overlay(highlightOverlay)
                    .clipShape(bubbleShape)
                    .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
            }
        } else if message.type == .document {
            VStack(alignment: isOwn ? .trailing : .leading, spacing: 6) {
                replyContextHeader
                bubbleContent
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .frame(maxWidth: maxBubbleWidth)
            .background(bubbleBackground)
            .overlay(highlightOverlay)
            .clipShape(bubbleShape)
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
            .contentShape(Rectangle())
        } else if message.type == .location {
            Group {
                if message.replyToId != nil {
                    VStack(alignment: isOwn ? .trailing : .leading, spacing: 0) {
                        replyContextHeader
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .frame(maxWidth: maxBubbleWidth)
                            .background(bubbleBackground)
                        bubbleContent
                    }
                    .overlay(highlightOverlay)
                    .clipShape(bubbleShape)
                    .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                } else {
                    bubbleContent
                        .overlay(highlightOverlay)
                        .clipShape(bubbleShape)
                        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                }
            }
            .contentShape(Rectangle())
        } else {
            // Testo
            VStack(alignment: isOwn ? .trailing : .leading, spacing: 6) {
                replyContextHeader
                bubbleContent
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .frame(
                maxWidth: shouldConstrainToMaxWidth ? maxBubbleWidth : nil,
                alignment: isOwn ? .trailing : .leading
            )
            .background(bubbleBackground)
            .overlay(highlightOverlay)
            .clipShape(bubbleShape)
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        }
    }
    
    // MARK: - Bubble content
    
    @ViewBuilder
    private var bubbleContent: some View {
        switch message.type {
        case .text:
            // FIX 2: usa cachedLinkURL e cachedHighlightedText precalcolati nell'init,
            // invece di chiamare NSDataDetector e costruire AttributedString ad ogni render.
            VStack(alignment: .leading, spacing: 4) {
                if let url = cachedLinkURL {
                    Text(cachedHighlightedText)
                        .font(.body)
                        .foregroundStyle(isOwn ? .white : .primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    LinkPreviewView(url: url, isOwn: isOwn)
                    
                    HStack {
                        Spacer(minLength: 0)
                        timeAndChecks
                    }
                } else {
                    // FIX 4: if/else esplicito invece di ViewThatFits.
                    // ViewThatFits misura entrambe le alternative ad ogni layout pass.
                    if textIsShort {
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(cachedHighlightedText)
                                .font(.body)
                                .foregroundStyle(isOwn ? .white : .primary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: true)
                            timeAndChecks
                        }
                        .fixedSize(horizontal: true, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(cachedHighlightedText)
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
                        .frame(maxWidth: max(maxBubbleWidth - 24, 100), alignment: .leading)
                    }
                }
            }
            
        case .photo: photoContent
        case .video: videoContent
        case .audio: EmptyView()
        case .document: documentContent
        case .location:
            if let lat = message.latitude, let lon = message.longitude {
                ZStack(alignment: .bottomTrailing) {
                    LocationBubbleView(latitude: lat, longitude: lon, isOwn: isOwn)
                    timeAndChecksOverlayOnMedia
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                        .padding(6)
                }
            }
        }
    }
    
    // MARK: - Highlight overlay
    
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
        return repliedTo.senderId == currentUID
        ? "Tu"
        : (repliedTo.senderName.isEmpty ? "Utente" : repliedTo.senderName)
    }
    
    @ViewBuilder
    private var replySubtitle: some View {
        if let repliedTo {
            switch repliedTo.type {
            case .text:
                let t = (repliedTo.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = cachedReplyLinkURL {
                    HStack(spacing: 8) {
                        LinkPreviewThumb(
                            url: url,
                            size: ChatThumbStyle.composerReplySize,
                            corner: ChatThumbStyle.replyCorner
                        )
                        Text(url.host ?? "Link")
                    }
                } else {
                    Text(t.isEmpty ? "Messaggio" : t)
                }
            case .photo:
                HStack(spacing: 8) {
                    replyThumb(for: repliedTo)
                    Text("Foto")
                }
            case .video:
                HStack(spacing: 8) {
                    replyThumb(for: repliedTo)
                    Text("Video")
                }
            case .audio:
                let d = repliedTo.mediaDurationSeconds ?? 0
                let label = d > 0 ? "Messaggio vocale • \(formatDuration(d))" : "Messaggio vocale"
                HStack(spacing: 6) {
                    Image(systemName: "waveform").font(.caption2)
                    Text(label)
                }
            case .document:
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill").font(.caption2)
                    Text(repliedTo.text ?? "Documento")
                }
            case .location:
                HStack(spacing: 8) {
                    replyThumb(for: repliedTo)
                    Text("Posizione condivisa")
                }
            }
        } else {
            Text("Messaggio")
        }
    }
    
    private var locationContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "location.fill")
                .foregroundStyle(isOwn ? .white : .accentColor)
            Text("Posizione condivisa").font(.caption)
        }
        .onTapGesture { openInMaps() }
    }
    
    private func openInMaps() {
        guard let lat = message.latitude, let lon = message.longitude else { return }
        let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lon)")!
        UIApplication.shared.open(url)
    }
    
    // MARK: - Time & Checks
    
    private var timeAndChecksOverlayOnMedia: some View {
        HStack(spacing: 4) {
            if message.editedAt != nil {
                Text("Modificato").font(.caption2).foregroundStyle(.white.opacity(0.85))
            }
            Text(cachedTimeString).font(.caption2).foregroundStyle(.white.opacity(0.9))
            if isOwn { syncIconOverlayOnMedia }
        }
        .fixedSize()
    }
    
    @ViewBuilder
    private var syncIconOverlayOnMedia: some View {
        switch message.syncState {
        case .pendingUpsert, .pendingDelete:
            Image(systemName: "clock").font(.caption2).foregroundStyle(.white.opacity(0.85))
        case .error:
            Image(systemName: "exclamationmark.circle.fill").font(.caption2).foregroundStyle(.yellow)
        case .synced:
            let isRead = !message.readBy.isEmpty
            HStack(spacing: -4) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isRead ? .white.opacity(0.9) : .white.opacity(0.0))
            }
        }
    }
    
    private var timeAndChecks: some View {
        HStack(spacing: 4) {
            if message.editedAt != nil {
                Text("Modificato").font(.caption2).foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
            }
            Text(cachedTimeString).font(.caption2).foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
            if isOwn { syncIcon }
        }
        .fixedSize()
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
    
    // MARK: - Photo / Video
    
    private var photoContent: some View {
        Group {
            if let urlString = message.mediaURL, let remoteURL = URL(string: urlString) {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: remoteURL, contentMode: .fill)
                        .frame(width: ChatMediaStyle.size.width, height: ChatMediaStyle.size.height)
                        .overlay(highlightOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    if isDownloadingMedia {
                        Color.black.opacity(0.35).clipShape(RoundedRectangle(cornerRadius: 10))
                        ProgressView().tint(.white)
                            .frame(width: ChatMediaStyle.size.width, height: ChatMediaStyle.size.height)
                    }
                    
                    timeAndChecksOverlayOnMedia
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                        .padding(6)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isDownloadingMedia else { return }
                    Task { await downloadAndPreviewMedia(remoteURL: remoteURL, fileName: "immagine.jpg") }
                }
                .mediaQuickLookSheet(url: $downloadedMediaURL, isPresented: $showMediaQuickLook, error: $mediaDownloadError)
            } else {
                mediaLoadingPlaceholder
            }
        }
    }
    
    private var videoContent: some View {
        Group {
            if let urlString = message.mediaURL, let remoteURL = URL(string: urlString) {
                ZStack {
                    VideoThumbnailView(videoURL: remoteURL, cacheKey: videoCacheKey(urlString: urlString))
                        .frame(width: ChatMediaStyle.size.width, height: ChatMediaStyle.size.height)
                        .clipped()
                        .overlay(highlightOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    if isDownloadingMedia {
                        Color.black.opacity(0.35).clipShape(RoundedRectangle(cornerRadius: 10))
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white)
                            .shadow(radius: 6)
                    }
                    
                    VStack(alignment: .trailing) {
                        Spacer()
                        HStack {
                            Spacer()
                            timeAndChecksOverlayOnMedia
                                .padding(.horizontal, 7).padding(.vertical, 5)
                                .background(.black.opacity(0.55), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                                .padding(6)
                        }
                    }
                }
                .frame(width: ChatMediaStyle.size.width, height: ChatMediaStyle.size.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isDownloadingMedia else { return }
                    let ext = remoteURL.pathExtension.isEmpty ? "mp4" : remoteURL.pathExtension
                    Task { await downloadAndPreviewMedia(remoteURL: remoteURL, fileName: "video.\(ext)") }
                }
                .mediaQuickLookSheet(url: $downloadedMediaURL, isPresented: $showMediaQuickLook, error: $mediaDownloadError)
            } else {
                mediaLoadingPlaceholder
            }
        }
    }
    
    private func downloadAndPreviewMedia(remoteURL: URL, fileName: String) async {
        isDownloadingMedia = true
        mediaDownloadError = nil
        defer { isDownloadingMedia = false }
        do {
            let (tmpURL, _) = try await URLSession.shared.download(from: remoteURL)
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(fileName)
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destURL.path) { try FileManager.default.removeItem(at: destURL) }
            try FileManager.default.moveItem(at: tmpURL, to: destURL)
            downloadedMediaURL = destURL
            showMediaQuickLook = true
        } catch {
            mediaDownloadError = error.localizedDescription
        }
    }
    
    @ViewBuilder
    private func replyThumb(for msg: KBChatMessage) -> some View {
        switch msg.type {
        case .photo:
            if let urlString = msg.mediaURL, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, contentMode: .fill)
                    .frame(width: ChatThumbStyle.bubbleReplySize, height: ChatThumbStyle.bubbleReplySize)
                    .clipShape(RoundedRectangle(cornerRadius: ChatThumbStyle.composerCorner))
                    .clipped()
            } else { replyThumbPlaceholder }
        case .video:
            if let t = msg.mediaThumbnailURL, let tu = URL(string: t) {
                CachedAsyncImage(url: tu, contentMode: .fill)
                    .frame(width: ChatThumbStyle.bubbleReplySize, height: ChatThumbStyle.bubbleReplySize)
                    .clipShape(RoundedRectangle(cornerRadius: ChatThumbStyle.composerCorner))
                    .clipped()
            } else if let urlString = msg.mediaURL, let url = URL(string: urlString) {
                VideoThumbnailView(videoURL: url, cacheKey: videoCacheKey(urlString: urlString))
                    .frame(width: ChatThumbStyle.bubbleReplySize, height: ChatThumbStyle.bubbleReplySize)
                    .clipShape(RoundedRectangle(cornerRadius: ChatThumbStyle.composerCorner))
                    .clipped()
            } else { replyThumbPlaceholder }
        case .location:
            if let lat = msg.latitude, let lon = msg.longitude {
                MiniLocationThumb(latitude: lat, longitude: lon)
                    .frame(width: ChatThumbStyle.bubbleReplySize, height: ChatThumbStyle.bubbleReplySize)
                    .clipShape(RoundedRectangle(cornerRadius: ChatThumbStyle.composerCorner))
            } else { replyThumbPlaceholder }
        case .text:
            if let url = cachedReplyLinkURL {
                LinkPreviewThumb(url: url, size: ChatThumbStyle.composerReplySize, corner: ChatThumbStyle.replyCorner)
            }
        default:
            EmptyView()
        }
    }
    
    struct MiniLocationThumb: View {
        let latitude: Double
        let longitude: Double
        private var center: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
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
    
    private var replyThumbPlaceholder: some View {
        RoundedRectangle(cornerRadius: ChatThumbStyle.replyCorner)
            .fill(Color.primary.opacity(0.08))
            .frame(width: ChatThumbStyle.composerReplySize, height: ChatThumbStyle.composerReplySize)
    }
    
    // MARK: - Document
    
    @State private var isDownloadingDoc = false
    @State private var downloadedDocURL: URL?
    @State private var showQuickLook = false
    @State private var docDownloadError: String?
    
    private var documentContent: some View {
        Group {
            if let urlString = message.mediaURL, let remoteURL = URL(string: urlString) {
                Button {
                    guard !isDownloadingDoc else { return }
                    Task { await downloadAndPreviewDoc(remoteURL: remoteURL) }
                } label: {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 12) {
                            ZStack {
                                if isDownloadingDoc {
                                    ProgressView().tint(isOwn ? .white : .accentColor).frame(width: 36, height: 36)
                                } else {
                                    Image(systemName: documentIcon(for: message.text))
                                        .font(.system(size: 28))
                                        .foregroundStyle(isOwn ? .white : .accentColor)
                                        .frame(width: 36)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.text ?? "Documento")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isOwn ? .white : .primary)
                                    .lineLimit(2).multilineTextAlignment(.leading)
                                Text(isDownloadingDoc ? "Download in corso…" : "Tocca per aprire")
                                    .font(.caption2)
                                    .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                        timeAndChecks
                    }
                    .frame(maxWidth: max(maxBubbleWidth - 48, 100))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(DragGesture(minimumDistance: 20).onChanged { _ in })
                .sheet(isPresented: $showQuickLook) {
                    if let url = downloadedDocURL {
                        QuickLookPreview(urls: [url], initialIndex: 0).ignoresSafeArea()
                    }
                }
                .alert("Errore download", isPresented: .constant(docDownloadError != nil)) {
                    Button("OK") { docDownloadError = nil }
                } message: {
                    Text(docDownloadError ?? "")
                }
            } else {
                HStack(spacing: 12) {
                    ProgressView().tint(isOwn ? .white : .accentColor).frame(width: 36)
                    Text(message.text ?? "Documento")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOwn ? .white : .primary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: maxBubbleWidth - 48)
            }
        }
    }
    
    private func downloadAndPreviewDoc(remoteURL: URL) async {
        isDownloadingDoc = true
        docDownloadError = nil
        defer { isDownloadingDoc = false }
        do {
            let (tmpURL, _) = try await URLSession.shared.download(from: remoteURL)
            let fileName = message.text ?? remoteURL.lastPathComponent
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(fileName)
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destURL.path) { try FileManager.default.removeItem(at: destURL) }
            try FileManager.default.moveItem(at: tmpURL, to: destURL)
            downloadedDocURL = destURL
            showQuickLook = true
        } catch {
            docDownloadError = "Impossibile aprire il documento: \(error.localizedDescription)"
        }
    }
    
    private func documentIcon(for fileName: String?) -> String {
        guard let name = fileName?.lowercased() else { return "doc.fill" }
        if name.hasSuffix(".pdf") { return "doc.richtext.fill" }
        if name.hasSuffix(".doc") || name.hasSuffix(".docx") { return "doc.text.fill" }
        if name.hasSuffix(".xls") || name.hasSuffix(".xlsx") { return "tablecells.fill" }
        if name.hasSuffix(".ppt") || name.hasSuffix(".pptx") { return "rectangle.on.rectangle.fill" }
        if name.hasSuffix(".zip") || name.hasSuffix(".rar") { return "archivebox.fill" }
        if name.hasSuffix(".mp3") || name.hasSuffix(".m4a") { return "music.note" }
        return "doc.fill"
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
                .frame(height: 24)
            
            Button { cyclePlaybackRate() } label: {
                Text(playbackRateLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isOwn ? .white : .accentColor)
                    .frame(width: AudioBubble.rateW, height: 28)
                    .background(
                        Capsule()
                            .fill(isOwn ? Color.white.opacity(0.25) : Color.accentColor.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
            .frame(width: AudioBubble.rateW)
        }
        .frame(maxWidth: .infinity, minHeight: AudioBubble.playW, maxHeight: AudioBubble.playW, alignment: .leading)
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
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let p = (v.location.x / geo.size.width).clamped(to: 0...1)
                        dragProgress = p
                        isDraggingSlider = true
                        stopProgressTimer()
                        audioPlayer?.currentTime = p * (audioPlayer?.duration ?? 0)
                    }
                    .onEnded { v in
                        let p = (v.location.x / geo.size.width).clamped(to: 0...1)
                        isDraggingSlider = false
                        playbackProgress = p
                        if let player = audioPlayer {
                            player.currentTime = p * player.duration
                            if isPlayingAudio { startProgressTimer() }
                        } else {
                            Task { await loadPlayerAndSeek(to: p) }
                        }
                    }
            )
        }
    }
    
    private func waveformHeight(index: Int) -> CGFloat {
        CGFloat(6 + abs((message.id.hashValue ^ (index &* 31)) % 15))
    }
    
    private var audioBottomRow: some View {
        HStack(spacing: 4) {
            if let dur = message.mediaDurationSeconds {
                Text(isDraggingSlider ? formatDuration(Int(dragProgress * Double(dur))) : formatDuration(dur))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
                    .animation(.none, value: isDraggingSlider)
            }
            
            Spacer(minLength: 0)
            
            Text(cachedTimeString)
                .font(.caption2)
                .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
            
            if isOwn { syncIcon }
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.and.mic")
                    .font(.caption)
                Text("Trascrizione automatica")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isOwn ? Color.white.opacity(0.78) : .secondary)
            
            switch message.transcriptStatus {
            case .none:
                if let text = message.transcriptPreviewText {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(isOwn ? .white : .primary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
                
            case .processing:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(isOwn ? .white : .accentColor)
                        
                        Text("Trascrizione in corso…")
                            .font(.subheadline)
                            .foregroundStyle(isOwn ? .white.opacity(0.9) : .primary)
                    }
                    
                    if let partial = message.transcriptPreviewText {
                        Text(partial)
                            .font(.subheadline)
                            .foregroundStyle(isOwn ? .white.opacity(0.95) : .primary)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    }
                }
                
            case .completed:
                if let text = message.transcriptPreviewText {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(isOwn ? .white : .primary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                } else {
                    Text("Trascrizione non disponibile")
                        .font(.subheadline)
                        .foregroundStyle(isOwn ? .white.opacity(0.78) : .secondary)
                }
                
            case .failed:
                if let text = message.transcriptPreviewText {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(isOwn ? .white : .primary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                } else {
                    Text("Trascrizione non disponibile")
                        .font(.subheadline)
                        .foregroundStyle(isOwn ? .white.opacity(0.78) : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
    
    private var bottomRow: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(cachedTimeString).font(.caption2).foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
            if isOwn { syncIcon }
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
        Button { onReply() } label: { Label("Rispondi", systemImage: "arrowshape.turn.up.left") }
        Button { onLongPress() } label: { Label("Reagisci", systemImage: "face.smiling") }
        if message.type == .text {
            Button { copyTextToPasteboard() } label: { Label("Copia", systemImage: "doc.on.doc") }
        }
        if isOwn, message.type == .text, let onEdit {
            Button { onEdit() } label: { Label("Modifica", systemImage: "pencil") }
        }
        if let onDelete {
            Button(role: .destructive) { onDelete() } label: { Label("Elimina", systemImage: "trash") }
        }
        
        if message.type == .audio, let transcript = message.transcriptPreviewText, !transcript.isEmpty {
            Button { copyTranscriptToPasteboard() } label: {
                Label("Copia trascrizione", systemImage: "text.badge.checkmark")
            }
        }
    }
    
    private func copyTranscriptToPasteboard() {
        guard let t = message.transcriptPreviewText, !t.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIPasteboard.general.string = t
    }
    
    private func copyTextToPasteboard() {
        let t = (message.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIPasteboard.general.string = t
    }
    
    // MARK: - Placeholder
    
    private var mediaLoadingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground))
                .frame(width: ChatMediaStyle.size.width, height: ChatMediaStyle.size.height)
            ProgressView()
        }
    }
    
    // MARK: - Static helpers (usati nell'init, non nel body)
    
    // FIX 2: static per sottolineare che non accedono a self e possono
    // essere chiamati nell'init senza catturare la struct in modo ricorsivo.
    static func extractFirstURL(from text: String) -> URL? {
        guard let d = Self.sharedLinkDetector else { return nil }
        return d.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)).flatMap { $0.url }
    }
    
    // Singleton: NSDataDetector è costoso da istanziare (~5-10ms la prima volta).
    // Ricrearlo ad ogni bubble (anche nell'init) causava il DynamicBody.updateValue
    // che vedevi nel call stack. Un'istanza condivisa e thread-safe risolve.
    private static let sharedLinkDetector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )
    
    static func buildHighlightedText(_ text: String, searchText: String) -> AttributedString {
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
    
    // MARK: - Style
    
    private var bubbleBackground: Color {
        isOwn ? KBTheme.bubbleTint : Color(.secondarySystemBackground)
    }
    
    private var bubbleShape: some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius: isOwn ? 18 : 4,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: isOwn ? 4 : 18,
            topTrailingRadius: 18
        )
    }
    
    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .purple, .orange, .pink, .teal]
        return colors[abs(message.senderId.hashValue) % colors.count]
    }
    
    private var playbackRateLabel: String {
        switch playbackRate {
        case 1.5: return "1.5×"
        case 2.0: return "2×"
        default: return "1×"
        }
    }
    
    private func cyclePlaybackRate() {
        switch playbackRate {
        case 1.0: playbackRate = 1.5
        case 1.5: playbackRate = 2.0
        default: playbackRate = 1.0
        }
        if let p = audioPlayer, isPlayingAudio { p.enableRate = true; p.rate = playbackRate }
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
        if let player = audioPlayer {
            do {
                try configureAudioSession()
                
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
        guard let us = message.mediaURL, let url = URL(string: us) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try configureAudioSession()
                
                proximityRouter.start()
                let player = try AVAudioPlayer(data: data)
                player.enableRate = true
                player.rate = playbackRate
                let router = proximityRouter
                audioDelegate.onFinish = { [router] in
                    DispatchQueue.main.async {
                        router.stop()
                        self.stopProgressTimer()
                        isPlayingAudio = false
                        self.playbackProgress = 0
                        audioPlayer?.stop()
                        audioPlayer?.currentTime = 0
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
    
    private func loadPlayerAndSeek(to progress: Double) async {
        guard let us = message.mediaURL, let url = URL(string: us) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try configureAudioSession()
            let player = try AVAudioPlayer(data: data)
            player.enableRate = true
            player.rate = playbackRate
            player.prepareToPlay()
            player.currentTime = progress * player.duration
            let router = proximityRouter
            audioDelegate.onFinish = {
                DispatchQueue.main.async {
                    router.stop()
                    self.stopProgressTimer()
                    self.isPlayingAudio = false
                    self.playbackProgress = 0
                    self.audioPlayer?.currentTime = 0
                }
            }
            player.delegate = audioDelegate
            DispatchQueue.main.async {
                self.audioPlayer = player
                self.playbackProgress = progress
            }
        } catch {}
    }
    
    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let p = audioPlayer, p.duration > 0 else { return }
            DispatchQueue.main.async { playbackProgress = p.currentTime / p.duration }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func configureAudioSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playback, mode: .spokenAudio, options: [])
        try s.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func formatDuration(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }
}

// MARK: - LocationBubbleView

private struct LocationBubbleView: View {
    let latitude: Double
    let longitude: Double
    let isOwn: Bool
    @State private var cameraPosition: MapCameraPosition
    
    init(latitude: Double, longitude: Double, isOwn: Bool) {
        self.latitude = latitude
        self.longitude = longitude
        self.isOwn = isOwn
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: $cameraPosition) {
                Marker("Posizione", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)).tint(.red)
            }
            .frame(width: 220, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { openMaps() })
    }
    
    private func openMaps() {
        let label = "Posizione condivisa".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Posizione"
        let appleURL = URL(string: "http://maps.apple.com/?q=\(label)&ll=\(latitude),\(longitude)")!
        if UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!) {
            UIApplication.shared.open(URL(string: "comgooglemaps://?q=\(latitude),\(longitude)")!)
        } else {
            UIApplication.shared.open(appleURL)
        }
    }
}

// MARK: - QuickLook sheet modifier

extension View {
    fileprivate func mediaQuickLookSheet(
        url: Binding<URL?>,
        isPresented: Binding<Bool>,
        error: Binding<String?>
    ) -> some View {
        self
            .sheet(isPresented: isPresented) {
                if let u = url.wrappedValue {
                    QuickLookPreview(urls: [u], initialIndex: 0).ignoresSafeArea()
                }
            }
            .alert("Errore", isPresented: .constant(error.wrappedValue != nil)) {
                Button("OK") { error.wrappedValue = nil }
            } message: {
                Text(error.wrappedValue ?? "")
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
    let url: URL
    let isOwn: Bool
    
    @EnvironmentObject private var store: LinkPreviewStore
    private let reservedHeight: CGFloat = 170
    
    var body: some View {
        Group {
            switch store.previews[url] {
            case .none, .loading:
                placeholder
            case .ready(let meta):
                Button { UIApplication.shared.open(url) } label: { card(meta) }.buttonStyle(.plain)
            case .failed:
                Color.clear.frame(height: reservedHeight)
            }
        }
        .frame(minHeight: reservedHeight)
        .onAppear { store.fetchIfNeeded(for: url) }
    }
    
    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 0).fill(bg.opacity(0.5))
                .frame(maxWidth: .infinity).frame(height: 110)
                .overlay(ProgressView().tint(isOwn ? .white : .accentColor))
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(bg.opacity(0.6)).frame(width: 80, height: 9)
                RoundedRectangle(cornerRadius: 3).fill(bg.opacity(0.5)).frame(width: 140, height: 11)
                RoundedRectangle(cornerRadius: 3).fill(bg.opacity(0.4)).frame(width: 110, height: 9)
            }
            .padding(8)
            Spacer(minLength: 0)
        }
        .frame(height: reservedHeight)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
    
    private func card(_ meta: LinkPreviewMetadata) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let iu = meta.imageURL {
                CachedAsyncImage(url: iu, contentMode: .fill)
                    .frame(maxWidth: .infinity).frame(height: 110).clipped()
            } else {
                RoundedRectangle(cornerRadius: 0).fill(bg.opacity(0.35)).frame(height: 110)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(url.host ?? url.absoluteString)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary).lineLimit(1)
                if let t = meta.title, !t.isEmpty {
                    Text(t).font(.caption.weight(.semibold)).foregroundStyle(isOwn ? .white : .primary).lineLimit(2)
                }
                if let d = meta.description, !d.isEmpty {
                    Text(d).font(.caption2).foregroundStyle(isOwn ? .white.opacity(0.8) : .secondary).lineLimit(2)
                }
            }
            .padding(8)
            Spacer(minLength: 0)
        }
        .frame(height: reservedHeight)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
    
    private var bg: Color {
        isOwn ? .white.opacity(0.15) : Color(.tertiarySystemBackground)
    }
}

// MARK: - SenderAvatarCache
//
// Cache in-memory delle immagini avatar per la sessione corrente.
// Priorità:
//   1) Cache in-memory (già caricato in questa sessione)
//   2) KBUserProfile.avatarData nel ModelContext locale (SwiftData, zero rete)
//   3) Firebase Storage: users/{uid}/avatar.jpg  (user-scoped)
//   4) Firebase Storage: families/{familyId}/avatars/{uid}.jpg  (family-scoped)
// I dati scaricati da Storage vengono salvati in KBUserProfile.avatarData
// così le sessioni successive non fanno più rete.

final class SenderAvatarCache {
    static let shared = SenderAvatarCache()
    private init() {}
    
    private var cache: [String: Any] = [:]   // UIImage | NSNull
    private var inFlight: Set<String> = []
    
    func cachedImage(for uid: String) -> UIImage? { cache[uid] as? UIImage }
    func isFailed(for uid: String) -> Bool { cache[uid] is NSNull }
    
    func loadImage(
        for uid: String,
        familyId: String,
        modelContext: ModelContext
    ) async -> UIImage? {
        // 1) cache in-memory
        if let img = cache[uid] as? UIImage { return img }
        if cache[uid] is NSNull { return nil }
        if inFlight.contains(uid) { return nil }
        inFlight.insert(uid)
        defer { inFlight.remove(uid) }
        
        // 2) SwiftData locale
        let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
        if let profile = try? modelContext.fetch(desc).first,
           let data = profile.avatarData,
           let img = UIImage(data: data) {
            cache[uid] = img
            return img
        }
        
        // 3+4) Firebase Storage
        let storage = Storage.storage()
        let img: UIImage?
        
        if let i = await downloadImage(ref: storage.reference().child("users/\(uid)/avatar.jpg")) {
            img = i
        } else if !familyId.isEmpty,
                  let i = await downloadImage(ref: storage.reference().child("families/\(familyId)/avatars/\(uid).jpg")) {
            img = i
        } else {
            img = nil
        }
        
        guard let img else {
            cache[uid] = NSNull()
            return nil
        }
        
        cache[uid] = img
        
        // Persisti in locale così la prossima sessione non fa rete
        if let data = img.jpegData(compressionQuality: 0.8) {
            let desc2 = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
            if let profile = try? modelContext.fetch(desc2).first {
                profile.avatarData = data
                try? modelContext.save()
            }
        }
        
        return img
    }
    
    private func downloadImage(ref: StorageReference) async -> UIImage? {
        do {
            let data = try await ref.data(maxSize: 5 * 1024 * 1024)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

// MARK: - SenderAvatarView

struct SenderAvatarView: View {
    let senderId: String
    let familyId: String
    let senderName: String
    let fallbackColor: Color
    
    @Environment(\.modelContext) private var modelContext
    @State private var image: UIImage? = nil
    
    var body: some View {
        // ZStack con dimensione fissa e stabile: SwiftUI non rimisura mai questa view,
        // anche quando image passa da nil a UIImage — evita measureBackwards nel LazyVStack.
        ZStack {
            Circle().fill(fallbackColor)
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Text(senderName.prefix(1).uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 32, height: 32)
        .fixedSize()
        .task(id: senderId) {
            guard !senderId.isEmpty else { return }
            if let img = await SenderAvatarCache.shared.loadImage(
                for: senderId,
                familyId: familyId,
                modelContext: modelContext
            ) {
                await MainActor.run { image = img }
            }
        }
    }
}

extension Comparable {
    fileprivate func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}
