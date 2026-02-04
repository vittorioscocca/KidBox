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
import OSLog

@MainActor
final class FirebaseGoogleAuthService {
    
    func signIn(presenting viewController: UIViewController) async throws -> User {
        
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw NSError(domain: "KidBoxAuth", code: -10)
        }
        
        GIDSignIn.sharedInstance.configuration =
        GIDConfiguration(clientID: clientID)
        
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: viewController
        )
        
        guard let idToken = result.user.idToken?.tokenString else {
            throw NSError(domain: "KidBoxAuth", code: -11)
        }
        
        let accessToken = result.user.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )
        
        let authResult = try await Auth.auth().signIn(with: credential)
        KBLog.auth.info("Google sign-in OK uid=\(authResult.user.uid, privacy: .public)")
        return authResult.user
    }
}
