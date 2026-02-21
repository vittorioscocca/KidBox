//
//  FolderGridCard.swift
//  KidBox
//
//  Created by vscocca on 06/02/26. Updated 21/02/26.
//

import SwiftUI

/// Card cartella per la vista a griglia — grafica rinnovata.
struct FolderGridCard: View {
    let title: String
    var subtitle: String? = nil          // es. "3 elementi"
    let isSelecting: Bool
    let isSelected: Bool
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background card
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.22), Color.orange.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isSelected
                            ? Color.accentColor.opacity(0.8)
                            : Color.orange.opacity(0.25),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
            
            VStack(alignment: .leading, spacing: 8) {
                // Icona + badge selezione
                HStack(alignment: .top) {
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    
                    Spacer()
                    
                    if isSelecting {
                        SelectionBadge(isSelected: isSelected)
                    }
                }
                
                Spacer(minLength: 4)
                
                Text(title.isEmpty ? "Senza nome" : title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .frame(minHeight: 100)
        .scaleEffect(isSelected ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
