//
//  CopyToClipboardButton.swift
//  KidBox
//

import SwiftUI

/// Piccolo bottone "copia negli appunti" da affiancare a testi copiabili
/// (es. referti testuali della Salute). Funziona su iPhone e Mac Catalyst.
struct CopyToClipboardButton: View {
    let text: String
    var accessibilityLabel: String = "Copia"

    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            withAnimation(.easeInOut(duration: 0.2)) { copied = true }
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeInOut(duration: 0.2)) { copied = false }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                Text(copied ? "Copiato" : "Copia")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(copied ? Color.green : Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copiato" : accessibilityLabel)
    }
}

#Preview {
    CopyToClipboardButton(text: "Esempio di referto")
        .padding()
}
