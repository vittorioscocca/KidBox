//
//  AuthFacade.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import FirebaseAuth

@MainActor
final class AuthFacade {
    
    private let services: [AuthProvider: AuthService]
    
    init(services: [AuthService]) {
        var dict: [AuthProvider: AuthService] = [:]
        services.forEach { dict[$0.provider] = $0 }
        self.services = dict
    }
    
    func signIn(with provider: AuthProvider, presentation: AuthPresentation) async throws -> User {
        guard let service = services[provider] else {
            throw NSError(domain: "KidBoxAuth", code: -30, userInfo: [
                NSLocalizedDescriptionKey: "Auth provider not available: \(provider.rawValue)"
            ])
        }
        return try await service.signIn(presentation: presentation)
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
    }
}
