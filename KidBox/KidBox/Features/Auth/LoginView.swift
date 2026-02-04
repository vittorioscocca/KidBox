//
//  LoginView.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI
import AuthenticationServices
import SwiftData
import OSLog
import UIKit
import Combine

struct LoginView: View {
    
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
            
            // Apple
            SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in }
                .frame(height: 48)
                .overlay(
                    Button {
                        guard let windowScene = UIApplication.shared.connectedScenes
                            .compactMap({ $0 as? UIWindowScene }).first,
                              let window = windowScene.keyWindow else { return }
                        vm.signInApple(window: window)
                    } label: { Color.clear }
                )
            
            // Google
            Button {
                guard let vc = UIApplication.shared.topMostViewController else { return }
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
    }
}
