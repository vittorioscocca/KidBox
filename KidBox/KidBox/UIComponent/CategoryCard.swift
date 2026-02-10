//
//  CategoryCard.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import SwiftUI

struct CategoryCard: View {
    let cat: KBDocumentCategory
    let action: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    SyncPill(state: cat.syncState, error: cat.lastSyncError)
                }
                
                Text(cat.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("Apri categoria")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Elimina categoria", systemImage: "trash")
            }
        }
    }
}
