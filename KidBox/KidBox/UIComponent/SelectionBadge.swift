//
//  SelectionBadge.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//

import SwiftUI

/// Cerchio di selezione che appare in modalità multi-selezione.
/// Mostra un checkmark blu quando selezionato, cerchio vuoto altrimenti.
struct SelectionBadge: View {
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color(.systemBackground))
                .frame(width: 24, height: 24)
            
            Circle()
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 1.5)
                .frame(width: 24, height: 24)
            
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}
