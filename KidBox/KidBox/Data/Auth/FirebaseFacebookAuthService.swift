//
//  FirebaseFacebookAuthService.swift
//  KidBox
//
//  Meta può mostrare limited.facebook.com (Limited Login): in quel caso non c’è un access token
//  Graph classico ma un OIDC (`AuthenticationToken`). Firebase richiede allora
//  `OAuthProvider` + `rawNonce` (vedi documentazione Firebase “Facebook Limited Login”).
//  Se Meta restituisce ancora un access token classico, usiamo `FacebookAuthProvider`.
//

import UIKit
import CryptoKit
import FirebaseAuth
import FBSDKLoginKit
import FBSDKCoreKit

@MainActor
final class FirebaseFacebookAuthService: NSObject {
    
    // MARK: - Public API
    
    func signInWithFacebook(presentingViewController: UIViewController) async throws -> User {
        KBLog.auth.kbInfo("Facebook sign-in (Firebase) started")
        
        let outcome = try await FacebookLoginDelegate.signIn(from: presentingViewController)
        KBLog.auth.kbDebug("Facebook login completed, building Firebase credential")
        
        let credential: AuthCredential
        switch outcome {
        case .graphAccessToken(let token):
            credential = FacebookAuthProvider.credential(withAccessToken: token)
        case .limitedOIDC(let idToken, let rawNonce):
            credential = OAuthProvider.credential(
                providerID: .facebook,
                idToken: idToken,
                rawNonce: rawNonce
            )
        }
        
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

private enum FacebookLoginOutcome {
    case graphAccessToken(String)
    case limitedOIDC(idToken: String, rawNonce: String)
}

private enum FacebookLoginCrypto {
    
    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if status != errSecSuccess {
            KBLog.auth.kbError("SecRandomCopyBytes failed status=\(status)")
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }
    
    static func sha256Hex(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private final class FacebookLoginDelegate {
    
    static func signIn(from viewController: UIViewController) async throws -> FacebookLoginOutcome {
        KBLog.auth.kbDebug("FacebookLoginDelegate.signIn invoked")
        
        await MainActor.run { LoginManager().logOut() }
        
        let rawNonce = FacebookLoginCrypto.randomNonceString()
        let hashedNonce = FacebookLoginCrypto.sha256Hex(rawNonce)
        
        return try await withCheckedThrowingContinuation { continuation in
            // Limited Login: Meta richiede il nonce SHA-256 nella richiesta; Firebase valida con rawNonce.
            // appSwitch .disabled: Limited Login non usa app switch (vedi doc Meta).
            guard let configuration = LoginConfiguration(
                permissions: ["public_profile", "email"],
                tracking: .limited,
                nonce: hashedNonce,
                appSwitch: .disabled
            ) else {
                KBLog.auth.kbError("Facebook LoginConfiguration init failed (permissions / nonce)")
                continuation.resume(throwing: AuthError.unknown)
                return
            }
            
            let manager = LoginManager()
            manager.logIn(viewController: viewController, configuration: configuration) { loginResult in
                switch loginResult {
                case .cancelled:
                    KBLog.auth.kbInfo("Facebook login cancelled by user")
                    continuation.resume(throwing: AuthError.cancelled)
                case let .failed(error):
                    KBLog.auth.kbError("Facebook SDK login error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                case .success:
                    if let idToken = AuthenticationToken.current?.tokenString, !idToken.isEmpty {
                        KBLog.auth.kbDebug("Facebook Limited Login OIDC token obtained (not logged)")
                        continuation.resume(returning: .limitedOIDC(idToken: idToken, rawNonce: rawNonce))
                        return
                    }
                    let access = AccessToken.current?.tokenString
                    if let access, !access.isEmpty {
                        KBLog.auth.kbDebug("Facebook Graph access token obtained (not logged)")
                        continuation.resume(returning: .graphAccessToken(access))
                        return
                    }
                    KBLog.auth.kbError("Facebook login: né Authentication né Access token dopo il login")
                    continuation.resume(throwing: AuthError.missingToken)
                }
            }
        }
    }
}
