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
    
    // Sfondo crema esattamente come nello screenshot di riferimento
    private let cream = Color(red: 0.961, green: 0.957, blue: 0.945)
    
    var body: some View {
        ZStack {
            cream.ignoresSafeArea()
            
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
        }
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthView(vm: vm)
        }
        .onAppear { KBLog.navigation.kbDebug("LoginView appeared") }
        .onDisappear { KBLog.navigation.kbDebug("LoginView disappeared") }
    }
    
    // MARK: - Logo
    
    private var logoSection: some View {
        VStack(spacing: 16) {
            // Icona app (usa il tuo asset, fallback a simbolo SF)
            Image("AppIcon-Login")   // metti qui il nome del tuo asset, oppure usa sotto
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            // Se non hai l'asset, commenta le 5 righe sopra e decommenta questa:
            // Image(systemName: "figure.2.and.child.holdinghands")
            //     .font(.system(size: 44))
            //     .foregroundStyle(.primary)
            
            Text("KidBox")
                .font(.system(size: 36, weight: .semibold, design: .serif))
                .foregroundStyle(.primary)
            
            Text("La tua famiglia,\nin un'unica app.")
                .font(.system(size: 26, weight: .medium, design: .serif))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }
    
    // MARK: - Buttons
    
    private var googleButton: some View {
        ProviderButton(
            label: "Continua con Google",
            icon: { GoogleIcon() },
            isLoading: vm.isBusy
        ) {
            KBLog.auth.kbInfo("LoginView Google tapped")
            guard let vc = UIApplication.shared.topMostViewController else { return }
            vm.signInGoogle(viewController: vc)
        }
    }
    
    private var appleButton: some View {
        // Usiamo l'overlay trick per mantenere il look nativo Apple
        // ma wrappato nello stesso stile nero degli altri bottoni
        ZStack {
            SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in }
                .frame(height: 52)
                .clipShape(Capsule())
            
            // Overlay trasparente che intercetta il tap e usa il nostro vm
            Button {
                KBLog.auth.kbInfo("LoginView Apple tapped")
                guard let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene }).first,
                      let window = windowScene.keyWindow else { return }
                vm.signInApple(window: window)
            } label: {
                // Bottone con stesso stile degli altri per coerenza visiva
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Continua con Apple")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 52)
                .background(Color.black, in: Capsule())
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
            isLoading: vm.isBusy
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
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 52)
            .background(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Divisore
    
    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(height: 1)
            
            Circle()
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                .frame(width: 24, height: 24)
                .overlay(
                    Text("o")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                )
            
            Rectangle()
                .fill(Color.primary.opacity(0.15))
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
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

// MARK: - ProviderButton (Google / Facebook)

private struct ProviderButton<Icon: View>: View {
    let label: String
    let icon: () -> Icon
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon()
                    .frame(width: 22, height: 22)
                Text(isLoading ? "Accesso…" : label)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 52)
            .background(Color.black, in: Capsule())
            .opacity(isLoading ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Google Icon

private struct GoogleIcon: View {
    var body: some View {
        // Cerchio colorato con la G di Google — vettoriale puro, nessuna dipendenza asset
        ZStack {
            Circle().fill(.white).frame(width: 22, height: 22)
            Text("G")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
        }
    }
}

// MARK: - Facebook Icon

private struct FacebookIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.23, green: 0.35, blue: 0.60))
                .frame(width: 22, height: 22)
            Text("f")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
