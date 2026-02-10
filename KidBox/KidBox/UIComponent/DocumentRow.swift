//
//  DocumentRow.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import SwiftUI

struct DocumentRow: View {
    let doc: KBDocument
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.title.isEmpty ? "Senza titolo" : doc.title)
                    .font(.subheadline).bold()
                    .foregroundStyle(.primary)
                    .lineLimit(2) // ✅ 2 righe in list
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(doc.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1) // ✅ il testo “vince”
            
            Spacer(minLength: 8)
            
            // ✅ Mostra pill SOLO se non è OK
            if !(doc.syncState == .synced && (doc.lastSyncError?.isEmpty ?? true)) {
                SyncPill(state: doc.syncState, error: doc.lastSyncError)
                    .fixedSize()
            }
        }
        .padding(.vertical, 6)
    }
    
    private var iconName: String {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf") { return "doc.richtext" }
        if m.contains("image") { return "photo" }
        if m.contains("text") { return "doc.text" }
        return "doc"
    }
}
