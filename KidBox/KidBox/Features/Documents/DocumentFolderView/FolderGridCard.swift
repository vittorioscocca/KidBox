//
//  FolderGridCard.swift
//  KidBox
//
//  Created by vscocca on 06/02/26. Updated 21/02/26.
//

import SwiftUI

/// Icona cartella libera per la griglia — stile iOS Files.
struct FolderGridCard: View {
    let title: String
    var updatedAt: Date? = nil
    var subtitle: String? = nil
    let isSelecting: Bool
    let isSelected: Bool
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                ZStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 20, y: -20)
                    }
                }
                .frame(width: 72, height: 64)
                
                Text(title.isEmpty ? "Senza nome" : title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                
                if let sub = subtitle {
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let date = updatedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
        .scaleEffect(isSelected ? 0.94 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}
