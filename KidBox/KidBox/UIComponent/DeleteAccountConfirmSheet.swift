//
//  DeleteAccountCardView.swift
//  KidBox
//
//  Created by vscocca on 19/02/26.
//

import SwiftUI

struct DeleteAccountConfirmSheet: View {
    @Binding var confirmText: String
    @Binding var isDeleting: Bool
    @Binding var errorText: String?
    
    let onCancel: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Questa azione è definitiva. Il tuo account e i tuoi dati verranno cancellati dai nostri sistemi.")
                    Text("Se fai parte di una famiglia con altri membri, verrà rimossa solo la tua partecipazione.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section("Conferma") {
                    TextField("Digita ELIMINA", text: $confirmText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                
                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Elimina account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", action: onCancel)
                        .disabled(isDeleting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isDeleting ? "..." : "Elimina", action: onDelete)
                        .disabled(isDeleting)
                }
            }
        }
    }
}
