//
//  ChatBubble.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//

import AVFoundation
import AVKit
import MapKit
import SwiftUI

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
    
    @State private var containerWidth: CGFloat = 0
    
    // Media QuickLook (foto, video, documento)
    @State private var isDownloadingMedia = false
    @State private var downloadedMediaURL: URL?
    @State private var showMediaQuickLook = false
    @State private var mediaDownloadError: String?
    
    // Swipe-to-reply
    @State private var swipeX: CGFloat = 0
    
    private var maxBubbleWidth: CGFloat {
        let w = max(containerWidth, 0)
        switch dynamicTypeSize {
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4,
                .accessibility5:
            return min(w * 0.68, 420)
        default:
            return min(w * 0.72, 420)
        }
    }
    
    private enum ChatMediaStyle {
        static let size = CGSize(width: 220, height: 160)
        static let corner: CGFloat = 14
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
    
    private var hasLinkPreview: Bool {
        guard message.type == .text else { return false }
        return extractFirstURL(from: message.text ?? "") != nil
    }
    
    private var shouldConstrainToMaxWidth: Bool {
        // Se c'è reply header o link preview, vogliamo una larghezza "stabile" e non full screen
        (message.replyToId != nil) || hasLinkPreview
    }
    
    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 2) {
            
            let name = message.senderName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
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
                                guard
                                    abs(v.translation.width)
                                        > abs(v.translation.height)
                                else { return }
                                guard v.translation.width > 0 else { return }
                                swipeX = min(28, v.translation.width / 3)
                            }
                            .onEnded { v in
                                let shouldTrigger =
                                v.translation.width > 70
                                && abs(v.translation.width)
                                > abs(v.translation.height)
                                withAnimation(
                                    .spring(
                                        response: 0.25,
                                        dampingFraction: 0.8
                                    )
                                ) { swipeX = 0 }
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
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { containerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { oldValue, newValue in
                        containerWidth = newValue
                    }
            }
        )
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
        } else if message.type == .photo || message.type == .video
        {
            // Foto, video, posizione: nessuna cornice colorata
            // clipShape e shadow applicati al solo contenuto visivo (non al VStack esterno)
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
            // Document: come testo ma con allowsHitTesting esplicito per non bloccare il swipe
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
            .contentShape(Rectangle())  // superficie completa per il swipe
        } else if message.type == .location {
            // Location: serve contentShape per ricevere il swipe nonostante la Map interna
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
            .contentShape(Rectangle())   // ← questo è il fix: swipe ricevuto anche sulla mappa
            
        } else {
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
    
    private var timeAndChecksOverlayOnMedia: some View {
        HStack(spacing: 4) {
            if message.editedAt != nil {
                Text("Modificato")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }
            
            Text(message.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.9))
            
            if isOwn { syncIconOverlayOnMedia }
        }
        .fixedSize()
    }
    
    @ViewBuilder
    private var syncIconOverlayOnMedia: some View {
        switch message.syncState {
        case .pendingUpsert, .pendingDelete:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.yellow) // su sfondo scuro è più leggibile del rosso
        case .synced:
            let isRead = !message.readBy.isEmpty
            HStack(spacing: -4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isRead ? .white.opacity(0.9) : .white.opacity(0.0))
            }
        }
    }
    
    private var timeAndChecks: some View {
        HStack(spacing: 4) {
            if message.editedAt != nil {
                Text("Modificato")
                    .font(.caption2)
                    .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
            }
            
            Text(message.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
            if isOwn { syncIcon }
        }
        .fixedSize()  // important: non deve espandere
    }
    
    @ViewBuilder
    private var highlightOverlay: some View {
        if isHighlighted {
            bubbleShape
                .fill(
                    isOwn
                    ? Color.white.opacity(0.18)
                    : Color.accentColor.opacity(0.12)
                )
                .overlay(
                    bubbleShape.stroke(
                        isOwn
                        ? Color.white.opacity(0.85)
                        : Color.accentColor.opacity(0.85),
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
                        .foregroundStyle(
                            isOwn ? Color.white.opacity(0.9) : Color.accentColor
                        )
                        .lineLimit(1)
                    
                    replySubtitle
                        .font(.caption2)
                        .foregroundStyle(
                            isOwn ? Color.white.opacity(0.75) : Color.secondary
                        )
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isOwn
                ? Color.white.opacity(0.12)
                : Color.accentColor.opacity(0.08),
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
                let t = (repliedTo.text ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let url = extractFirstURL(from: t) {
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
                let label =
                d > 0
                ? "Messaggio vocale • \(formatDuration(d))"
                : "Messaggio vocale"
                
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.caption2)
                    Text(label)
                }
                
            case .document:
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.caption2)
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
            
            Text("Posizione condivisa")
                .font(.caption)
        }
        .onTapGesture {
            openInMaps()
        }
    }
    
    private func openInMaps() {
        guard let lat = message.latitude,
              let lon = message.longitude
        else { return }
        
        let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lon)")!
        UIApplication.shared.open(url)
    }
    
    func highlightedText(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        
        guard !searchText.isEmpty else { return attr }
        
        let lower = text.lowercased()
        let query = searchText.lowercased()
        
        var searchRange = lower.startIndex..<lower.endIndex
        
        while let range = lower.range(
            of: query,
            options: [],
            range: searchRange
        ) {
            if let attrRange = Range(range, in: attr) {
                attr[attrRange].backgroundColor = .yellow.opacity(0.4)
            }
            searchRange = range.upperBound..<lower.endIndex
        }
        
        return attr
    }
    
    private struct LocationBubbleView: View {
        
        let latitude: Double
        let longitude: Double
        let isOwn: Bool
        
        @State private var cameraPosition: MapCameraPosition
        
        init(latitude: Double, longitude: Double, isOwn: Bool) {
            self.latitude = latitude
            self.longitude = longitude
            self.isOwn = isOwn
            
            let coordinate = CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )
            
            _cameraPosition = State(
                initialValue:
                        .region(
                            MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(
                                    latitudeDelta: 0.01,
                                    longitudeDelta: 0.01
                                )
                            )
                        )
            )
        }
        
        var body: some View {
            ZStack(alignment: .bottomLeading) {
                Map(position: $cameraPosition) {
                    Marker(
                        "Posizione",
                        coordinate: CLLocationCoordinate2D(
                            latitude: latitude,
                            longitude: longitude
                        )
                    )
                    .tint(.red)
                }
                .frame(
                    width: ChatMediaStyle.size.width,
                    height: ChatMediaStyle.size.height
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            // ✅ FIX: simultaneousGesture permette al tap di coesistere
            // col DragGesture del parent bubble (swipe-to-reply)
            .simultaneousGesture(
                TapGesture().onEnded {
                    openMaps()
                }
            )
        }
        
        private func openMaps() {
            let lat = latitude
            let lon = longitude
            let label =
            "Posizione condivisa".addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? "Posizione"
            
            // Apple Maps (web URL -> app)
            let appleURL = URL(
                string: "http://maps.apple.com/?q=\(label)&ll=\(lat),\(lon)"
            )!
            
            // Google Maps (app scheme)
            if UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!)
            {
                let googleURL = URL(string: "comgooglemaps://?q=\(lat),\(lon)")!
                UIApplication.shared.open(googleURL)
            } else {
                UIApplication.shared.open(appleURL)
            }
        }
    }
    
    // MARK: - Bubble content (non-audio)
    
    @ViewBuilder
    private var bubbleContent: some View {
        switch message.type {
        case .text:
            let text = message.text ?? ""
            let linkURL = ChatLinkDetector.firstURL(in: text)
            
            VStack(alignment: .leading, spacing: 4) {
                
                if let url = linkURL {
                    // Con link: testo semplice → preview → timeAndChecks solo in fondo
                    Text(highlightedText(text))
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
                    // Senza link: inline se ci sta, altrimenti testo + ora sotto
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(highlightedText(text))
                                .font(.body)
                                .foregroundStyle(isOwn ? .white : .primary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: true)
                            timeAndChecks
                        }
                        .fixedSize(horizontal: true, vertical: true)
                        
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
                        .frame(
                            maxWidth: max(maxBubbleWidth - 24, 100),
                            alignment: .leading
                        )
                    }
                }
            }
        case .photo: photoContent
        case .video: videoContent
        case .audio: EmptyView()
        case .document: documentContent
        case .location:
            if let lat = message.latitude,
               let lon = message.longitude
            {
                ZStack(alignment: .bottomTrailing) {
                    LocationBubbleView(
                        latitude: lat,
                        longitude: lon,
                        isOwn: isOwn
                    )
                    timeAndChecksOverlayOnMedia
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        )
                        .padding(6)
                }
            }
        }
    }
    
    // MARK: - Photo / Video
    
    private var photoContent: some View {
        Group {
            if let urlString = message.mediaURL,
               let remoteURL = URL(string: urlString)
            {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: remoteURL, contentMode: .fill)
                        .frame(
                            width: ChatMediaStyle.size.width,
                            height: ChatMediaStyle.size.height
                        )
                        .overlay(highlightOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    if isDownloadingMedia {
                        Color.black.opacity(0.35)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        ProgressView().tint(.white)
                            .frame(
                                width: ChatMediaStyle.size.width,
                                height: ChatMediaStyle.size.height
                            )
                    }
                    
                    timeAndChecksOverlayOnMedia
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        )
                        .padding(6)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isDownloadingMedia else { return }
                    Task {
                        await downloadAndPreviewMedia(
                            remoteURL: remoteURL,
                            fileName: "immagine.jpg"
                        )
                    }
                }
                .mediaQuickLookSheet(
                    url: $downloadedMediaURL,
                    isPresented: $showMediaQuickLook,
                    error: $mediaDownloadError
                )
            } else {
                mediaLoadingPlaceholder
            }
        }
    }
    
    private func copyTextToPasteboard() {
        let t = (message.text ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !t.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIPasteboard.general.string = t
    }
    
    private var videoContent: some View {
        Group {
            if let urlString = message.mediaURL,
               let remoteURL = URL(string: urlString)
            {
                ZStack {
                    VideoThumbnailView(
                        videoURL: remoteURL,
                        cacheKey: videoCacheKey(urlString: urlString)
                    )
                    .frame(
                        width: ChatMediaStyle.size.width,
                        height: ChatMediaStyle.size.height
                    )
                    .clipped()
                    .overlay(highlightOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    if isDownloadingMedia {
                        Color.black.opacity(0.35)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
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
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.55), in: Capsule())
                                .overlay(
                                    Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                                )
                                .padding(6)
                        }
                    }
                }
                .frame(
                    width: ChatMediaStyle.size.width,
                    height: ChatMediaStyle.size.height
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isDownloadingMedia else { return }
                    let ext = remoteURL.pathExtension.isEmpty ? "mp4" : remoteURL.pathExtension
                    Task {
                        await downloadAndPreviewMedia(
                            remoteURL: remoteURL,
                            fileName: "video.\(ext)"
                        )
                    }
                }
                .mediaQuickLookSheet(
                    url: $downloadedMediaURL,
                    isPresented: $showMediaQuickLook,
                    error: $mediaDownloadError
                )
            } else {
                mediaLoadingPlaceholder
            }
        }
    }
    
    // MARK: - Shared download + QuickLook
    
    private func downloadAndPreviewMedia(remoteURL: URL, fileName: String) async
    {
        isDownloadingMedia = true
        mediaDownloadError = nil
        defer { isDownloadingMedia = false }
        
        do {
            let (tmpURL, _) = try await URLSession.shared.download(
                from: remoteURL
            )
            
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(fileName)
            
            try FileManager.default.createDirectory(
                at: destURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
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
            } else {
                replyThumbPlaceholder
            }
            
        case .video:
            // Se hai già una thumbnail URL salvata, usa quella (super leggero)
            if let t = msg.mediaThumbnailURL, let tu = URL(string: t) {
                CachedAsyncImage(url: tu, contentMode: .fill)
                frame(width: ChatThumbStyle.bubbleReplySize, height: ChatThumbStyle.bubbleReplySize)
                    .clipShape(RoundedRectangle(cornerRadius: ChatThumbStyle.composerCorner))
                    .clipped()
            } else if let urlString = msg.mediaURL, let url = URL(string: urlString) {
                // Fallback: genera thumb dal video (più costoso ma ok in piccolo)
                VideoThumbnailView(videoURL: url, cacheKey: videoCacheKey(urlString: urlString))
                    .frame(width: ChatThumbStyle.bubbleReplySize, height: ChatThumbStyle.bubbleReplySize)
                    .clipShape(RoundedRectangle(cornerRadius: ChatThumbStyle.composerCorner))
                    .clipped()
            } else {
                replyThumbPlaceholder
            }
            
        case .location:
            if let lat = msg.latitude, let lon = msg.longitude {
                MiniLocationThumb(latitude: lat, longitude: lon)
                    .frame(width: ChatThumbStyle.bubbleReplySize, height: ChatThumbStyle.bubbleReplySize)
                    .clipShape(RoundedRectangle(cornerRadius: ChatThumbStyle.composerCorner))
            } else {
                replyThumbPlaceholder
            }
            
        case .text:
            if let t = msg.text, let url = ChatLinkDetector.firstURL(in: t) {
                LinkPreviewThumb(url: url, size: ChatThumbStyle.composerReplySize, corner: ChatThumbStyle.replyCorner)
            }
            
        default:
            EmptyView()
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
            if let urlString = message.mediaURL,
               let remoteURL = URL(string: urlString)
            {
                Button {
                    guard !isDownloadingDoc else { return }
                    Task { await downloadAndPreviewDoc(remoteURL: remoteURL) }
                } label: {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 12) {
                            ZStack {
                                if isDownloadingDoc {
                                    ProgressView()
                                        .tint(isOwn ? .white : .accentColor)
                                        .frame(width: 36, height: 36)
                                } else {
                                    Image(
                                        systemName: documentIcon(
                                            for: message.text
                                        )
                                    )
                                    .font(.system(size: 28))
                                    .foregroundStyle(
                                        isOwn ? .white : .accentColor
                                    )
                                    .frame(width: 36)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.text ?? "Documento")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isOwn ? .white : .primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(
                                    isDownloadingDoc
                                    ? "Download in corso…"
                                    : "Tocca per aprire"
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    isOwn ? .white.opacity(0.7) : .secondary
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                        timeAndChecks
                    }
                    .frame(maxWidth: max(maxBubbleWidth - 48, 100))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)   // lascia passare il swipe al padre
                        .onChanged { _ in }
                )
                .sheet(isPresented: $showQuickLook) {
                    if let url = downloadedDocURL {
                        QuickLookPreview(urls: [url], initialIndex: 0)
                            .ignoresSafeArea()
                    }
                }
                .alert(
                    "Errore download",
                    isPresented: .constant(docDownloadError != nil)
                ) {
                    Button("OK") { docDownloadError = nil }
                } message: {
                    Text(docDownloadError ?? "")
                }
            } else {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(isOwn ? .white : .accentColor)
                        .frame(width: 36)
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
            let (tmpURL, _) = try await URLSession.shared.download(
                from: remoteURL
            )
            let fileName = message.text ?? remoteURL.lastPathComponent
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(fileName)
            try FileManager.default.createDirectory(
                at: destURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: tmpURL, to: destURL)
            downloadedDocURL = destURL
            showQuickLook = true
        } catch {
            docDownloadError =
            "Impossibile aprire il documento: \(error.localizedDescription)"
        }
    }
    
    private func documentIcon(for fileName: String?) -> String {
        guard let name = fileName?.lowercased() else { return "doc.fill" }
        if name.hasSuffix(".pdf") { return "doc.richtext.fill" }
        if name.hasSuffix(".doc") || name.hasSuffix(".docx") {
            return "doc.text.fill"
        }
        if name.hasSuffix(".xls") || name.hasSuffix(".xlsx") {
            return "tablecells.fill"
        }
        if name.hasSuffix(".ppt") || name.hasSuffix(".pptx") {
            return "rectangle.on.rectangle.fill"
        }
        if name.hasSuffix(".zip") || name.hasSuffix(".rar") {
            return "archivebox.fill"
        }
        if name.hasSuffix(".mp3") || name.hasSuffix(".m4a") {
            return "music.note"
        }
        return "doc.fill"
    }
    
    private func videoCacheKey(urlString: String) -> String {
        if var c = URLComponents(string: urlString) {
            c.query = nil
            return c.string ?? urlString
        }
        return urlString
    }
    
    // MARK: - Audio content
    
    private var audioContent: some View {
        HStack(alignment: .center, spacing: AudioBubble.spacing) {
            Button {
                toggleAudio()
            } label: {
                Image(
                    systemName: isPlayingAudio
                    ? "pause.circle.fill" : "play.circle.fill"
                )
                .font(.title2)
                .foregroundStyle(isOwn ? .white : .accentColor)
            }
            .buttonStyle(.plain)
            .frame(width: AudioBubble.playW, height: AudioBubble.playW)
            .accessibilityLabel(
                isPlayingAudio ? "Pausa audio" : "Riproduci audio"
            )
            
            scrubbableWaveform
                .frame(width: AudioBubble.waveW, height: 24)
            
            Button {
                cyclePlaybackRate()
            } label: {
                Text(playbackRateLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isOwn ? .white : .accentColor)
                    .frame(width: AudioBubble.rateW, height: 28)
                    .background(
                        Capsule().fill(
                            isOwn
                            ? Color.white.opacity(0.25)
                            : Color.accentColor.opacity(0.15)
                        )
                    )
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
                        let played =
                        Double(i) / 20.0
                        < (isDraggingSlider
                           ? dragProgress : playbackProgress)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                isOwn
                                ? (played
                                   ? Color.white
                                   : Color.white.opacity(0.35))
                                : (played
                                   ? Color.accentColor
                                   : Color.accentColor.opacity(0.3))
                            )
                            .frame(width: 5, height: waveformHeight(index: i))
                    }
                }
                let prog = isDraggingSlider ? dragProgress : playbackProgress
                Circle()
                    .fill(isOwn ? Color.white : Color.accentColor)
                    .frame(
                        width: isDraggingSlider ? 14 : 10,
                        height: isDraggingSlider ? 14 : 10
                    )
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                    .offset(
                        x: prog * geo.size.width - (isDraggingSlider ? 7 : 5)
                    )
                    .animation(
                        .easeInOut(duration: 0.1),
                        value: isDraggingSlider
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let p = (v.location.x / geo.size.width).clamped(
                            to: 0...1
                        )
                        dragProgress = p
                        isDraggingSlider = true
                        stopProgressTimer()
                        audioPlayer?.currentTime =
                        p * (audioPlayer?.duration ?? 0)
                    }
                    .onEnded { v in
                        let p = (v.location.x / geo.size.width).clamped(
                            to: 0...1
                        )
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
    
    // MARK: - Bottom rows
    
    // Audio: durata a sx, orario a dx — larghezza fissa
    private var audioBottomRow: some View {
        HStack(spacing: 4) {
            if let dur = message.mediaDurationSeconds {
                Text(
                    isDraggingSlider
                    ? formatDuration(Int(dragProgress * Double(dur)))
                    : formatDuration(dur)
                )
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
            Image(systemName: "clock").font(.caption2).foregroundStyle(
                .white.opacity(0.6)
            )
        case .error:
            Image(systemName: "exclamationmark.circle.fill").font(.caption2)
                .foregroundStyle(.red)
        case .synced:
            let isRead = !message.readBy.isEmpty
            HStack(spacing: -4) {
                Image(systemName: "checkmark").font(
                    .system(size: 9, weight: .bold)
                )
                .foregroundStyle(
                    isRead ? Color.white : Color.white.opacity(0.6)
                )
                Image(systemName: "checkmark").font(
                    .system(size: 9, weight: .bold)
                )
                .foregroundStyle(isRead ? Color.white : Color.clear)
            }
        }
    }
    
    // MARK: - Reactions
    
    private var reactionRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(message.reactions.keys.sorted()), id: \.self) {
                emoji in
                let count = message.reactions[emoji]?.count ?? 0
                Button {
                    onReactionTap(emoji)
                } label: {
                    HStack(spacing: 2) {
                        Text(emoji).font(.caption)
                        if count > 1 {
                            Text("\(count)").font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color(.tertiarySystemBackground), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(
                            Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Context menu
    
    @ViewBuilder
    private var contextMenuItems: some View {
        Button { onReply() } label: { Label("Rispondi", systemImage: "arrowshape.turn.up.left") }
        Button {
            onLongPress()
        } label: {
            Label("Reagisci", systemImage: "face.smiling")
        }
        
        if message.type == .text {
            Button {
                copyTextToPasteboard()
            } label: {
                Label("Copia", systemImage: "doc.on.doc")
            }
        }
        
        if isOwn, message.type == .text, let onEdit {
            Button {
                onEdit()
            } label: {
                Label("Modifica", systemImage: "pencil")
            }
        }
        
        if let onDelete {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Elimina", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Placeholder
    
    private var mediaLoadingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(
                Color(.tertiarySystemBackground)
            )
            .frame(
                width: ChatMediaStyle.size.width,
                height: ChatMediaStyle.size.height
            )
            ProgressView()
        }
    }
    
    // MARK: - Link helpers
    
    private func extractFirstURL(from text: String) -> URL? {
        guard
            let d = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue
            )
        else { return nil }
        return d.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ).flatMap { $0.url }
    }
    
    private func makeAttributedText(_ text: String) -> AttributedString {
        var attr =
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
        guard
            let d = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue
            )
        else { return attr }
        d.enumerateMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ) { m, _, _ in
            guard let m, let url = m.url,
                  let sr = Range(m.range, in: text), let ar = Range(sr, in: attr)
            else { return }
            attr[ar].link = url
            attr[ar].foregroundColor =
            isOwn ? UIColor.white : UIColor.systemBlue
            attr[ar].underlineStyle = .single
        }
        return attr
    }
    
    // MARK: - Style
    
    private var bubbleBackground: Color {
        isOwn ? .accentColor : Color(.secondarySystemBackground)
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
        if let p = audioPlayer, isPlayingAudio {
            p.enableRate = true
            p.rate = playbackRate
        }
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
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(
                    .speaker
                )
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
        guard let us = message.mediaURL, let url = URL(string: us) else {
            return
        }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try configureAudioSession()
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(
                    .speaker
                )
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
        guard let us = message.mediaURL, let url = URL(string: us) else {
            return
        }
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
        progressTimer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: true
        ) { _ in
            guard let p = audioPlayer, p.duration > 0 else { return }
            DispatchQueue.main.async {
                playbackProgress = p.currentTime / p.duration
            }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func configureAudioSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try s.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func formatDuration(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }
}

// MARK: - QuickLook sheet modifier (per foto e video)

extension View {
    fileprivate func mediaQuickLookSheet(
        url: Binding<URL?>,
        isPresented: Binding<Bool>,
        error: Binding<String?>
    ) -> some View {
        self
            .sheet(isPresented: isPresented) {
                if let u = url.wrappedValue {
                    QuickLookPreview(urls: [u], initialIndex: 0)
                        .ignoresSafeArea()
                }
            }
            .alert("Errore", isPresented: .constant(error.wrappedValue != nil))
        {
            Button("OK") { error.wrappedValue = nil }
        } message: {
            Text(error.wrappedValue ?? "")
        }
    }
}

// MARK: - ChatBubbleAudioDelegate

final class ChatBubbleAudioDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) { onFinish?() }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?)
    { onFinish?() }
}

