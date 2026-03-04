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
            // Icona documento con badge tipo file
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(.systemGray4))
                
                Text(fileExtLabel)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(iconTint, in: RoundedRectangle(cornerRadius: 3))
                    .offset(x: 4, y: 4)
            }
            .frame(width: 44, height: 44)
            
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
            }
        }
        .padding(.vertical, 6)
    }
    
    private var fileExtLabel: String {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf")               { return "PDF" }
        if m.contains("jpeg") || m.contains("jpg") { return "JPG" }
        if m.contains("png")               { return "PNG" }
        if m.contains("gif")               { return "GIF" }
        if m.contains("word") || m.contains("msword") { return "DOC" }
        if m.contains("sheet") || m.contains("excel") { return "XLS" }
        if m.contains("presentation") || m.contains("powerpoint") { return "PPT" }
        if m.contains("text/plain")        { return "TXT" }
        let ext = (doc.fileName as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : String(ext.prefix(4))
    }
    
    private var iconTint: Color {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf")               { return .red }
        if m.contains("image")             { return .blue }
        if m.contains("word") || m.contains("msword") { return Color(red: 0.17, green: 0.44, blue: 0.86) }
        if m.contains("sheet") || m.contains("excel") { return Color(red: 0.13, green: 0.62, blue: 0.30) }
        if m.contains("presentation") || m.contains("powerpoint") { return .orange }
        if m.contains("text")              { return .gray }
        return .indigo
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
