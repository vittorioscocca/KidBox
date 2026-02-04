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
import OSLog

/// Auth service for "Sign in with Apple" backed by FirebaseAuth.
@MainActor
final class FirebaseAppleAuthService: NSObject {
    
    func signInWithApple(presentationAnchor: ASPresentationAnchor) async throws -> User {
        let nonce = randomNonceString()
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let output = try await AppleSignInDelegate.signIn(
            request: request,
            presentationAnchor: presentationAnchor
        )
        
        let credential = OAuthProvider.appleCredential(
            withIDToken: output.idToken,
            rawNonce: nonce,
            fullName: output.fullName
        )
        
        let authResult = try await Auth.auth().signIn(with: credential)
        KBLog.auth.info("Firebase sign-in OK uid=\(authResult.user.uid, privacy: .public)")
        return authResult.user
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        KBLog.auth.info("Firebase sign-out OK")
    }
    
    func currentUser() -> User? {
        Auth.auth().currentUser
    }
}

// MARK: - Apple Delegate bridge

private final class AppleSignInDelegate: NSObject,
                                         ASAuthorizationControllerDelegate,
                                         ASAuthorizationControllerPresentationContextProviding {
    
    struct Output {
        let idToken: String
        let fullName: PersonNameComponents?
    }
    
    private var continuation: CheckedContinuation<Output, Error>?
    var presentationAnchor: ASPresentationAnchor?
    
    static func signIn(request: ASAuthorizationAppleIDRequest,
                       presentationAnchor: ASPresentationAnchor) async throws -> Output {
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
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let presentationAnchor else {
            fatalError("Missing presentationAnchor (UIWindow) for Apple Sign-In")
        }
        return presentationAnchor
    }
    
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = appleIDCredential.identityToken,
              let tokenString = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: NSError(domain: "KidBoxAuth", code: -1))
            continuation = nil
            return
        }
        
        continuation?.resume(returning: Output(idToken: tokenString, fullName: appleIDCredential.fullName))
        continuation = nil
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
// MARK: - Nonce helpers (Firebase recommended)

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

private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashedData = SHA256.hash(data: inputData)
    return hashedData.compactMap { String(format: "%02x", $0) }.joined()
}
