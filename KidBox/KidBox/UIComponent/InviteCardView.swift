//
//  InviteCardView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//
import SwiftUI

struct InviteCardView: View {
    let action: () -> Void
    
    init(action: @escaping () -> Void) {
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Invita l’altro genitore")
                        .font(.headline)
                    Text("Genera un codice e condividilo in 2 secondi.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.thinMaterial)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Invita l’altro genitore")
        .accessibilityHint("Apre la schermata per generare un codice invito")
    }
}
