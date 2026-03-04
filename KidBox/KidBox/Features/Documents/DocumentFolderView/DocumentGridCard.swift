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
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isSelected
                                ? Color.accentColor.opacity(0.9)
                                : Color.primary.opacity(0.06),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                
                VStack(alignment: .leading, spacing: 0) {
                    // Area icona centrata
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(iconTint.opacity(0.12))
                            .frame(height: 72)
                        
                        Image(systemName: iconName)
                            .font(.system(size: 30))
                            .foregroundStyle(iconTint)
                    }
                    .padding([.top, .horizontal], 12)
                    
                    // Testo
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
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    
                    Spacer(minLength: 8)
                    
                    // Bottom: size
                    HStack {
                        Text(prettySize(doc.fileSize))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                        
                        Spacer()
                        
                        if doc.syncState != .synced {
                            SyncPill(state: doc.syncState, error: doc.lastSyncError)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                
                // Badge selezione
                if isSelecting {
                    VStack {
                        HStack {
                            Spacer()
                            SelectionBadge(isSelected: isSelected)
                                .padding(10)
                        }
                        Spacer()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .contextMenu {
            if !isSelecting {
                Button { onRename() } label: { Label("Rinomina", systemImage: "pencil") }
                Divider()
                Button { onMove() } label: { Label("Sposta in…", systemImage: "folder") }
                Button { onCopy() } label: { Label("Copia in…", systemImage: "doc.on.doc") }
                Button { onDuplicate() } label: { Label("Duplica", systemImage: "plus.square.on.square") }
                Divider()
                Button(role: .destructive) { onDelete() } label: { Label("Elimina", systemImage: "trash") }
            }
        }
    }
    
    private var iconName: String {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf")   { return "doc.richtext.fill" }
        if m.contains("image") { return "photo.fill" }
        if m.contains("text")  { return "doc.text.fill" }
        if m.contains("word") || m.contains("document") { return "doc.text.fill" }
        if m.contains("sheet") || m.contains("excel") { return "tablecells.fill" }
        return "doc.fill"
    }
    
    private var iconTint: Color {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf")   { return .red }
        if m.contains("image") { return .blue }
        if m.contains("text")  { return .green }
        if m.contains("word") || m.contains("document") { return .blue }
        if m.contains("sheet") || m.contains("excel") { return Color(red: 0.13, green: 0.69, blue: 0.30) }
        return .indigo
    }
    
    private func prettySize(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1024      { return "\(bytes) B" }
        let kb = b / 1024
        if kb < 1024     { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024     { return String(format: "%.1f MB", mb) }
        return String(format: "%.1f GB", mb / 1024)
    }
}
