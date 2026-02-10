//
//  DocumentGridCard.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//
import SwiftUI

struct DocumentGridCard: View {
    let doc: KBDocument
    
    let isSelecting: Bool
    let isSelected: Bool
    
    let onTap: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                if isSelecting {
                    Spacer().frame(height: 18)
                }
                // MARK: - Top row
                HStack(alignment: .top, spacing: 10) {
                   
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.title.isEmpty ? "Senza titolo" : doc.title)
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        
                        Text(doc.fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .layoutPriority(1) // ✅ il testo vince
                    
                    Spacer(minLength: 0)
                }
                
                // MARK: - Bottom row
                HStack {
                    Text(prettySize(doc.fileSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // ✅ pill separata → non ruba spazio al titolo
                    if doc.syncState != .synced {
                        SyncPill(state: doc.syncState, error: doc.lastSyncError)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            // ✅ badge selezione UNICO
            .overlay(alignment: .topLeading) {
                if isSelecting {
                    SelectionBadge(isSelected: isSelected)
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onRename() } label: {
                Label("Rinomina", systemImage: "pencil")
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("Elimina", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Helpers
    
    private var iconName: String {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf") { return "doc.richtext" }
        if m.contains("image") { return "photo" }
        if m.contains("text") { return "doc.text" }
        return "doc"
    }
    
    private func prettySize(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1024 { return "\(bytes) B" }
        let kb = b / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024
        return String(format: "%.1f GB", gb)
    }
}
