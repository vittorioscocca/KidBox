//
//  LoginView.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI
import AuthenticationServices
import UIKit
import Combine

struct LoginView: View {
    
    @StateObject private var vm = LoginViewModel(
        auth: AuthFacade(services: [
            AppleAuthService(),
            GoogleAuthService(),
            FacebookAuthService()
        ])
    )
    
    @State private var showEmailAuth = false
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Dynamic theme
    
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    private var primaryText: Color { .primary }
    private var secondaryText: Color { .secondary }
    
    private var primaryButtonBackground: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var primaryButtonForeground: Color {
        colorScheme == .dark ? .black : .white
    }
    
    private var overlayScrim: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    
                    Spacer().frame(height: 72)
                    
                    // ── Logo + Tagline ─────────────────────────────────────
                    logoSection
                    
                    Spacer().frame(height: 52)
                    
                    // ── Provider buttons ───────────────────────────────────
                    VStack(spacing: 12) {
                        googleButton
                        appleButton
                        facebookButton
                    }
                    .padding(.horizontal, 28)
                    
                    // ── Divisore ───────────────────────────────────────────
                    divider
                        .padding(.horizontal, 28)
                        .padding(.vertical, 20)
                    
                    // ── Email button ───────────────────────────────────────
                    emailButton
                        .padding(.horizontal, 28)
                    
                    // ── Errore ─────────────────────────────────────────────
                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .padding(.top, 12)
                    }
                    
                    Spacer().frame(height: 32)
                    
                    // ── Footer legale ──────────────────────────────────────
                    legalFooter
                        .padding(.horizontal, 28)
                    
                    Spacer().frame(height: 40)
                }
            }
            .disabled(vm.isBusy)
            .blur(radius: vm.isBusy ? 1 : 0)
            
            if vm.isBusy {
                overlayScrim
                    .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Accesso in corso…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(primaryText)
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthView(vm: vm)
        }
        .onAppear { KBLog.navigation.kbDebug("LoginView appeared") }
        .onDisappear { KBLog.navigation.kbDebug("LoginView disappeared") }
        .animation(.default, value: vm.isBusy)
    }
    
    // MARK: - Logo
    
    private var logoSection: some View {
        VStack(spacing: 16) {
            Image("LoginIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Text("KidBox")
                .font(.system(size: 36, weight: .semibold, design: .serif))
                .foregroundStyle(primaryText)
            
            Text("La tua famiglia,\nin un'unica app.")
                .font(.system(size: 26, weight: .medium, design: .serif))
                .foregroundStyle(primaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }
    
    // MARK: - Buttons
    
    private var googleButton: some View {
        ProviderButton(
            label: "Continua con Google",
            icon: { GoogleIcon() },
            isLoading: vm.isBusy,
            background: primaryButtonBackground,
            foreground: primaryButtonForeground
        ) {
            KBLog.auth.kbInfo("LoginView Google tapped")
            guard let vc = UIApplication.shared.topMostViewController else { return }
            vm.signInGoogle(viewController: vc)
        }
    }
    
    private var appleButton: some View {
        ZStack {
            SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in }
                .frame(height: 52)
                .clipShape(Capsule())
            
            Button {
                KBLog.auth.kbInfo("LoginView Apple tapped")
                guard let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene }).first,
                      let window = windowScene.keyWindow else { return }
                vm.signInApple(window: window)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Continua con Apple")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(primaryButtonForeground)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 52)
                .background(primaryButtonBackground, in: Capsule())
            }
            .buttonStyle(.plain)
            .opacity(vm.isBusy ? 0.6 : 1)
            .disabled(vm.isBusy)
        }
        .frame(height: 52)
    }
    
    private var facebookButton: some View {
        ProviderButton(
            label: "Continua con Facebook",
            icon: { FacebookIcon() },
            isLoading: vm.isBusy,
            background: primaryButtonBackground,
            foreground: primaryButtonForeground
        ) {
            KBLog.auth.kbInfo("LoginView Facebook tapped")
            guard let vc = UIApplication.shared.topMostViewController else { return }
            vm.signInFacebook(viewController: vc)
        }
    }
    
    private var emailButton: some View {
        Button {
            showEmailAuth = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 16))
                Text("Continua con email")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(primaryText)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 52)
            .background(
                Capsule()
                    .strokeBorder(primaryText.opacity(0.25), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(vm.isBusy)
        .opacity(vm.isBusy ? 0.6 : 1)
    }
    
    // MARK: - Divider
    
    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(primaryText.opacity(0.15))
                .frame(height: 1)
            
            Circle()
                .strokeBorder(primaryText.opacity(0.2), lineWidth: 1)
                .frame(width: 24, height: 24)
                .overlay(
                    Text("o")
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryText)
                )
            
            Rectangle()
                .fill(primaryText.opacity(0.15))
                .frame(height: 1)
        }
    }
    
    // MARK: - Footer
    
    private var legalFooter: some View {
        let privacyURL = URL(string: "https://vittorioscocca.github.io/KidBox/privacy/")!
        let termsURL   = URL(string: "https://vittorioscocca.github.io/KidBox/terms/")!
        
        var attributed = AttributedString("Continuando, accetti i Termini di Servizio e la Privacy Policy di KidBox.")
        
        if let termsRange = attributed.range(of: "Termini di Servizio") {
            attributed[termsRange].link = termsURL
            attributed[termsRange].underlineStyle = .single
        }
        
        if let privacyRange = attributed.range(of: "Privacy Policy") {
            attributed[privacyRange].link = privacyURL
            attributed[privacyRange].underlineStyle = .single
        }
        
        return Text(attributed)
            .font(.system(size: 12))
            .foregroundStyle(secondaryText)
            .multilineTextAlignment(.center)
    }
}

// MARK: - ProviderButton (Google / Facebook)

private struct ProviderButton<Icon: View>: View {
    let label: String
    let icon: () -> Icon
    let isLoading: Bool
    let background: Color
    let foreground: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon()
                    .frame(width: 22, height: 22)
                Text(isLoading ? "Accesso…" : label)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 52)
            .background(background, in: Capsule())
            .opacity(isLoading ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Google Icon

private struct GoogleIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            Circle()
                .fill(colorScheme == .dark ? Color.black : Color.white)
                .frame(width: 22, height: 22)
            Text("G")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
        }
    }
}

// MARK: - Facebook Icon

private struct FacebookIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            Circle()
                .fill(colorScheme == .dark ? Color.black : Color(red: 0.23, green: 0.35, blue: 0.60))
                .frame(width: 22, height: 22)
            Text("f")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(colorScheme == .dark ? Color(red: 0.23, green: 0.35, blue: 0.60) : .white)
        }
    }
}
