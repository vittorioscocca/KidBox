//
//  TodoNotesField.swift
//  KidBox
//

import SwiftUI

/// Anteprima note in lista To-Do (più righe, testo leggibile).
struct TodoNotesPreviewText: View {
    let notes: String?

    var body: some View {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            Text(trimmed)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Editor note ampio con supporto elenco puntato.
struct TodoNotesEditor: View {
    @Binding var text: String

    private let minHeight: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Scrivi qui dettagli, promemoria o un elenco puntato…")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: minHeight)
                    .scrollContentBackground(.hidden)
            }

            HStack(spacing: 12) {
                Button {
                    appendBulletLine()
                } label: {
                    Label("Punto elenco", systemImage: "list.bullet")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)

                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func appendBulletLine() {
        if text.isEmpty {
            text = "• "
            return
        }
        if text.hasSuffix("\n") {
            text += "• "
        } else {
            text += "\n• "
        }
    }
}
