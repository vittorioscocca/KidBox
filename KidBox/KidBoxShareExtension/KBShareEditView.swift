//
//  KBShareEditView.swift
//  KidBoxShareExtension
//

import SwiftUI
import UIKit
import AVFoundation
import os.log

private enum ShareSendResult {
    case completedInExtension
    case deferredToMainApp(urlString: String, showBanner: Bool)
    case videoDeferredToMainApp
}

private struct ParsedEventShare {
    let title: String
    let notes: String
    let detectedDate: Date?
}

struct KBShareEditView: View {
    let destination: KBShareDestination
    let payload: KBSharePayload
    let onDone: () -> Void
    let onOpenApp: (String) -> Void
    weak var extensionContext: NSExtensionContext?
    
    @State private var editedText: String = ""
    @State private var editedTitle: String = ""
    @State private var isSending = false
    @State private var hasSent = false
    @State private var errorMessage: String? = nil
    @State private var remoteImage: UIImage? = nil
    @State private var videoSavedToAppGroup = false
    @State private var deferredBannerDestination: KBShareDestination? = nil
    @FocusState private var inputFocused: Bool
    @State private var videoThumbnail: UIImage? = nil
    
    private let appGroupId = "group.it.vittorioscocca.kidbox"
    private let logger = Logger(subsystem: "it.vittorioscocca.KidBox.ShareExtension", category: "KBShareEditView")
    
