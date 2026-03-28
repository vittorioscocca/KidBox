//
//  FirebaseFacebookAuthService.swift
//  KidBox
//
//  Fix per Facebook SDK 17.4.0:
//  Il token restituito da LoginManager.logIn() non è più direttamente
//  utilizzabile da Firebase come OAuth token. Occorre:
//  1. Fare il login normalmente con LoginManager
//  2. Usare AccessToken.current (che SDK 17.x popola correttamente)
//  3. Passare tokenString di AccessToken.current a Firebase
//

import UIKit
import FirebaseAuth
import FBSDKLoginKit
import FBSDKCoreKit

@MainActor
final class FirebaseFacebookAuthService: NSObject {
    
    // MARK: - Public API
    
    func signInWithFacebook(presentingViewController: UIViewController) async throws -> User {
        KBLog.auth.kbInfo("Facebook sign-in (Firebase) started")
        
        // Step 1 — Facebook login + token
        let tokenString = try await FacebookLoginDelegate.signIn(from: presentingViewController)
        KBLog.auth.kbDebug("Facebook login completed, building Firebase credential")
        
        // Step 2 — Firebase credential
        let credential = FacebookAuthProvider.credential(withAccessToken: tokenString)
        
        // Step 3 — Firebase sign-in
        let authResult = try await Auth.auth().signIn(with: credential)
        KBLog.auth.kbInfo("Firebase sign-in OK uid=\(authResult.user.uid)")
        
        return authResult.user
    }
    
    func signOut() throws {
        KBLog.auth.kbInfo("Firebase sign-out requested (Facebook service)")
        do {
            try Auth.auth().signOut()
            LoginManager().logOut()
            KBLog.auth.kbInfo("Firebase + Facebook sign-out OK")
        } catch {
            KBLog.auth.kbError("Firebase sign-out failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func currentUser() -> User? {
        Auth.auth().currentUser
    }
}

// MARK: - Facebook login delegate bridge

private final class FacebookLoginDelegate {
    
    static func signIn(from viewController: UIViewController) async throws -> String {
        KBLog.auth.kbDebug("FacebookLoginDelegate.signIn invoked")
        
        // Prima logga out qualsiasi sessione Facebook precedente
        // per forzare un token fresco — evita il "Cannot parse access token"
        // che si verifica con sessioni cached del SDK 17.x
        await MainActor.run { LoginManager().logOut() }
        
        return try await withCheckedThrowingContinuation { continuation in
            let manager = LoginManager()
            manager.logIn(
                permissions: ["public_profile", "email"],
                from: viewController
            ) { result, error in
                
                if let error {
                    KBLog.auth.kbError("Facebook SDK login error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result else {
                    KBLog.auth.kbError("Facebook SDK returned nil result without error")
                    continuation.resume(throwing: AuthError.unknown)
                    return
                }
                
                if result.isCancelled {
                    KBLog.auth.kbInfo("Facebook login cancelled by user")
                    continuation.resume(throwing: AuthError.cancelled)
                    return
                }
                
                // FIX SDK 17.x: result.token può essere nil o avere un token
                // non parsabile da Firebase. Usiamo AccessToken.current
                // che viene popolato correttamente dal SDK dopo il login.
                let tokenString = AccessToken.current?.tokenString
                ?? result.token?.tokenString
                
                guard let tokenString, !tokenString.isEmpty else {
                    KBLog.auth.kbError("Facebook login: access token nil after login")
                    continuation.resume(throwing: AuthError.missingToken)
                    return
                }
                
                KBLog.auth.kbDebug("Facebook access token obtained via AccessToken.current (not logged)")
                continuation.resume(returning: tokenString)
            }
        }
    }
}
