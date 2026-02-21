//
//  FolderRow.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import SwiftUI

// MARK: - FolderRow (Lista)

/// Row cartella per la vista a lista — grafica rinnovata.
struct FolderRow: View {
    let title: String
    var subtitle: String? = nil
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Senza nome" : title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer(minLength: 0)
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

