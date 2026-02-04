//
//  GoogleAuthService.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import UIKit
import FirebaseAuth

@MainActor
final class GoogleAuthService: AuthService {
    let provider: AuthProvider = .google
    private let impl = FirebaseGoogleAuthService()
    
    func signIn(presentation: AuthPresentation) async throws -> User {
        guard case let .viewController(vc) = presentation else {
            throw NSError(domain: "KidBoxAuth", code: -21, userInfo: [
                NSLocalizedDescriptionKey: "Google sign-in requires a UIViewController presentation."
            ])
        }
        return try await impl.signIn(presenting: vc)
    }
    
    func signOut() throws {
        // Firebase signOut is enough for Google too
        try implSignOut()
    }
    
    private func implSignOut() throws {
        // centralize signOut to FirebaseAuth only
        try Auth.auth().signOut()
    }
}
