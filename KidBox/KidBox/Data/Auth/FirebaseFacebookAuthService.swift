//
//  FirebaseFacebookAuthService.swift
//  KidBox
//
//  Created by vscocca on 27/02/26.
//

import UIKit
import FirebaseAuth
import FBSDKLoginKit
import FBSDKCoreKit

/// Firebase-backed "Sign in with Facebook" implementation.
///
/// Responsibilities:
/// - Present the Facebook login dialog via `LoginManager`.
/// - Bridge the callback-based Facebook SDK into async/await.
/// - Build a Firebase OAuth credential from the Facebook access token.
/// - Sign in/out using FirebaseAuth.
///
/// Prerequisites:
/// 1. Add `FacebookSDK` (FBSDKLoginKit, FBSDKCoreKit) via SPM:
///    `https://github.com/facebook/facebook-ios-sdk`
/// 2. Configure `Info.plist`:
///    - `FacebookAppID`        → your Meta App ID (string)
///    - `FacebookClientToken`  → your Meta Client Token
///    - `FacebookDisplayName`  → your app name
///    - `CFBundleURLTypes`     → add scheme `fb<APP_ID>`
/// 3. In `AppDelegate.application(_:didFinishLaunchingWithOptions:)`:
///    ```swift
///    ApplicationDelegate.shared.application(app, didFinishLaunchingWithOptions: options)
///    ```
/// 4. In `AppDelegate.application(_:open:options:)`:
///    ```swift
///    ApplicationDelegate.shared.application(app, open: url, options: options)
///    ```
/// 5. Enable Facebook provider in Firebase Console → Authentication → Sign-in method.
///
/// Security notes:
/// - Never log access tokens or user PII.
/// - The Facebook access token is passed directly to Firebase and not stored locally.
@MainActor
final class FirebaseFacebookAuthService: NSObject {
    
    // MARK: - Public API
    
    /// Presents the Facebook login dialog and signs into Firebase using the resulting credential.
    ///
    /// Flow:
    /// 1. Present Facebook login via `LoginManager` (bridged to async/await)
    /// 2. Extract access token from the result
    /// 3. Build Firebase `OAuthCredential` from the token
    /// 4. Sign into Firebase
    ///
    /// - Parameter viewController: The view controller used to present the Facebook login sheet.
    /// - Returns: The authenticated Firebase `User`.
    func signInWithFacebook(presentingViewController: UIViewController) async throws -> User {
        KBLog.auth.kbInfo("Facebook sign-in (Firebase) started")
        
        // Step 1 — Facebook login
        let accessToken = try await FacebookLoginDelegate.signIn(from: presentingViewController)
        KBLog.auth.kbDebug("Facebook login completed, building Firebase credential")
        
        // Step 2 — Firebase credential
        let credential = FacebookAuthProvider.credential(withAccessToken: accessToken)
        
        // Step 3 — Firebase sign-in
        let authResult = try await Auth.auth().signIn(with: credential)
        KBLog.auth.kbInfo("Firebase sign-in OK uid=\(authResult.user.uid)")
        
        return authResult.user
    }
    
    /// Signs out of both Firebase and the Facebook SDK.
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
    
    /// Returns the current Firebase user if available.
    func currentUser() -> User? {
        Auth.auth().currentUser
    }
}

// MARK: - Facebook login delegate bridge

/// Bridges `LoginManager`'s callback-based API into async/await.
///
/// Kept private to ensure callers go through `FirebaseFacebookAuthService.signInWithFacebook`.
private final class FacebookLoginDelegate {
    
    /// Presents the Facebook login UI and returns the raw access token string.
    ///
    /// - Parameter viewController: The presenting view controller.
    /// - Returns: Facebook access token string (never logged).
    /// - Throws: `AuthError.cancelled` if the user dismisses the dialog,
    ///           or any error returned by the Facebook SDK.
    static func signIn(from viewController: UIViewController) async throws -> String {
        KBLog.auth.kbDebug("FacebookLoginDelegate.signIn invoked")
        
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
                
                guard let tokenString = result.token?.tokenString else {
                    KBLog.auth.kbError("Facebook login succeeded but access token is missing")
                    continuation.resume(throwing: AuthError.missingToken)
                    return
                }
                
                // Do not log tokenString (sensitive).
                KBLog.auth.kbDebug("Facebook access token obtained (not logged)")
                continuation.resume(returning: tokenString)
            }
        }
    }
}
