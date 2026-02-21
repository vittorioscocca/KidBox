//
//  DocumentGridCard.swift
//  KidBox
//
//  Created by vscocca on 09/02/26. Updated 21/02/26.
//

import SwiftUI

struct DocumentGridCard: View {
    let doc: KBDocument
    
    let isSelecting: Bool
    let isSelected: Bool
    
    let onTap: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onMove: () -> Void
    let onCopy: () -> Void
    let onDuplicate: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                // Card background
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                isSelected
                                ? Color.accentColor.opacity(0.8)
                                : Color.primary.opacity(0.07),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                
                VStack(alignment: .leading, spacing: 10) {
                    // Top: icona tipo + badge selezione
                    HStack(alignment: .top) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(iconTint.opacity(0.15))
                                .frame(width: 38, height: 38)
                            
                            Image(systemName: iconName)
                                .font(.headline)
                                .foregroundStyle(iconTint)
                        }
                        
                        Spacer()
                        
                        if isSelecting {
                            SelectionBadge(isSelected: isSelected)
                        }
                    }
                    
                    // Titolo + fileName
                    VStack(alignment: .leading, spacing: 3) {
                        Text(doc.title.isEmpty ? "Senza titolo" : doc.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Text(doc.fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Bottom: dimensione + pill sync
                    HStack(alignment: .center) {
                        Text(prettySize(doc.fileSize))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                        
                        Spacer()
                        
                        if doc.syncState != .synced {
                            SyncPill(state: doc.syncState, error: doc.lastSyncError)
                        }
                    }
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .contextMenu {
            if !isSelecting {
                Button { onRename() } label: {
                    Label("Rinomina", systemImage: "pencil")
                }
                Divider()
                Button { onMove() } label: {
                    Label("Sposta in…", systemImage: "folder")
                }
                Button { onCopy() } label: {
                    Label("Copia in…", systemImage: "doc.on.doc")
                }
                Button { onDuplicate() } label: {
                    Label("Duplica", systemImage: "plus.square.on.square")
                }
                Divider()
                Button(role: .destructive) { onDelete() } label: {
                    Label("Elimina", systemImage: "trash")
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var iconName: String {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf")   { return "doc.richtext.fill" }
        if m.contains("image") { return "photo.fill" }
        if m.contains("text")  { return "doc.text.fill" }
        return "doc.fill"
    }
    
    private var iconTint: Color {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf")   { return .red }
        if m.contains("image") { return .blue }
        if m.contains("text")  { return .green }
        return .indigo
    }
    
    private func prettySize(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1024          { return "\(bytes) B" }
        let kb = b / 1024
        if kb < 1024         { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024         { return String(format: "%.1f MB", mb) }
        return String(format: "%.1f GB", mb / 1024)
    }
}
