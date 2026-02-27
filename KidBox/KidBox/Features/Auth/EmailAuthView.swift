//
//  EmailAuthView.swift
//  KidBox
//
//  Created by vscocca on 27/02/26.
//

import SwiftUI

/// Modale che gestisce sia il **login** che la **registrazione** via email/password.
/// Viene presentata come sheet da `LoginView`.
struct EmailAuthView: View {
    
    @ObservedObject var vm: LoginViewModel
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Local state
    
    @State private var isRegistering = false
    @State private var email         = ""
    @State private var password      = ""
    @State private var confirmPwd    = ""
    @State private var showPassword  = false
    
    private let cream = Color(red: 0.961, green: 0.957, blue: 0.945)
    
    // MARK: - Validation
    
    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".")
    }
    
    private var isFormValid: Bool {
        guard isEmailValid, password.count >= 6 else { return false }
        if isRegistering { return password == confirmPwd }
        return true
    }
    
    private var passwordMismatch: Bool {
        isRegistering && !confirmPwd.isEmpty && password != confirmPwd
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            cream.ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // ── Drag handle ────────────────────────────────────────────
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                
                // ── Titolo ─────────────────────────────────────────────────
                Text(isRegistering ? "Crea account" : "Accedi")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                
                Text(isRegistering
                     ? "Inserisci email e password per registrarti."
                     : "Inserisci le tue credenziali per accedere.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 4)
                
                Spacer().frame(height: 32)
                
                // ── Campi ──────────────────────────────────────────────────
                VStack(spacing: 14) {
                    
                    // Email
                    KBTextField(
                        placeholder: "Email",
                        text: $email,
                        icon: "envelope",
                        keyboardType: .emailAddress,
                        autocapitalization: .never
                    )
                    
                    // Password
                    KBSecureField(
                        placeholder: "Password (min. 6 caratteri)",
                        text: $password,
                        showPassword: $showPassword
                    )
                    
                    // Conferma password (solo registrazione)
                    if isRegistering {
                        KBSecureField(
                            placeholder: "Conferma password",
                            text: $confirmPwd,
                            showPassword: $showPassword
                        )
                        
                        if passwordMismatch {
                            Text("Le password non coincidono.")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.horizontal, 28)
                
                // ── Password dimenticata (solo login) ──────────────────────
                if !isRegistering {
                    Button("Password dimenticata?") {
                        vm.resetPassword(email: email)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .disabled(email.isEmpty)
                }
                
                Spacer().frame(height: 28)
                
                // ── CTA principale ─────────────────────────────────────────
                Button {
                    Task {
                        if isRegistering {
                            await vm.registerEmail(email: email, password: password)
                        } else {
                            await vm.signInEmail(email: email, password: password)
                        }
                        if vm.errorMessage == nil { dismiss() }
                    }
                } label: {
                    Group {
                        if vm.isBusy {
                            ProgressView().tint(.white)
                        } else {
                            Text(isRegistering ? "Crea account" : "Accedi")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(isFormValid ? Color.black : Color.black.opacity(0.3), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!isFormValid || vm.isBusy)
                .padding(.horizontal, 28)
                
                // ── Errore ─────────────────────────────────────────────────
                if let error = vm.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 10)
                }
                
                // ── Banner reset password ──────────────────────────────────
                if vm.resetPasswordSent {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Email di recupero inviata.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 10)
                }
                
                Spacer().frame(height: 24)
                
                // ── Switch login ↔ registrazione ───────────────────────────
                HStack(spacing: 4) {
                    Text(isRegistering ? "Hai già un account?" : "Non hai un account?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Button(isRegistering ? "Accedi" : "Registrati") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistering.toggle()
                            vm.errorMessage = nil
                            vm.resetPasswordSent = false
                            confirmPwd = ""
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                }
                
                Spacer().frame(height: 40)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)   // gestiamo noi il handle sopra
        .onTapGesture { hideKeyboard() }
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

// MARK: - KBTextField

private struct KBTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color(.systemBackground).opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - KBSecureField

private struct KBSecureField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var showPassword: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Group {
                if showPassword {
                    TextField(placeholder, text: $text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            
            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color(.systemBackground).opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
