//
//  ChangePasswordSheet.swift
//  KidBox
//
//  Created by vscocca on 21/09/26.
//

import SwiftUI
import FirebaseAuth
import OSLog

/// Cambio password dell'account per chi è entrato con email e password.
///
/// Apple e Google non hanno una password da cambiare: la voce che apre questo
/// foglio compare solo quando fra i provider dell'utente c'è `password`.
/// Firebase rifiuta `updatePassword` su una sessione non recente
/// (`requiresRecentLogin`), quindi si riautentica sempre con la password
/// attuale prima di scrivere quella nuova: così la vecchia password è anche
/// la conferma di identità, senza far uscire l'utente dall'app.
struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var showSuccess = false

    private var mismatch: Bool {
        !confirmPassword.isEmpty && newPassword != confirmPassword
    }

    private var canSubmit: Bool {
        !currentPassword.isEmpty
            && newPassword.count >= 6
            && newPassword == confirmPassword
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Cambia la password con cui accedi a KidBox.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Password attuale") {
                    SecureField("Password attuale", text: $currentPassword)
                        .textContentType(.password)
                }

                Section {
                    SecureField("Nuova password", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("Conferma nuova password", text: $confirmPassword)
                        .textContentType(.newPassword)
                } header: {
                    Text("Nuova password")
                } footer: {
                    if mismatch {
                        Text("Le password non coincidono.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Almeno 6 caratteri.")
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Cambia password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "..." : "Salva") { submit() }
                        .disabled(!canSubmit)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert("Password aggiornata ✅", isPresented: $showSuccess) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text("D'ora in poi accedi con la nuova password.")
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        guard let user = Auth.auth().currentUser, let email = user.email else {
            errorText = String(localized: "Sessione non valida. Esci e accedi di nuovo.")
            return
        }
        isSaving = true
        errorText = nil
        KBLog.auth.kbInfo("ChangePassword requested")
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
                try await user.reauthenticate(with: credential)
                try await user.updatePassword(to: newPassword)
                KBLog.auth.kbInfo("ChangePassword done")
                showSuccess = true
            } catch {
                errorText = friendlyError(error)
                KBLog.auth.kbError("ChangePassword failed: \(error.localizedDescription)")
            }
        }
    }

    /// Stessi codici di `LoginViewModel.friendlyError`, ma qui la password
    /// sbagliata è quella attuale, e va detto.
    private func friendlyError(_ error: Error) -> String {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .wrongPassword, .invalidCredential:
            return String(localized: "La password attuale non è corretta.")
        case .weakPassword:
            return String(localized: "La nuova password è troppo debole (min. 6 caratteri).")
        case .networkError:
            return String(localized: "Errore di rete. Controlla la connessione.")
        case .tooManyRequests:
            return String(localized: "Troppi tentativi. Riprova tra qualche minuto.")
        case .requiresRecentLogin:
            return String(localized: "Sessione non valida. Esci e accedi di nuovo.")
        default:
            return error.localizedDescription
        }
    }
}
