//
//  LaunchScreenView.swift
//  KidBox
//
//  Animated launch screen that mirrors the app icon:
//  orange gradient background + family symbol + "KidBox" wordmark.
//
//  

import SwiftUI

public struct LaunchScreenView: View {
    
    // MARK: - Animation state
    @State private var gradientAngle: Double       = 0
    @State private var iconScale: Double           = 0.55
    @State private var iconOpacity: Double         = 0
    @State private var iconBounce: Double          = 0
    @State private var ringScale: Double           = 0.6
    @State private var ringOpacity: Double         = 0
    @State private var wordmarkOpacity: Double     = 0
    @State private var wordmarkOffset: Double      = 18
    @State private var particle1: Bool             = false
    @State private var particle2: Bool             = false
    @State private var particle3: Bool             = false
    
    // MARK: - Colors — match the icon exactly
    private let topColor    = Color(red: 1.00, green: 0.75, blue: 0.25)   // warm yellow-orange
    private let bottomColor = Color(red: 0.95, green: 0.38, blue: 0.10)   // deep orange
    
    public var body: some View {
        ZStack {
            // ── Background gradient ──────────────────────────────────────
            LinearGradient(
                colors: [topColor, bottomColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // ── Soft radial glow behind icon ─────────────────────────────
            RadialGradient(
                colors: [Color.white.opacity(0.18), Color.clear],
                center: .center,
                startRadius: 60,
                endRadius: 220
            )
            .ignoresSafeArea()
            .scaleEffect(ringScale)
            .opacity(ringOpacity)
            
            // ── Decorative rings ─────────────────────────────────────────
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.5)
                .frame(width: 260, height: 260)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
            
            Circle()
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                .frame(width: 340, height: 340)
                .scaleEffect(ringScale)
                .opacity(ringOpacity * 0.7)
            
            // ── Floating particles ───────────────────────────────────────
            ParticleView(animate: particle1, offsetX: -90, offsetY: -130, size: 7, delay: 0)
            ParticleView(animate: particle2, offsetX:  80, offsetY: -110, size: 5, delay: 0.1)
            ParticleView(animate: particle3, offsetX: 110, offsetY:  -60, size: 6, delay: 0.2)
            ParticleView(animate: particle1, offsetX: -70, offsetY:  100, size: 4, delay: 0.15)
            ParticleView(animate: particle2, offsetX:  50, offsetY:  120, size: 8, delay: 0.05)
            
            // ── Main icon card ───────────────────────────────────────────
            VStack(spacing: 24) {
                
                ZStack {
                    // Card shadow
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                        .frame(width: 128, height: 128)
                        .blur(radius: 20)
                        .offset(y: 14)
                    
                    // Icona reale dell'app
                    Image(uiImage: UIImage(named: "Icon") ?? UIImage())
                        .resizable()
                        .scaledToFill()
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                }
                .scaleEffect(iconScale + iconBounce)
                .opacity(iconOpacity)
                
                // ── Wordmark ─────────────────────────────────────────────
                VStack(spacing: 4) {
                    Text("KidBox")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    
                    Text("La tua famiglia, in un'unica app.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.80))
                }
                .opacity(wordmarkOpacity)
                .offset(y: wordmarkOffset)
            }
        }
        .onAppear { runAnimation() }
    }
    
    // MARK: - Animation sequence
    
    private func runAnimation() {
        // 1. Rings fade in
        withAnimation(.easeOut(duration: 0.7).delay(0.1)) {
            ringScale   = 1.0
            ringOpacity = 1.0
        }
        
        // 2. Icon bounces in
        withAnimation(.spring(response: 0.55, dampingFraction: 0.62).delay(0.25)) {
            iconScale   = 1.0
            iconOpacity = 1.0
        }
        
        // 3. Subtle secondary bounce
        withAnimation(.easeInOut(duration: 0.2).delay(0.85)) {
            iconBounce = 0.04
        }
        withAnimation(.easeInOut(duration: 0.2).delay(1.05)) {
            iconBounce = 0
        }
        
        // 4. Wordmark slides up
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.55)) {
            wordmarkOpacity = 1.0
            wordmarkOffset  = 0
        }
        
        // 5. Particles
        withAnimation(.easeInOut(duration: 1.2).delay(0.4).repeatForever(autoreverses: true)) {
            particle1 = true
        }
        withAnimation(.easeInOut(duration: 1.5).delay(0.6).repeatForever(autoreverses: true)) {
            particle2 = true
        }
        withAnimation(.easeInOut(duration: 1.1).delay(0.2).repeatForever(autoreverses: true)) {
            particle3 = true
        }
    }
}

// MARK: - Particle

private struct ParticleView: View {
    let animate: Bool
    let offsetX: CGFloat
    let offsetY: CGFloat
    let size: CGFloat
    let delay: Double
    
    var body: some View {
        Circle()
            .fill(Color.white.opacity(animate ? 0.55 : 0.20))
            .frame(width: size, height: size)
            .offset(x: offsetX, y: offsetY + (animate ? -10 : 0))
            .scaleEffect(animate ? 1.3 : 0.8)
    }
}

// MARK: - Preview

#Preview {
    LaunchScreenView()
}
