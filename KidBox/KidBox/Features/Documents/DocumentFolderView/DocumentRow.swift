//
//  DocumentRow.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import SwiftUI

// MARK: - DocumentRow (Lista) — stile Dropbox

struct DocumentRow: View {
    let doc: KBDocument
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Icona tipo file con sfondo colorato
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconTint.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(iconTint)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.title.isEmpty ? "Senza titolo" : doc.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                // Seconda riga: nome file · data · dimensione
                HStack(spacing: 4) {
                    if !doc.fileName.isEmpty && doc.fileName != doc.title {
                        Text(doc.fileName)
                            .lineLimit(1)
                        Text("·")
                            .foregroundStyle(.tertiary)
                    }
                    Text(doc.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(prettySize(doc.fileSize))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .layoutPriority(1)
            
            Spacer(minLength: 8)
            
            if doc.syncState != .synced {
                SyncPill(state: doc.syncState, error: doc.lastSyncError)
                    .fixedSize()
            } else {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
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
        if m.contains("sheet") || m.contains("excel") { return .green }
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
