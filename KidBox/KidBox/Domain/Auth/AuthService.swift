//
//  AuthService.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import FirebaseAuth
import UIKit

protocol AuthService {
    /// Provider supported by this service.
    var provider: AuthProvider { get }
    
    /// Signs in and returns the Firebase user.
    @MainActor
    func signIn(presentation: AuthPresentation) async throws -> User
    
    /// Signs out (if the provider requires extra cleanup, do it here).
    @MainActor
    func signOut() throws
}

/// Presentation context for auth flows.
/// Apple needs a UIWindow, Google needs a UIViewController.
enum AuthPresentation {
    case window(UIWindow)
    case viewController(UIViewController)
}
