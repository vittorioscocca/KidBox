//
//  AppleAuthService.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import UIKit
import FirebaseAuth


/// Apple Sign-In implementation of `AuthService`.
///
/// Responsibilities:
/// - Expose the provider type (`.apple`)
/// - Perform sign-in using a `UIWindow` presentation anchor
/// - Delegate the concrete Firebase implementation to `FirebaseAppleAuthService`
///
/// Notes:
/// - Runs on `MainActor` because presentation requires UIKit.
/// - Does not perform any navigation; it only authenticates and returns a Firebase `User`.
/// - Avoid logging sensitive user data (email, full name, identity tokens).
@MainActor
final class AppleAuthService: AuthService {
    
    /// Identifies this service provider.
    let provider: AuthProvider = .apple
    
    /// Concrete Firebase implementation (kept private to enforce abstraction).
    private let impl = FirebaseAppleAuthService()
    
    /// Signs the user in with Apple.
    ///
    /// - Parameter presentation: Presentation context required to show the Apple auth UI.
    /// - Returns: The authenticated Firebase `User`.
    ///
    /// - Throws:
    ///   - An error if the presentation context is not a `.window`.
    ///   - Any error thrown by the underlying Firebase implementation.
    func signIn(presentation: AuthPresentation) async throws -> User {
        KBLog.auth.kbInfo("Apple sign-in requested")
        
        guard case let .window(window) = presentation else {
            KBLog.auth.kbError("Apple sign-in failed: invalid presentation (requires UIWindow)")
            throw NSError(
                domain: "KidBoxAuth",
                code: -20,
                userInfo: [NSLocalizedDescriptionKey: "Apple sign-in requires a UIWindow presentation."]
            )
        }
        
        KBLog.auth.kbDebug("Calling FirebaseAppleAuthService.signInWithApple")
        let user = try await impl.signInWithApple(presentationAnchor: window)
        KBLog.auth.kbInfo("Apple sign-in completed")
        return user
    }
    
    /// Signs the user out from the Apple/Firebase authentication session.
    ///
    /// - Throws: Any error thrown by the underlying Firebase implementation.
    func signOut() throws {
        KBLog.auth.kbInfo("Apple sign-out requested")
        do {
            try impl.signOut()
            KBLog.auth.kbInfo("Apple sign-out completed")
        } catch {
            KBLog.auth.kbError("Apple sign-out failed: \(error.localizedDescription)")
            throw error
        }
    }
}
