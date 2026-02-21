//
//  DocumentRow.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import SwiftUI

// MARK: - DocumentRow (Lista) aggiornato

struct DocumentRow: View {
    let doc: KBDocument
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Icona tipo file
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconTint.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: iconName)
                    .font(.headline)
                    .foregroundStyle(iconTint)
            }
            
            // Testo
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.title.isEmpty ? "Senza titolo" : doc.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 6) {
                    Text(doc.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    
                    Text(prettySize(doc.fileSize))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .layoutPriority(1)
            
            Spacer(minLength: 8)
            
            // Pill sync solo se non OK
            if doc.syncState != .synced {
                SyncPill(state: doc.syncState, error: doc.lastSyncError)
                    .fixedSize()
            }
        }
        .padding(.vertical, 4)
    }
    
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
