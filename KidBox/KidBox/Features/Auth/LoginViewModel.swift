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
import OSLog

@MainActor
final class LoginViewModel: ObservableObject {
    
    @Published var isBusy = false
    @Published var errorMessage: String?
    
    private let auth: AuthFacade
    
    init(auth: AuthFacade) {
        self.auth = auth
    }
    
    func signInApple(window: UIWindow) {
        Task { await signIn(provider: .apple, presentation: .window(window)) }
    }
    
    func signInGoogle(viewController: UIViewController) {
        Task { await signIn(provider: .google, presentation: .viewController(viewController)) }
    }
    
    private func signIn(provider: AuthProvider, presentation: AuthPresentation) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        
        do {
            _ = try await auth.signIn(with: provider, presentation: presentation)
        } catch {
            errorMessage = error.localizedDescription
            KBLog.auth.error("Sign-in failed (\(provider.rawValue, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func signOut() {
        do { try auth.signOut() } catch { }
    }
}
