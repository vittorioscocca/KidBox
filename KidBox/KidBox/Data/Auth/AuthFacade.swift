//
//  AuthFacade.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import FirebaseAuth

/// Central authentication facade.
///
/// `AuthFacade` abstracts multiple authentication providers
/// (Apple, Google, etc.) behind a unified interface.
///
/// Responsibilities:
/// - Hold registered `AuthService` implementations.
/// - Route sign-in requests to the correct provider.
/// - Perform global sign-out via FirebaseAuth.
///
/// Design:
/// - Uses a dictionary keyed by `AuthProvider`.
/// - Providers are injected at initialization time.
/// - Runs on `MainActor` because authentication flows may require UI presentation.
@MainActor
final class AuthFacade {
    
    // MARK: - Properties
    
    /// Registered authentication services indexed by provider.
    private let services: [AuthProvider: AuthService]
    
    // MARK: - Initialization
    
    /// Initializes the facade with a list of available auth services.
    ///
    /// - Parameter services: Array of concrete `AuthService` implementations.
    ///   Each service must expose its own `provider` identifier.
    ///
    /// If multiple services declare the same provider,
    /// the last one in the array overrides the previous.
    init(services: [AuthService]) {
        KBLog.auth.kbInfo("AuthFacade init with \(services.count) services")
        
        var dict: [AuthProvider: AuthService] = [:]
        services.forEach {
            KBLog.auth.kbDebug("Registering auth provider: \($0.provider.rawValue)")
            dict[$0.provider] = $0
        }
        
        self.services = dict
        
        KBLog.auth.kbInfo("AuthFacade ready with \(dict.count) providers")
    }
    
    // MARK: - Sign In
    
    /// Performs sign-in using the specified provider.
    ///
    /// - Parameters:
    ///   - provider: The authentication provider (Apple, Google, etc.).
    ///   - presentation: Presentation context required by certain providers.
    ///
    /// - Returns: Authenticated Firebase `User`.
    ///
    /// - Throws:
    ///   - If the requested provider is not registered.
    ///   - Any error thrown by the underlying `AuthService`.
    func signIn(
        with provider: AuthProvider,
        presentation: AuthPresentation
    ) async throws -> User {
        
        KBLog.auth.kbInfo("Sign-in requested for provider: \(provider.rawValue)")
        
        guard let service = services[provider] else {
            KBLog.auth.kbError("Auth provider not available: \(provider.rawValue)")
            throw NSError(
                domain: "KidBoxAuth",
                code: -30,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Auth provider not available: \(provider.rawValue)"
                ]
            )
        }
        
        KBLog.auth.kbDebug("Delegating sign-in to provider: \(provider.rawValue)")
        let user = try await service.signIn(presentation: presentation)
        KBLog.auth.kbInfo("Sign-in completed for provider: \(provider.rawValue)")
        
        return user
    }
    
    // MARK: - Sign Out
    
    /// Signs out the current Firebase user.
    ///
    /// - Throws: Any error thrown by `FirebaseAuth`.
    ///
    /// Note:
    /// This performs a global Firebase sign-out, not provider-specific logic.
    func signOut() throws {
        KBLog.auth.kbInfo("Global sign-out requested")
        
        do {
            try Auth.auth().signOut()
            KBLog.auth.kbInfo("Firebase sign-out successful")
        } catch {
            KBLog.auth.kbError("Firebase sign-out failed: \(error.localizedDescription)")
            throw error
        }
    }
}
