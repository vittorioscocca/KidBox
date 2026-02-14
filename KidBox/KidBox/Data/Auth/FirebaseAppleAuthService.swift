//
//  FirebaseAppleAuthService.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseAuth

/// Firebase-backed "Sign in with Apple" implementation.
///
/// Responsibilities:
/// - Create Apple authorization request with a Firebase-compatible nonce.
/// - Bridge ASAuthorizationController callback-based API into async/await.
/// - Build Firebase OAuth credential from Apple ID token and nonce.
/// - Sign in/out using FirebaseAuth.
///
/// Security notes:
/// - Never log identity tokens or raw nonces.
/// - Avoid logging user PII (email/fullName).
@MainActor
final class FirebaseAppleAuthService: NSObject {
    
    /// Performs Apple Sign-In and then signs into Firebase using the resulting Apple credential.
    ///
    /// Flow (unchanged):
    /// 1. Generate nonce
    /// 2. Create AppleID request, attach SHA256(nonce)
    /// 3. Perform Apple sign-in via delegate bridge
    /// 4. Convert Apple output to Firebase OAuth credential
    /// 5. Sign into Firebase
    ///
    /// - Parameter presentationAnchor: The window used to present the Apple sign-in sheet.
    /// - Returns: The authenticated Firebase `User`.
    func signInWithApple(presentationAnchor: ASPresentationAnchor) async throws -> User {
        KBLog.auth.kbInfo("Apple sign-in (Firebase) started")
        
        let nonce = randomNonceString()
        KBLog.auth.kbDebug("Nonce generated (not logged)")
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        KBLog.auth.kbDebug("Performing Apple authorization request")
        let output = try await AppleSignInDelegate.signIn(
            request: request,
            presentationAnchor: presentationAnchor
        )
        
        KBLog.auth.kbDebug("Apple authorization completed, building Firebase credential")
        let credential = OAuthProvider.appleCredential(
            withIDToken: output.idToken,
            rawNonce: nonce,
            fullName: output.fullName
        )
        
        let authResult = try await Auth.auth().signIn(with: credential)
        KBLog.auth.kbInfo("Firebase sign-in OK uid=\(authResult.user.uid)")
        
        return authResult.user
    }
    
    /// Signs out the current Firebase user.
    func signOut() throws {
        KBLog.auth.kbInfo("Firebase sign-out requested (Apple service)")
        
        do {
            try Auth.auth().signOut()
            KBLog.auth.kbInfo("Firebase sign-out OK")
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

// MARK: - Apple Delegate bridge

/// Bridges `ASAuthorizationController` delegate callbacks to async/await.
///
/// This is kept private to ensure callers use `FirebaseAppleAuthService.signInWithApple`.
private final class AppleSignInDelegate: NSObject,
                                         ASAuthorizationControllerDelegate,
                                         ASAuthorizationControllerPresentationContextProviding {
    
    /// Successful output extracted from Apple authorization.
    struct Output {
        let idToken: String
        let fullName: PersonNameComponents?
    }
    
    /// Continuation used to resume the async call once Apple completes.
    private var continuation: CheckedContinuation<Output, Error>?
    
    /// Anchor window used for presenting the authorization sheet.
    var presentationAnchor: ASPresentationAnchor?
    
    /// Runs Apple sign-in for a given request and returns the extracted output.
    ///
    /// - Important: The ID token must be present and convertible to UTF-8 string.
    static func signIn(
        request: ASAuthorizationAppleIDRequest,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> Output {
        KBLog.auth.kbDebug("AppleSignInDelegate.signIn invoked")
        
        let delegate = AppleSignInDelegate()
        delegate.presentationAnchor = presentationAnchor
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        controller.presentationContextProvider = delegate
        controller.performRequests()
        
        return try await withCheckedThrowingContinuation { cont in
            delegate.continuation = cont
        }
    }
    
    /// Provides the anchor window for the Apple sign-in UI.
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let presentationAnchor else {
            // This is a programmer error: presentationAnchor must be set before performing requests.
            KBLog.auth.kbError("Missing presentationAnchor for Apple Sign-In (fatalError)")
            fatalError("Missing presentationAnchor (UIWindow) for Apple Sign-In")
        }
        return presentationAnchor
    }
    
    /// Delegate callback on successful authorization.
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        KBLog.auth.kbDebug("Apple authorizationController didCompleteWithAuthorization")
        
        guard
            let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = appleIDCredential.identityToken,
            let tokenString = String(data: tokenData, encoding: .utf8)
        else {
            KBLog.auth.kbError("Apple authorization missing/invalid identityToken")
            continuation?.resume(throwing: NSError(domain: "KidBoxAuth", code: -1))
            continuation = nil
            return
        }
        
        // Do not log tokenString (sensitive).
        continuation?.resume(
            returning: Output(idToken: tokenString, fullName: appleIDCredential.fullName)
        )
        continuation = nil
    }
    
    /// Delegate callback on error.
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        KBLog.auth.kbError("Apple authorization failed: \(error.localizedDescription)")
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

// MARK: - Nonce helpers (Firebase recommended)

/// Generates a cryptographically secure random nonce (Firebase recommended).
///
/// - Parameter length: Desired nonce length.
/// - Returns: Random nonce string.
private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    
    let charset: [Character] =
    Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    
    var result = ""
    var remainingLength = length
    
    while remainingLength > 0 {
        var randoms: [UInt8] = [UInt8](repeating: 0, count: 16)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
        if errorCode != errSecSuccess {
            // Programmer/environment error: secure random generator must be available.
            KBLog.auth.kbError("Unable to generate nonce (SecRandomCopyBytes failed) -> fatalError")
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed.")
        }
        
        randoms.forEach { random in
            if remainingLength == 0 { return }
            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
    }
    
    return result
}

/// Returns the SHA256 hash of the input string as a hex string.
///
/// Used to attach the hashed nonce to the Apple request.
private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashedData = SHA256.hash(data: inputData)
    return hashedData.compactMap { String(format: "%02x", $0) }.joined()
}
