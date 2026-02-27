//
//  FacebookAuthService.swift
//  KidBox
//
//  Created by vscocca on 27/02/26.
//


import Foundation
import UIKit
import FirebaseAuth

/// Facebook Sign-In implementation of `AuthService`.
///
/// Responsibilities:
/// - Expose the provider type (`.facebook`)
/// - Perform sign-in using a `UIViewController` presentation context
/// - Delegate the concrete Firebase implementation to `FirebaseFacebookAuthService`
///
/// Notes:
/// - Runs on `MainActor` because presentation requires UIKit.
/// - Does not perform any navigation; it only authenticates and returns a Firebase `User`.
/// - Never log sensitive user data (access tokens, email, profile info).
@MainActor
final class FacebookAuthService: AuthService {
    
    /// Identifies this service provider.
    let provider: AuthProvider = .facebook
    
    /// Concrete Firebase implementation (kept private to enforce abstraction).
    private let impl = FirebaseFacebookAuthService()
    
    /// Signs the user in with Facebook.
    ///
    /// - Parameter presentation: Presentation context required to show the Facebook auth UI.
    /// - Returns: The authenticated Firebase `User`.
    ///
    /// - Throws:
    ///   - An error if the presentation context is not a `.viewController`.
    ///   - `AuthError.cancelled` if the user dismisses the Facebook dialog.
    ///   - Any error thrown by the underlying Firebase implementation.
    func signIn(presentation: AuthPresentation) async throws -> User {
        KBLog.auth.kbInfo("Facebook sign-in requested")
        
        guard case let .viewController(vc) = presentation else {
            KBLog.auth.kbError("Facebook sign-in failed: invalid presentation (requires UIViewController)")
            throw NSError(
                domain: "KidBoxAuth",
                code: -21,
                userInfo: [NSLocalizedDescriptionKey: "Facebook sign-in requires a UIViewController presentation."]
            )
        }
        
        KBLog.auth.kbDebug("Calling FirebaseFacebookAuthService.signInWithFacebook")
        let user = try await impl.signInWithFacebook(presentingViewController: vc)
        KBLog.auth.kbInfo("Facebook sign-in completed")
        return user
    }
    
    /// Signs the user out from the Facebook/Firebase authentication session.
    ///
    /// - Throws: Any error thrown by the underlying Firebase implementation.
    func signOut() throws {
        KBLog.auth.kbInfo("Facebook sign-out requested")
        do {
            try impl.signOut()
            KBLog.auth.kbInfo("Facebook sign-out completed")
        } catch {
            KBLog.auth.kbError("Facebook sign-out failed: \(error.localizedDescription)")
            throw error
        }
    }
}
