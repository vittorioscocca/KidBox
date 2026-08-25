//
//  MediaSourceSheet.swift
//  KidBox
//
//  Scelta della sorgente per gli allegati foto/video della chat.
//

import SwiftUI

/// Chiede da dove prendere il media: galleria del telefono o libreria KidBox.
///
/// Foglio compatto dal basso, coerente con gli altri della chat (reazioni,
/// allegati): due voci non giustificano una schermata a tutta altezza, e un
/// menu a comparsa staccherebbe la scelta dal punto in cui è nata.
struct MediaSourceSheet: View {

    let onPickPhoneGallery: () -> Void
    let onPickKidBox: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Da dove vuoi scegliere?")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            row(icon: "photo.on.rectangle", title: "Galleria del telefono", action: onPickPhoneGallery)
            row(icon: "square.grid.2x2", title: "Foto e Video di KidBox", action: onPickKidBox)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 24)
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
