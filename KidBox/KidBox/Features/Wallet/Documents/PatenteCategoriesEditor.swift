//
//  PatenteCategoriesEditor.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Editor riutilizzabile delle categorie di patente (A, B, C, ...), ciascuna
//  con la propria data di rilascio e scadenza. Usato dalle sheet di
//  acquisizione/modifica/collegamento quando il tipo documento è "Patente".
//

import SwiftUI

struct PatenteCategoriesEditor: View {
    @Binding var categories: [KBPatenteCategory]

    var body: some View {
        Section("Categorie patente") {
            if categories.isEmpty {
                Text("Aggiungi le categorie (A, B, C, …) con le rispettive date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach($categories) { $category in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Categoria (es. B)", text: $category.code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.body.weight(.semibold))
                        Spacer()
                        Button(role: .destructive) {
                            categories.removeAll { $0.id == category.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }

                    dateRow(label: "Rilascio", date: $category.issueDate)
                    dateRow(label: "Scadenza", date: $category.expiryDate)
                }
                .padding(.vertical, 4)
            }

            Button {
                categories.append(KBPatenteCategory(code: "", issueDate: nil, expiryDate: nil))
            } label: {
                Label("Aggiungi categoria", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    private func dateRow(label: String, date: Binding<Date?>) -> some View {
        let hasDate = Binding(
            get: { date.wrappedValue != nil },
            set: { date.wrappedValue = $0 ? (date.wrappedValue ?? Date()) : nil }
        )
        let dateValue = Binding(
            get: { date.wrappedValue ?? Date() },
            set: { date.wrappedValue = $0 }
        )

        Toggle(label, isOn: hasDate)
            .font(.subheadline)
        if date.wrappedValue != nil {
            DatePicker(label, selection: dateValue, displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
