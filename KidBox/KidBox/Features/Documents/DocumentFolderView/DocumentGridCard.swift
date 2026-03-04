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
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    // Icona documento grande
                    ZStack {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(Color(.systemGray4))
                        
                        // Badge tipo file in basso a destra sull'icona
                        Text(fileExtLabel)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(iconTint, in: RoundedRectangle(cornerRadius: 3))
                            .offset(x: 6, y: 8)
                    }
                    .frame(width: 72, height: 64)
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 10, y: 4)
                    }
                }
                
                Text(doc.title.isEmpty ? "Senza titolo" : doc.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                
                Text(prettySize(doc.fileSize))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .scaleEffect(isSelected ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
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
    
    /// Etichetta estensione (es. "PDF", "JPG", "DOC")
    private var fileExtLabel: String {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf")              { return "PDF" }
        if m.contains("jpeg") || m.contains("jpg") { return "JPG" }
        if m.contains("png")              { return "PNG" }
        if m.contains("gif")              { return "GIF" }
        if m.contains("word") || m.contains("msword") { return "DOC" }
        if m.contains("sheet") || m.contains("excel") { return "XLS" }
        if m.contains("presentation") || m.contains("powerpoint") { return "PPT" }
        if m.contains("text/plain")       { return "TXT" }
        let ext = (doc.fileName as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : String(ext.prefix(4))
    }
    
    private var iconTint: Color {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf")              { return .red }
        if m.contains("image")            { return .blue }
        if m.contains("word") || m.contains("msword") { return Color(red: 0.17, green: 0.44, blue: 0.86) }
        if m.contains("sheet") || m.contains("excel") { return Color(red: 0.13, green: 0.62, blue: 0.30) }
        if m.contains("presentation") || m.contains("powerpoint") { return .orange }
        if m.contains("text")             { return .gray }
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