    private func log(_ message: String) {
        logger.debug("[KBShareEditView] \(message, privacy: .public)")
        print("[KBShareEditView] \(message)")
    }
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if videoSavedToAppGroup {
                ScrollView { videoSuccessView }
            } else if let deferredDestination = deferredBannerDestination {
                ScrollView { deferredSuccessView(for: deferredDestination) }
            } else if destination == .chat {
                chatLayout
            } else {
                standardLayout
            }
        }
        .navigationTitle(destination.label)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            prefillFields()
            if destination == .chat, case .text = payload.type {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    inputFocused = true
                }
            }
        }
        .onChange(of: destination) { _, _ in prefillFields() }
    }
    
    // MARK: - Chat layout
    
    private var isTextOnlyPayload: Bool {
        if case .text = payload.type { return true }
        return false
    }
    
    private var chatLayout: some View {
        VStack(spacing: 0) {
            if isTextOnlyPayload {
                Spacer()
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Modifica il messaggio…", text: $editedText, axis: .vertical)
                        .lineLimit(1...10)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                        .focused($inputFocused)
                    sendCircleButton
                        .disabled(isSending || editedText.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        mediaPreview
                            .padding(.top, 20)
                            .padding(.horizontal, 16)
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption).foregroundStyle(.red)
                                .padding(.horizontal, 20)
                        }
                        sendBigButton
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                }
            }
            
            if isTextOnlyPayload, let error = errorMessage {
                Text(error)
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .task { await generateVideoThumbnailIfNeeded() }
    }
    
    // MARK: - Send circle (tasto freccia ↑, per testo)
    
    private var sendCircleButton: some View {
        Button { Task { await sendToDestination() } } label: {
            Group {
                if isSending {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .frame(width: 36, height: 36)
            .background(
                editedText.isEmpty ? Color.secondary.opacity(0.4) : destination.color,
                in: Circle()
            )
            .foregroundStyle(.white)
        }
        .disabled(isSending || editedText.isEmpty)
    }
    
    // MARK: - Send big button (media/file)
    
    private var sendBigButton: some View {
        Button { Task { await sendToDestination() } } label: {
            HStack(spacing: 12) {
                if isSending {
                    ProgressView().tint(.white)
                    Text("Invio in corso…")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Invia in chat")
                        .font(.subheadline.bold())
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(destination.color, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: destination.color.opacity(0.35), radius: 8, y: 4)
        }
        .disabled(isSending)
    }
    
    // MARK: - Media preview (chat, non-testo)
    
    @ViewBuilder
    private var mediaPreview: some View {
        switch payload.type {
            
        case .image(let url):
            if let url, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 340)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            }
            
        case .file(let url):
            let ext = url.pathExtension.lowercased()
            let isVideo = ["mp4", "mov", "m4v"].contains(ext)
            let isImg   = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"].contains(ext)
            if isVideo {
                videoPreviewCard(for: url)
            } else if isImg, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 340)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            } else {
                documentPreviewCard(for: url)
            }
            
        case .url(let u):
            if let fileURL = URL(string: u), fileURL.isFileURL {
                let ext = fileURL.pathExtension.lowercased()
                if ["mp4", "mov", "m4v"].contains(ext) {
                    videoPreviewCard(for: fileURL)
                } else {
                    documentPreviewCard(for: fileURL)
                }
            } else if isImageURL(u) {
                Group {
                    if let img = remoteImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 340)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 200)
                            .overlay(ProgressView())
                    }
                }
                .task {
                    guard let url = URL(string: u),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          let img = UIImage(data: data) else { return }
                    remoteImage = img
                }
            } else {
                linkPreviewCard(urlString: u)
            }
            
        default:
            EmptyView()
        }
    }
    
    // MARK: - Video preview card
    
    private func videoPreviewCard(for url: URL) -> some View {
        ZStack(alignment: .center) {
            Group {
                if let thumb = videoThumbnail {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.black.opacity(0.75))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.20), radius: 12, y: 4)
            
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 2)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "video.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(url.lastPathComponent)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Document preview card
    
    private func documentPreviewCard(for url: URL) -> some View {
        HStack(spacing: 16) {
            Image(systemName: fileIcon(for: url))
                .font(.system(size: 28))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(destination.color, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: destination.color.opacity(0.4), radius: 6, y: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(url.pathExtension.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
    
    // MARK: - Link preview card
    
    private func linkPreviewCard(urlString: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(destination.color)
            VStack(alignment: .leading, spacing: 4) {
                Text("Link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(urlString)
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
    
    // MARK: - Video thumbnail generation
    
    private func generateVideoThumbnailIfNeeded() async {
        let videoURL: URL?
        switch payload.type {
        case .file(let url):
            let ext = url.pathExtension.lowercased()
            videoURL = ["mp4", "mov", "m4v"].contains(ext) ? url : nil
        case .url(let u):
            if let fu = URL(string: u), fu.isFileURL {
                let ext = fu.pathExtension.lowercased()
                videoURL = ["mp4", "mov", "m4v"].contains(ext) ? fu : nil
            } else { videoURL = nil }
        default:
            videoURL = nil
        }
        guard let url = videoURL else { return }
        let thumb = await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 800, height: 800)
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            guard let cgImg = try? gen.copyCGImage(at: time, actualTime: nil) else { return nil as UIImage? }
            return UIImage(cgImage: cgImg)
        }.value
        await MainActor.run { videoThumbnail = thumb }
    }
    
    // MARK: - Standard layout (non-chat)
    
    private var standardLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                payloadPreview.padding(.top, 8)
                editFields
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }
                Spacer(minLength: 40)
                Button {
                    Task { await sendToDestination() }
                } label: {
                    HStack {
                        if isSending {
                            ProgressView().tint(.white)
                            Text("Invio in corso…")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: destination.icon)
                            Text(confirmLabel)
                        }
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(destination.color, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isSending)
            }
            .padding()
        }
    }
    
    // MARK: - Success views
    
    private var videoSuccessView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            VStack(spacing: 8) {
                Text("Video pronto")
                    .font(.title2.bold())
                Text("Apri KidBox per completare l'invio in chat.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                onOpenApp("kidbox://share?destination=chat")
            } label: {
                Label("Apri KidBox", systemImage: "arrow.up.right.app.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
            }
            Button("Annulla") {
                UserDefaults(suiteName: appGroupId)?.removeObject(forKey: "pendingShare")
                onDone()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Spacer(minLength: 40)
        }
        .padding(32)
    }
    
    @ViewBuilder
    private func deferredSuccessView(for destination: KBShareDestination) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            VStack(spacing: 8) {
                Text("Quasi fatto")
                    .font(.title2.bold())
                Text(messageForDeferredBanner(destination))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                onOpenApp("kidbox://share?destination=\(destination.rawStringValue)")
            } label: {
                Label("Apri KidBox", systemImage: "arrow.up.right.app.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(destination.color, in: RoundedRectangle(cornerRadius: 14))
            }
            Button("Annulla") {
                UserDefaults(suiteName: appGroupId)?.removeObject(forKey: "pendingShare")
                onDone()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Spacer(minLength: 40)
        }
        .padding(32)
    }
    
    private func messageForDeferredBanner(_ destination: KBShareDestination) -> String {
        switch destination {
        case .chat:           return "Apri KidBox per completare l'invio in chat."
        case .todo:           return "Apri KidBox per completare la creazione del to-do."
        case .event:          return "Apri KidBox per completare la creazione dell'evento."
        case .grocery:        return "Apri KidBox per completare l'aggiunta alla lista spesa."
        case .document:       return "Apri KidBox per completare il salvataggio del documento."
        case .note:           return "Apri KidBox per completare la nota."
        case .encryptedMedia: return "Apri KidBox per completare il salvataggio in Foto e video."
        }
    }
    
    // MARK: - Payload preview
    
    @ViewBuilder
    private var payloadPreview: some View {
        switch payload.type {
        case .image(let url):
            if let url, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 220).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
            }
            
        case .text(let t):
            VStack(alignment: .leading, spacing: 6) {
                Label("Contenuto condiviso", systemImage: "text.quote")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(t)
                    .font(.subheadline).foregroundStyle(.primary)
                    .lineLimit(6).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
            
        case .url(let u):
            if let fileURL = URL(string: u), fileURL.isFileURL {
                filePreviewCard(for: fileURL)
            } else if isImageURL(u) {
                Group {
                    if let img = remoteImage {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 220).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 160).overlay(ProgressView())
                    }
                }
                .task {
                    guard let url = URL(string: u),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          let img = UIImage(data: data) else { return }
                    remoteImage = img
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "link.circle.fill").font(.title2).foregroundStyle(destination.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Link").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(u).font(.subheadline).foregroundStyle(.blue).lineLimit(2)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
            }
            
        case .file(let url):
            filePreviewCard(for: url)
            
        case .unknown:
            EmptyView()
        }
    }
    
    private func isImageURL(_ u: String) -> Bool {
        let ext = URL(string: u)?.pathExtension.lowercased() ?? ""
        return ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(ext)
    }
    
    private func filePreviewCard(for url: URL) -> some View {
        HStack(spacing: 14) {
            Image(systemName: fileIcon(for: url))
                .font(.title2).foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(destination.color, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(url.pathExtension.uppercased()).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }
    
    private func fileIcon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":                         return "doc.richtext.fill"
        case "jpg", "jpeg", "png", "heic":  return "photo.fill"
        case "mp4", "mov", "m4v":           return "video.fill"
        case "doc", "docx":                 return "doc.fill"
        case "xls", "xlsx":                 return "tablecells.fill"
        case "zip", "rar":                  return "archivebox.fill"
        default:                            return "doc.fill"
        }
    }
    
    // MARK: - Edit fields
    
    @ViewBuilder
    private var editFields: some View {
        switch destination {
        case .todo:
            VStack(alignment: .leading, spacing: 8) {
                Label("Titolo del to-do", systemImage: "checkmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Es. Comprare latte", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
            }
            
        case .grocery:
            VStack(alignment: .leading, spacing: 8) {
                Label("Aggiungi alla lista spesa", systemImage: "cart")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Es. Latte, pane, uova", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                Text("Ogni riga diventerà un articolo separato")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            
        case .event:
            VStack(alignment: .leading, spacing: 8) {
                Label("Titolo evento", systemImage: "calendar")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Es. Visita pediatra", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                Label("Note aggiuntive", systemImage: "text.alignleft")
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                TextEditor(text: $editedText)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
            }
            
        case .note:
            VStack(alignment: .leading, spacing: 8) {
                Label("Titolo nota", systemImage: "note.text")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Titolo", text: $editedTitle).textFieldStyle(.roundedBorder)
                if !editedText.isEmpty {
                    Label("Testo", systemImage: "text.alignleft")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                    TextEditor(text: $editedText)
                        .frame(minHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                }
            }
            
        case .chat:
            EmptyView()
            
        case .document:
            VStack(alignment: .leading, spacing: 8) {
                Text("Il file verrà salvato nella sezione Documenti.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label("Titolo documento", systemImage: "folder")
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                TextField("Es. Referti agosto 2025", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
            }
            
        case .encryptedMedia:
            HStack(spacing: 12) {
                Image(systemName: "lock.fill").foregroundStyle(.cyan)
                Text("Il file verrà cifrato e salvato in Foto e video della famiglia.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Confirm label
    
    private var confirmLabel: String {
        switch destination {
        case .chat:             return "Invia in chat"
        case .document:         return "Salva nei documenti"
        case .todo:             return "Crea to-do"
        case .grocery:          return "Aggiungi alla spesa"
        case .event:            return "Crea evento"
        case .note:             return "Crea nota"
        case .encryptedMedia:   return "Salva in Foto e video"
        }
    }
    
    // MARK: - Prefill
    
    private func prefillFields() {
        switch payload.type {
        case .text(let t):
            if destination == .event {
                let parsed = parseEventText(t)
                editedTitle = parsed.title
                editedText  = parsed.notes
            } else if destination == .grocery {
                let lines = t.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                editedTitle = lines.joined(separator: "\n")
            } else if destination == .chat {
                editedText = t
            } else {
                let lines = t.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if lines.count >= 2 {
                    editedTitle = lines.first ?? t
                    editedText  = lines.dropFirst().joined(separator: "\n")
                } else {
                    let raw = lines.first ?? t
                    if let range = raw.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?")) {
                        let titleEnd = raw.index(after: range.lowerBound)
                        editedTitle  = String(raw[raw.startIndex..<titleEnd]).trimmingCharacters(in: .whitespaces)
                        editedText   = String(raw[titleEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        editedTitle = raw
                        editedText  = ""
                    }
                }
            }
        case .url(let u):
            if let fileURL = URL(string: u), fileURL.isFileURL {
                editedTitle = fileURL.deletingPathExtension().lastPathComponent
            } else {
                editedTitle = u
                editedText  = u
            }
        case .file(let url):
            let raw = url.deletingPathExtension().lastPathComponent
            // Rimuovi prefisso "share_UUID_" o puro UUID
            let uuidPattern = #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#
            let isUUID = raw.range(of: uuidPattern, options: .regularExpression) != nil
            if isUUID {
                editedTitle = ""  // mostra placeholder vuoto, utente inserisce il titolo
            } else if let range = raw.range(of: "_") {
                editedTitle = String(raw[range.upperBound...])
            } else {
                editedTitle = raw
            }
        default:
            break
        }
    }
    
    private func parseEventText(_ text: String) -> ParsedEventShare {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        var detectedDate: Date?
        var cleanedTitle = trimmed
        if let match = detector?.firstMatch(in: trimmed, range: range),
           let date = match.date,
           let swiftRange = Range(match.range, in: trimmed) {
            detectedDate = date
            var tmp = trimmed
            tmp.removeSubrange(swiftRange)
            cleanedTitle = tmp
                .replacingOccurrences(of: "  ", with: " ")
                .replacingOccurrences(of: " ,", with: ",")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleanedTitle.isEmpty { cleanedTitle = "Nuovo evento" }
        return ParsedEventShare(title: cleanedTitle, notes: trimmed, detectedDate: detectedDate)
    }
    
    // MARK: - Send
    
    private func sendToDestination() async {
        guard !hasSent else {
            log("sendToDestination SKIPPED — hasSent=true (double-tap guard)")
            return
        }
        hasSent = true
        log("sendToDestination START destination=\(destination.rawStringValue)")
        isSending = true
        errorMessage = nil
        
        do {
            let result: ShareSendResult
            
            switch destination {
            case .chat:
                result = try await sendDirectToChat()
                
            case .note:
                result = try await sendDirectToNote()
                
            case .todo, .event, .grocery:
                saveToAppGroup()
                result = .deferredToMainApp(
                    urlString: "kidbox://share?destination=\(destination.rawStringValue)",
                    showBanner: true
                )
                
            case .document:
                saveToAppGroup()
                result = .deferredToMainApp(
                    urlString: "kidbox://share?destination=document",
                    showBanner: false
                )
                
            case .encryptedMedia:
                // Identico a .document: copia il file nell'App Group,
                // l'app principale lo carica con SyncCenter.photoRemote.upload()
                saveToAppGroup()
                result = .deferredToMainApp(
                    urlString: "kidbox://share?destination=encryptedMedia",
                    showBanner: false
                )
            }
            
            switch result {
            case .completedInExtension:
                log("sendToDestination completed in extension → closing")
                onDone()
                
            case .deferredToMainApp(let urlString, let showBanner):
                if showBanner {
                    log("sendToDestination deferred with banner")
                    isSending = false
                    deferredBannerDestination = destination
                } else {
                    log("sendToDestination opening main app url=\(urlString)")
                    onOpenApp(urlString)
                }
                
            case .videoDeferredToMainApp:
                log("sendToDestination video deferred → showing banner")
                isSending = false
                videoSavedToAppGroup = true
            }
            
        } catch {
            log("sendToDestination ERROR: \(error.localizedDescription)")
            isSending = false
            errorMessage = "Errore: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Chat: invio diretto da extension
    
    private func sendDirectToChat() async throws -> ShareSendResult {
        log("sendDirectToChat START")
        
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let familyId = defaults.string(forKey: "activeFamilyId"),
              !familyId.isEmpty else {
            log("sendDirectToChat ERROR: familyId not found in App Group")
            throw ShareError.missingFamilyId
        }
        
        log("sendDirectToChat familyId=\(familyId)")
        
        let messageId = UUID().uuidString
        let storage = ChatStorageService()
        let remote = ChatRemoteStore()
        
        switch payload.type {
            
        case .image(let url):
            guard let sourceURL = url, let data = imageData(from: sourceURL) else {
                throw ShareError.missingFile
            }
            log("sendDirectToChat uploading image bytes=\(data.count)")
            let (storagePath, downloadURL) = try await storage.upload(
                data: data, familyId: familyId, messageId: messageId,
                fileName: "photo.jpg", mimeType: "image/jpeg"
            )
            log("sendDirectToChat upload OK storagePath=\(storagePath)")
            let dto = makeDTO(messageId: messageId, familyId: familyId, typeRaw: "photo",
                              mediaStoragePath: storagePath, mediaURL: downloadURL)
            try await remote.upsert(dto: dto)
            return .completedInExtension
            
        case .file(let url):
            let ext = url.pathExtension.lowercased()
            let isVideo = ["mp4", "mov", "m4v"].contains(ext)
            let isImage = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"].contains(ext)
            
            if isVideo {
                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                guard fileSize <= 200 * 1024 * 1024 else {
                    throw ShareError.videoTooLarge(sizeMB: fileSize / (1024 * 1024))
                }
                let name = "share_\(UUID().uuidString)_\(url.lastPathComponent)"
                guard let groupURL = copyFileToAppGroup(url, name: name) else {
                    throw ShareError.missingFile
                }
                UserDefaults(suiteName: appGroupId)?.set([
                    "destination":    "chat",
                    "sharedFilePath": groupURL.path,
                    "sharedFileType": "video",
                    "sharedFileName": url.lastPathComponent,
                    "timestamp":      ISO8601DateFormatter().string(from: Date())
                ], forKey: "pendingShare")
                log("sendDirectToChat video saved to AppGroup path=\(groupURL.path)")
                return .videoDeferredToMainApp
            }
            
            let (fileName, mimeType, typeRaw): (String, String, String) = {
                if isImage { return ("photo.jpg", "image/jpeg", "photo") }
                return (url.lastPathComponent, "application/octet-stream", "document")
            }()
            guard let data = try? Data(contentsOf: url) else { throw ShareError.missingFile }
            log("sendDirectToChat uploading file typeRaw=\(typeRaw) bytes=\(data.count)")
            let (storagePath, downloadURL) = try await storage.upload(
                data: data, familyId: familyId, messageId: messageId,
                fileName: fileName, mimeType: mimeType
            )
            let dto = makeDTO(messageId: messageId, familyId: familyId, typeRaw: typeRaw,
                              text: typeRaw == "document" ? url.lastPathComponent : nil,
                              mediaStoragePath: storagePath, mediaURL: downloadURL)
            try await remote.upsert(dto: dto)
            return .completedInExtension
            
        case .url(let u):
            if let fileURL = URL(string: u), fileURL.isFileURL {
                let accessed = fileURL.startAccessingSecurityScopedResource()
                defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: fileURL) else { throw ShareError.missingFile }
                let fileName = fileURL.lastPathComponent
                log("sendDirectToChat uploading file-url bytes=\(data.count) name=\(fileName)")
                let (storagePath, downloadURL) = try await storage.upload(
                    data: data, familyId: familyId, messageId: messageId,
                    fileName: fileName, mimeType: "application/octet-stream"
                )
                let dto = makeDTO(messageId: messageId, familyId: familyId, typeRaw: "document",
                                  text: fileName, mediaStoragePath: storagePath, mediaURL: downloadURL)
                try await remote.upsert(dto: dto)
                return .completedInExtension
                
            } else if isImageURL(u) {
                guard let imgURL = URL(string: u),
                      let (data, _) = try? await URLSession.shared.data(from: imgURL),
                      !data.isEmpty else { throw ShareError.missingFile }
                log("sendDirectToChat uploading remote image bytes=\(data.count)")
                let (storagePath, downloadURL) = try await storage.upload(
                    data: data, familyId: familyId, messageId: messageId,
                    fileName: "photo.jpg", mimeType: "image/jpeg"
                )
                let dto = makeDTO(messageId: messageId, familyId: familyId, typeRaw: "photo",
                                  mediaStoragePath: storagePath, mediaURL: downloadURL)
                try await remote.upsert(dto: dto)
                return .completedInExtension
                
            } else {
                let text = editedText.isEmpty ? u : editedText
                log("sendDirectToChat sending url=\(u)")
                let dto = makeDTO(messageId: messageId, familyId: familyId, typeRaw: "text", text: text)
                try await remote.upsert(dto: dto)
                return .completedInExtension
            }
            
        case .text(let t):
            let text = editedText.isEmpty ? t : editedText
            log("sendDirectToChat sending text=\(text.prefix(50))")
            let dto = makeDTO(messageId: messageId, familyId: familyId, typeRaw: "text", text: text)
            try await remote.upsert(dto: dto)
            return .completedInExtension
            
        case .unknown:
            log("sendDirectToChat unknown payload — nothing to send")
            return .completedInExtension
        }
    }
    
    // MARK: - Note: creazione diretta su Firestore dall'extension
    
    private func sendDirectToNote() async throws -> ShareSendResult {
        log("sendDirectToNote START")
        
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let familyId = defaults.string(forKey: "activeFamilyId"),
              !familyId.isEmpty else { throw ShareError.missingFamilyId }
        
        let uid = defaults.string(forKey: "currentUserUID") ?? ""
        let displayName = defaults.string(forKey: "currentUserDisplayName") ?? ""
        guard !uid.isEmpty else {
            log("sendDirectToNote ERROR: uid not found in App Group")
            throw ShareError.missingFamilyId
        }
        
        let title: String
        let body: String
        switch payload.type {
        case .text(let t):
            let raw = editedText.isEmpty ? t : editedText
            let lines = raw.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            title = editedTitle.isEmpty ? (lines.first ?? raw) : editedTitle
            body  = lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : ""
        case .url(let u):
            body  = u
            title = editedTitle.isEmpty ? u : editedTitle
        default:
            body  = editedText
            title = editedTitle
        }
        
        let noteId = UUID().uuidString
        let store = NotesRemoteStore()
        try await store.upsertRaw(noteId: noteId, familyId: familyId, title: title,
                                  body: body, uid: uid, displayName: displayName)
        log("sendDirectToNote OK noteId=\(noteId)")
        return .completedInExtension
    }
    
    // MARK: - DTO builder
    
    private func makeDTO(
        messageId: String, familyId: String, typeRaw: String,
        text: String? = nil, mediaStoragePath: String? = nil, mediaURL: String? = nil
    ) -> RemoteChatMessageDTO {
        let defaults   = UserDefaults(suiteName: appGroupId)
        let senderName = defaults?.string(forKey: "currentUserDisplayName") ?? "Utente"
        let senderId   = defaults?.string(forKey: "currentUserUID") ?? "unknown"
        log("makeDTO senderId=\(senderId) senderName=\(senderName)")
        return RemoteChatMessageDTO(
            id: messageId, familyId: familyId,
            senderId: senderId, senderName: senderName,
            typeRaw: typeRaw, text: text,
            mediaStoragePath: mediaStoragePath, mediaURL: mediaURL,
            mediaDurationSeconds: nil, mediaThumbnailURL: nil,
            replyToId: nil, reactionsJSON: nil, readByJSON: nil,
            createdAt: Date(), editedAt: nil,
            isDeleted: false, deletedFor: [],
            latitude: nil, longitude: nil
        )
    }
    
    private func makeSharedCopyName(for originalURL: URL) -> String {
        let ext = originalURL.pathExtension
        let uuid = UUID().uuidString
        return ext.isEmpty ? "share_\(uuid)" : "share_\(uuid).\(ext)"
    }
    
    // MARK: - App Group (per destinazioni non-chat)
    
    private func saveToAppGroup() {
        var data: [String: String] = [
            "destination": destination.rawStringValue,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        switch payload.type {
        case .text(let t):
            let finalText = editedText.isEmpty ? t : editedText
            data["text"] = finalText
            data["title"] = editedTitle
            
            if destination == .event {
                let parsed = parseEventText(finalText)
                data["title"] = editedTitle.isEmpty ? parsed.title : editedTitle
                if let date = parsed.detectedDate {
                    data["eventStartDate"] = ISO8601DateFormatter().string(from: date)
                }
            }
            
        case .url(let u):
            if let fileURL = URL(string: u), fileURL.isFileURL {
                let copyName = makeSharedCopyName(for: fileURL)
                if let groupURL = copyFileToAppGroup(fileURL, name: copyName) {
                    data["sharedFilePath"] = groupURL.path
                    data["sharedFileType"] = "file"
                    data["sharedFileName"] = fileURL.lastPathComponent   // nome originale
                    data["title"] = editedTitle.isEmpty
                    ? fileURL.deletingPathExtension().lastPathComponent
                    : editedTitle
                }
            } else {
                data["text"] = u
                if destination == .event {
                    let parsed = parseEventText(u)
                    data["title"] = editedTitle.isEmpty ? parsed.title : editedTitle
                    if let date = parsed.detectedDate {
                        data["eventStartDate"] = ISO8601DateFormatter().string(from: date)
                    }
                } else {
                    data["title"] = editedTitle
                }
            }
            
        case .image(let url):
            if let sourceURL = url {
                let copyName = makeSharedCopyName(for: sourceURL)
                if let groupURL = copyFileToAppGroup(sourceURL, name: copyName) {
                    data["sharedFilePath"] = groupURL.path
                    data["sharedFileType"] = "image"
                    data["sharedFileName"] = sourceURL.lastPathComponent
                }
            }
            data["title"] = editedTitle
            
        case .file(let url):
            let copyName = makeSharedCopyName(for: url)
            if let groupURL = copyFileToAppGroup(url, name: copyName) {
                data["sharedFilePath"] = groupURL.path
                data["sharedFileType"] = "file"
                data["sharedFileName"] = url.lastPathComponent          // nome originale
                data["title"] = editedTitle.isEmpty
                ? url.deletingPathExtension().lastPathComponent
                : editedTitle
            }
            
        case .unknown:
            break
        }
        
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        defaults.set(data, forKey: "pendingShare")
        log("saveToAppGroup saved keys=\(data.keys.sorted())")
    }
    
    // MARK: - Helpers
    
    private func imageData(from url: URL) -> Data? {
        if let data = try? Data(contentsOf: url) { return data }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
    
    private func copyFileToAppGroup(_ source: URL, name: String) -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else { return nil }
        let dest = container.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        
        // Usa NSFileCoordinator per forzare download iCloud
        var coordError: NSError?
        let coordinator = NSFileCoordinator()
        var result: URL? = nil
        coordinator.coordinate(readingItemAt: source, options: .withoutChanges, error: &coordError) { coordURL in
            if let data = try? Data(contentsOf: coordURL),
               (try? data.write(to: dest, options: .atomic)) != nil {
                result = dest
            }
        }
        if result != nil { return result }
        
        // Fallback copyItem
        if (try? FileManager.default.copyItem(at: source, to: dest)) != nil { return dest }
        return nil
    }
}

// MARK: - Errors

enum ShareError: LocalizedError {
    case missingFamilyId
    case missingFile
    case videoTooLarge(sizeMB: Int)
    
    var errorDescription: String? {
        switch self {
        case .missingFamilyId:
            return "Apri KidBox almeno una volta per configurare la famiglia."
        case .missingFile:
            return "Impossibile leggere il file selezionato."
        case .videoTooLarge(let sizeMB):
            return "Il video è troppo grande (\(sizeMB) MB). Il limite massimo è 200 MB."
        }
    }
}
