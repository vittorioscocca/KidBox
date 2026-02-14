//
//  LoginView.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI
import AuthenticationServices
import SwiftData
import UIKit
import Combine

/// Login screen for KidBox.
///
/// Shows:
/// - App title
/// - Error message (if any)
/// - Sign in with Apple (overlay trick to get the `UIWindow`)
/// - Sign in with Google (needs a presenting `UIViewController`)
///
/// Logging notes (views):
/// - Avoid logging in `body` (it can run many times).
/// - Prefer `.onAppear`, `.onDisappear`, and discrete user actions (button taps).
struct LoginView: View {
    
    /// ViewModel responsible for auth flows and error/state handling.
    @StateObject private var vm = LoginViewModel(
        auth: AuthFacade(services: [
            AppleAuthService(),
            GoogleAuthService()
        ])
    )
    
    var body: some View {
        VStack(spacing: 16) {
            Text("KidBox").font(.largeTitle).bold()
            
            if let error = vm.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            
            // MARK: - Apple
            
            SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in }
                .frame(height: 48)
                .overlay(
                    Button {
                        KBLog.auth.kbInfo("LoginView Apple sign-in tapped")
                        
                        guard let windowScene = UIApplication.shared.connectedScenes
                            .compactMap({ $0 as? UIWindowScene }).first,
                              let window = windowScene.keyWindow
                        else {
                            KBLog.auth.kbError("LoginView Apple sign-in failed: missing UIWindow")
                            return
                        }
                        
                        vm.signInApple(window: window)
                    } label: { Color.clear }
                )
            
            // MARK: - Google
            
            Button {
                KBLog.auth.kbInfo("LoginView Google sign-in tapped isBusy=\(vm.isBusy)")
                
                guard let vc = UIApplication.shared.topMostViewController else {
                    KBLog.auth.kbError("LoginView Google sign-in failed: missing UIViewController")
                    return
                }
                
                vm.signInGoogle(viewController: vc)
            } label: {
                Text(vm.isBusy ? "Accesso…" : "Accedi con Google")
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isBusy)
        }
        .padding()
        .onAppear {
            KBLog.navigation.kbDebug("LoginView appeared")
        }
        .onDisappear {
            KBLog.navigation.kbDebug("LoginView disappeared")
        }
        .onChange(of: vm.isBusy) { _, newValue in
            KBLog.auth.kbDebug("LoginView isBusy changed -> \(newValue)")
        }
        .onChange(of: vm.errorMessage) { _, newValue in
            if newValue != nil {
                KBLog.auth.kbError("LoginView errorMessage set")
            } else {
                KBLog.auth.kbDebug("LoginView errorMessage cleared")
            }
        }
    }
}
