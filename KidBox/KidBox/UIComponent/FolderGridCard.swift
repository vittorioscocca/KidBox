//
//  FolderGridCard.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import SwiftUI

struct FolderGridCard: View {
    let title: String
    
    let isSelecting: Bool
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            // spazio riservato al badge
            if isSelecting {
                Spacer().frame(height: 18)
            }
            
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(.subheadline).bold()
                .foregroundStyle(.primary)
                .lineLimit(2)
            
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if isSelecting {
                SelectionBadge(isSelected: isSelected)
                    .padding(8)
            }
        }
    }
}

struct SelectionBadge: View {
    let isSelected: Bool
    
    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.headline)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isSelected ? .blue : .secondary)
            .padding(2)
            .background(.ultraThinMaterial, in: Circle())
    }
}
