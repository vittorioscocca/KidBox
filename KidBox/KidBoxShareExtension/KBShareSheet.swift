//
//  KBShareSheet.swift
//  KBShare  ← solo Share Extension target
//

import SwiftUI

struct KBShareSheet: View {
    let payload: KBSharePayload
    let onDismiss: () -> Void
    let onOpenApp: (String) -> Void
    weak var extensionContext: NSExtensionContext?
    
    @State private var remoteImage: UIImage? = nil
    @State private var destinations: [KBShareDestination] = []
    @State private var isAIClassified = false
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                contentPreview
                    .padding()
                
                Divider()
                
                HStack {
                    Text("Invia a…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isAIClassified {
                        Label("Apple Intelligence", systemImage: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut, value: isAIClassified)
                .padding(.horizontal)
                .padding(.top, 16)
                
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    ForEach(destinations) { dest in
                        NavigationLink {
                            KBShareEditView(
                                destination: dest,
                                payload: payload,
                                onDone: onDismiss,
                                onOpenApp: onOpenApp,
                                extensionContext: extensionContext
                            )
                        } label: {
                            destinationCard(dest)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .animation(.spring(duration: 0.35), value: destinations.map(\.id))
                .padding()
                
                Spacer()
            }
            .navigationTitle("Condividi su KidBox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { onDismiss() }
                }
            }
            .task {
                // Placeholder sincrono immediato
                destinations = payload.defaultDestinations
                
                // Raffina con AI (solo per testo/URL)
                let result = await payload.classify()
                let aiDests: [KBShareDestination] = result.actions.compactMap { action in
                    switch action {
                    case .todo:     return .todo
                    case .event:    return .event
                    case .grocery:  return .grocery
                    case .note:     return .note
                    case .document: return .document
                    }
                }
                guard !aiDests.isEmpty else { return }
                
                // .chat va sempre in prima posizione
                var finalDests = aiDests
                if !finalDests.contains(.chat) {
                    finalDests.insert(.chat, at: 0)
                }
                
                withAnimation {
                    destinations = finalDests
                    isAIClassified = result.isAIClassified
                }
            }
        }
    }
    
    // MARK: - Content Preview
    
    @ViewBuilder
    private var contentPreview: some View {
        switch payload.type {
        case .image(let url):
            if let url, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(height: 120).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
        case .text(let t):
            Text(t)
                .font(.subheadline)
                .lineLimit(3)
                .padding(12)
                .background(Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 10))
            
        case .url(let u):
            if let fileURL = URL(string: u), fileURL.isFileURL {
                filePreviewCard(for: fileURL)
            } else if isImageURL(u) {
                Group {
                    if let img = remoteImage {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(height: 120).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 120)
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
                Text(u)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(2)
            }
            
        case .file(let url):
            filePreviewCard(for: url)
            
        case .unknown:
            EmptyView()
        }
    }
    
    // MARK: - Helpers
    
    private func isImageURL(_ u: String) -> Bool {
        let ext = URL(string: u)?.pathExtension.lowercased() ?? ""
        return ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(ext)
    }
    
    private func filePreviewCard(for url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: fileIcon(for: url))
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(url.pathExtension.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10))
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
    
    private func destinationCard(_ dest: KBShareDestination) -> some View {
        HStack(spacing: 12) {
            Image(systemName: dest.icon)
                .font(.title3)
                .foregroundStyle(dest.color)
                .frame(width: 36, height: 36)
                .background(dest.color.opacity(0.12), in: Circle())
            
            Text(dest.label)
                .font(.subheadline.weight(.medium))
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }
}
