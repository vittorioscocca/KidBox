//
//  AppleAuthService.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import UIKit
import FirebaseAuth

@MainActor
final class AppleAuthService: AuthService {
    let provider: AuthProvider = .apple
    private let impl = FirebaseAppleAuthService()
    
    func signIn(presentation: AuthPresentation) async throws -> User {
        guard case let .window(window) = presentation else {
            throw NSError(domain: "KidBoxAuth", code: -20, userInfo: [
                NSLocalizedDescriptionKey: "Apple sign-in requires a UIWindow presentation."
            ])
        }
        return try await impl.signInWithApple(presentationAnchor: window)
    }
    
    func signOut() throws {
        try impl.signOut()
    }
}
