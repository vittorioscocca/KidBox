//
//  FolderGridCard.swift
//  KidBox
//
//  Created by vscocca on 06/02/26. Updated 21/02/26.
//

import SwiftUI

/// Card cartella per la vista a griglia — stile Dropbox.
struct FolderGridCard: View {
    let title: String
    var updatedAt: Date? = nil
    var subtitle: String? = nil
    let isSelecting: Bool
    let isSelected: Bool
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.9) : Color.clear,
                            lineWidth: isSelected ? 2 : 0
                        )
                )
            
            VStack(alignment: .leading, spacing: 0) {
                // Icona grande centrata in alto
                HStack {
                    Spacer()
                    Image(systemName: "folder.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.orange)
                        .padding(.top, 18)
                    Spacer()
                }
                
                Spacer(minLength: 8)
                
                // Titolo e subtitle in basso
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? "Senza nome" : title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
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
                .padding([.horizontal, .bottom], 12)
                .padding(.top, 6)
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
        .frame(minHeight: 130)
        .scaleEffect(isSelected ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