// MARK: - LinkPreviewView

private struct LinkPreviewView: View {
    let url: URL
    let isOwn: Bool
    
    @EnvironmentObject private var store: LinkPreviewStore
    
    // Altezza totale riservata sempre: immagine 110 + testo ~60 = 170pt.
    // Sia il placeholder che la card finale occupano esattamente questo spazio,
    // così la LazyVStack non ricalcola mai la posizione delle bubble sopra.
    private let reservedHeight: CGFloat = 170
    
    var body: some View {
        Group {
            switch store.previews[url] {
            case .none, .loading:
                placeholder
            case .ready(let meta):
                Button { UIApplication.shared.open(url) } label: { card(meta) }
                    .buttonStyle(.plain)
            case .failed:
                // Anche in caso di fallimento manteniamo l'altezza riservata
                // con un placeholder invisibile, così non c'è resize nemmeno in questo caso.
                Color.clear.frame(height: reservedHeight)
            }
        }
        .frame(minHeight: reservedHeight)   // garantisce altezza minima sempre uguale
        .onAppear { store.fetchIfNeeded(for: url) }
    }
    
    // Placeholder con stessa struttura della card: immagine skeleton + testo skeleton
    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Zona immagine skeleton
            RoundedRectangle(cornerRadius: 0)
                .fill(bg.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .overlay(ProgressView().tint(isOwn ? .white : .accentColor))
            // Zona testo skeleton
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
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 0)
                    .fill(bg.opacity(0.35))
                    .frame(height: 110)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(url.host ?? url.absoluteString)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isOwn ? .white.opacity(0.7) : .secondary)
                    .lineLimit(1)
                if let t = meta.title, !t.isEmpty {
                    Text(t).font(.caption.weight(.semibold))
                        .foregroundStyle(isOwn ? .white : .primary).lineLimit(2)
                }
                if let d = meta.description, !d.isEmpty {
                    Text(d).font(.caption2)
                        .foregroundStyle(isOwn ? .white.opacity(0.8) : .secondary)
                        .lineLimit(2)
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

extension Comparable {
    fileprivate func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}
