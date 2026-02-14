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
/// - Orchestrates Apple and Google sign-in flows.
/// - Exposes loading state (`isBusy`) and error state (`errorMessage`) to the UI.
/// - Delegates actual authentication to `AuthFacade`.
///
/// Logging strategy:
/// - Log user intent (provider tapped).
/// - Log start/success/failure of sign-in.
/// - Avoid logging sensitive data (tokens, emails).
@MainActor
final class LoginViewModel: ObservableObject {
    
    // MARK: - Published State
    
    /// Indicates whether a sign-in operation is currently in progress.
    @Published var isBusy = false
    
    /// Human-readable error message shown in the UI.
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    
    private let auth: AuthFacade
    
    // MARK: - Init
    
    init(auth: AuthFacade) {
        self.auth = auth
        KBLog.auth.kbDebug("LoginViewModel initialized")
    }
    
    // MARK: - Public API
    
    /// Starts Apple sign-in flow.
    func signInApple(window: UIWindow) {
        KBLog.auth.kbInfo("LoginViewModel signInApple requested")
        Task { await signIn(provider: .apple, presentation: .window(window)) }
    }
    
    /// Starts Google sign-in flow.
    func signInGoogle(viewController: UIViewController) {
        KBLog.auth.kbInfo("LoginViewModel signInGoogle requested")
        Task { await signIn(provider: .google, presentation: .viewController(viewController)) }
    }
    
    /// Signs the current user out.
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
    
    /// Centralized async sign-in logic.
    ///
    /// - Important: Ensures `isBusy` is correctly reset using `defer`.
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
        } catch {
            errorMessage = error.localizedDescription
            KBLog.auth.kbError(
                "Sign-in failed provider=\(provider.rawValue) error=\(error.localizedDescription)"
            )
        }
    }
}
