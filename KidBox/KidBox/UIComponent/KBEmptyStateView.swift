//
//  KBEmptyStateView.swift
//  KidBox
//

import SwiftUI

/// Schermata di benvenuto di una sezione ancora vuota: icona, titolo, testo che
/// spiega a cosa serve la sezione, e il pulsante per creare il primo elemento.
///
/// Nasce da `NotesEmptyStateView` / `TodoEmptyStateView`, che avevano lo stesso
/// corpo copiato due volte. Averne uno solo evita che le sezioni divergano una
/// per una e tiene allineato il rendering con `KBEmptyState` su Android.
///
/// `secondaryTitle` serve alle sezioni con due modi di iniziare — Casa, dove si
/// può aggiungere sia un elemento sia una scadenza.
struct KBEmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let actionSystemImage: String
    let action: () -> Void

    /// Tinta della sezione: Animali e Garage usano l'arancio, il resto l'accento KidBox.
    var accent: Color = .accentColor
    var secondaryTitle: String? = nil
    var secondarySystemImage: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: action) {
                Label(actionTitle, systemImage: actionSystemImage)
                    .font(.subheadline).fontWeight(.medium)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }

            if let secondaryTitle, let secondaryAction {
                Button(action: secondaryAction) {
                    Label(secondaryTitle, systemImage: secondarySystemImage ?? actionSystemImage)
                        .font(.subheadline).fontWeight(.medium)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .foregroundStyle(accent)
                        .overlay(Capsule().stroke(accent, lineWidth: 1))
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
