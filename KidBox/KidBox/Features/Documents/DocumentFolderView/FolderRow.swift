//
//  FolderRow.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import SwiftUI

// MARK: - FolderRow (Lista)

/// Row cartella per la vista a lista — stile Dropbox.
struct FolderRow: View {
    let title: String
    var updatedAt: Date? = nil
    var subtitle: String? = nil
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
                .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "Senza nome" : title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if let sub = subtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let date = updatedAt {
                    Text("Modificata \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
    }
}
