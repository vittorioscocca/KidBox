//
//  FirebaseGoogleAuthService.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn


/// Firebase-backed Google Sign-In service.
///
/// Responsibilities:
/// - Configure Google Sign-In using Firebase clientID
/// - Perform Google authentication flow
/// - Exchange Google tokens for Firebase credential
/// - Sign into FirebaseAuth
///
/// Security notes:
/// - Never log ID tokens or access tokens
/// - Avoid logging sensitive user data
///
/// Runs on `MainActor` because presentation requires UIKit.
@MainActor
final class FirebaseGoogleAuthService {
    
    /// Performs Google Sign-In and authenticates with Firebase.
    ///
    /// Flow (unchanged):
    /// 1. Read Firebase clientID
    /// 2. Configure `GIDSignIn`
    /// 3. Present Google sign-in UI
    /// 4. Extract idToken + accessToken
    /// 5. Build Firebase credential
    /// 6. Sign into Firebase
    ///
    /// - Parameter viewController: Controller used to present Google sign-in UI.
    /// - Returns: Authenticated Firebase `User`.
    func signIn(presenting viewController: UIViewController) async throws -> User {
        
        KBLog.auth.kbInfo("Google sign-in started")
        
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            KBLog.auth.kbError("Google sign-in failed: missing Firebase clientID")
            throw NSError(domain: "KidBoxAuth", code: -10)
        }
        
        KBLog.auth.kbDebug("Configuring GIDSignIn with Firebase clientID")
        GIDSignIn.sharedInstance.configuration =
        GIDConfiguration(clientID: clientID)
        
        KBLog.auth.kbDebug("Presenting Google sign-in UI")
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: viewController
        )
        
        guard let idToken = result.user.idToken?.tokenString else {
            KBLog.auth.kbError("Google sign-in failed: missing idToken")
            throw NSError(domain: "KidBoxAuth", code: -11)
        }
        
        // Never log idToken or accessToken
        let accessToken = result.user.accessToken.tokenString
        KBLog.auth.kbDebug("Google tokens received (not logged)")
        
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )
        
        KBLog.auth.kbDebug("Signing into Firebase with Google credential")
        let authResult = try await Auth.auth().signIn(with: credential)
        
        KBLog.auth.kbInfo("Google sign-in OK uid=\(authResult.user.uid)")
        
        return authResult.user
    }
}
