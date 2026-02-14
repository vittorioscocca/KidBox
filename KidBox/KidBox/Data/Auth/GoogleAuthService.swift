//
//  GoogleAuthService.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import UIKit
import FirebaseAuth


/// Google authentication adapter implementing `AuthService`.
///
/// Responsibilities:
/// - Expose the provider type (`.google`)
/// - Validate the required presentation context (`UIViewController`)
/// - Delegate the concrete sign-in implementation to `FirebaseGoogleAuthService`
/// - Perform sign-out via FirebaseAuth (Google does not require extra steps here)
///
/// Notes:
/// - Runs on `MainActor` because Google Sign-In requires UI presentation.
/// - Does not own navigation; it only returns an authenticated Firebase `User`.
@MainActor
final class GoogleAuthService: AuthService {
    
    /// Identifies this service provider.
    let provider: AuthProvider = .google
    
    /// Concrete Firebase implementation (kept private to enforce abstraction).
    private let impl = FirebaseGoogleAuthService()
    
    /// Signs the user in with Google.
    ///
    /// - Parameter presentation: Presentation context required to show the Google sign-in UI.
    /// - Returns: The authenticated Firebase `User`.
    ///
    /// - Throws:
    ///   - An error if the presentation context is not `.viewController`.
    ///   - Any error thrown by the underlying Firebase/Google sign-in flow.
    func signIn(presentation: AuthPresentation) async throws -> User {
        KBLog.auth.kbInfo("GoogleAuthService sign-in requested")
        
        guard case let .viewController(vc) = presentation else {
            KBLog.auth.kbError("Google sign-in failed: invalid presentation (requires UIViewController)")
            throw NSError(
                domain: "KidBoxAuth",
                code: -21,
                userInfo: [
                    NSLocalizedDescriptionKey: "Google sign-in requires a UIViewController presentation."
                ]
            )
        }
        
        KBLog.auth.kbDebug("Delegating sign-in to FirebaseGoogleAuthService")
        let user = try await impl.signIn(presenting: vc)
        KBLog.auth.kbInfo("GoogleAuthService sign-in completed")
        return user
    }
    
    /// Signs the user out.
    ///
    /// Current behavior (unchanged):
    /// - FirebaseAuth signOut is sufficient for Google as well.
    ///
    /// - Throws: Any error thrown by FirebaseAuth sign-out.
    func signOut() throws {
        KBLog.auth.kbInfo("GoogleAuthService sign-out requested")
        
        do {
            try implSignOut()
            KBLog.auth.kbInfo("GoogleAuthService sign-out completed")
        } catch {
            KBLog.auth.kbError("GoogleAuthService sign-out failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Centralized Firebase sign-out implementation.
    ///
    /// Note: This intentionally uses FirebaseAuth only (no provider-specific cleanup).
    private func implSignOut() throws {
        KBLog.auth.kbDebug("Signing out via FirebaseAuth")
        try Auth.auth().signOut()
    }
}
