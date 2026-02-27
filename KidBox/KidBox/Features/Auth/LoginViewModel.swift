//
//  LoginViewModel.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import Combine
import FirebaseAuth
import UIKit

/// ViewModel responsible for handling authentication flows in `LoginView`.
///
/// Responsibilities:
/// - Orchestrates Apple, Google, Facebook and Email/Password sign-in flows.
/// - Exposes loading state (`isBusy`) and error state (`errorMessage`) to the UI.
/// - Delegates social auth to `AuthFacade` (Apple, Google) and
///   `FirebaseFacebookAuthService` (Facebook) directly — same pattern used by Apple.
///
/// Logging strategy:
/// - Log user intent (provider tapped).
/// - Log start / success / failure of sign-in.
/// - Never log sensitive data (tokens, emails, passwords).
@MainActor
final class LoginViewModel: ObservableObject {
    
    // MARK: - Published State
    
    /// Indicates whether a sign-in operation is currently in progress.
    @Published var isBusy            = false
    
    /// Human-readable error message shown in the UI.
    @Published var errorMessage: String?
    
    /// Set to `true` after a successful password-reset email dispatch.
    @Published var resetPasswordSent = false
    
    // MARK: - Dependencies
    
    private let auth:        AuthFacade
    private let facebookAuth = FirebaseFacebookAuthService()
    
    // MARK: - Init
    
    init(auth: AuthFacade) {
        self.auth = auth
        KBLog.auth.kbDebug("LoginViewModel initialized")
    }
    
    // MARK: - Social Sign-In
    
    func signInApple(window: UIWindow) {
        KBLog.auth.kbInfo("LoginViewModel signInApple requested")
        Task { await signIn(provider: .apple, presentation: .window(window)) }
    }
    
    func signInGoogle(viewController: UIViewController) {
        KBLog.auth.kbInfo("LoginViewModel signInGoogle requested")
        Task { await signIn(provider: .google, presentation: .viewController(viewController)) }
    }
    
    func signInFacebook(viewController: UIViewController) {
        KBLog.auth.kbInfo("LoginViewModel signInFacebook requested")
        Task {
            isBusy = true
            errorMessage = nil
            defer {
                isBusy = false
                KBLog.auth.kbDebug("Sign-in finished provider=facebook isBusy=false")
            }
            do {
                _ = try await facebookAuth.signInWithFacebook(presentingViewController: viewController)
                KBLog.auth.kbInfo("Sign-in success provider=facebook")
            } catch AuthError.cancelled {
                // Utente ha annullato — nessun messaggio di errore
                KBLog.auth.kbInfo("Sign-in cancelled provider=facebook")
            } catch {
                errorMessage = friendlyError(error)
                KBLog.auth.kbError("Sign-in failed provider=facebook error=\(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Email / Password
    
    /// Accesso con email e password esistenti.
    func signInEmail(email: String, password: String) async {
        KBLog.auth.kbInfo("LoginViewModel signInEmail requested")
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
            KBLog.auth.kbInfo("LoginViewModel signInEmail success")
        } catch {
            errorMessage = friendlyError(error)
            KBLog.auth.kbError("LoginViewModel signInEmail failed: \(error.localizedDescription)")
        }
    }
    
    /// Registrazione nuovo utente con email e password.
    func registerEmail(email: String, password: String) async {
        KBLog.auth.kbInfo("LoginViewModel registerEmail requested")
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        
        do {
            try await Auth.auth().createUser(withEmail: email, password: password)
            KBLog.auth.kbInfo("LoginViewModel registerEmail success")
        } catch {
            errorMessage = friendlyError(error)
            KBLog.auth.kbError("LoginViewModel registerEmail failed: \(error.localizedDescription)")
        }
    }
    
    /// Invia l'email di reset password.
    func resetPassword(email: String) {
        guard !email.isEmpty else { return }
        KBLog.auth.kbInfo("LoginViewModel resetPassword requested")
        resetPasswordSent = false
        errorMessage = nil
        
        Task {
            do {
                try await Auth.auth().sendPasswordReset(withEmail: email)
                resetPasswordSent = true
                KBLog.auth.kbInfo("LoginViewModel resetPassword email sent")
            } catch {
                errorMessage = friendlyError(error)
                KBLog.auth.kbError("LoginViewModel resetPassword failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        KBLog.auth.kbInfo("LoginViewModel signOut requested")
        do {
            try auth.signOut()
            KBLog.auth.kbInfo("LoginViewModel signOut success")
        } catch {
            KBLog.auth.kbError("LoginViewModel signOut failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private
    
    /// Centralised async sign-in logic for Apple and Google (via AuthFacade).
    private func signIn(provider: AuthProvider, presentation: AuthPresentation) async {
        KBLog.auth.kbInfo("Sign-in started provider=\(provider.rawValue)")
        
        isBusy = true
        errorMessage = nil
        
        defer {
            isBusy = false
            KBLog.auth.kbDebug("Sign-in finished provider=\(provider.rawValue) isBusy=false")
        }
        
        do {
            _ = try await auth.signIn(with: provider, presentation: presentation)
            KBLog.auth.kbInfo("Sign-in success provider=\(provider.rawValue)")
        } catch AuthError.cancelled {
            // Utente ha annullato: non mostriamo errori
            KBLog.auth.kbInfo("Sign-in cancelled provider=\(provider.rawValue)")
        } catch {
            errorMessage = friendlyError(error)
            KBLog.auth.kbError("Sign-in failed provider=\(provider.rawValue) error=\(error.localizedDescription)")
        }
    }
    
    /// Traduce i codici di errore Firebase in messaggi leggibili in italiano.
    private func friendlyError(_ error: Error) -> String {
        let code = (error as NSError).code
        switch AuthErrorCode(rawValue: code) {
        case .emailAlreadyInUse:
            return "Questa email è già registrata. Prova ad accedere."
        case .invalidEmail:
            return "Indirizzo email non valido."
        case .weakPassword:
            return "La password è troppo debole (min. 6 caratteri)."
        case .wrongPassword:
            return "Password errata. Riprova o usa \"Password dimenticata\"."
        case .userNotFound:
            return "Nessun account trovato con questa email."
        case .networkError:
            return "Errore di rete. Controlla la connessione."
        case .tooManyRequests:
            return "Troppi tentativi. Riprova tra qualche minuto."
        case .userDisabled:
            return "Account disabilitato. Contatta il supporto."
        default:
            return error.localizedDescription
        }
    }
}
