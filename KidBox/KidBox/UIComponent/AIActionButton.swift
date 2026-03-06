//
//  AIActionButton.swift
//  KidBox
//
//  Created by vscocca on 06/03/26.
//

import SwiftUI

struct AskAIControl: View {
    
    enum Style {
        case circle
    }
    
    let style: Style
    let accessibilityLabel: String
    let action: () -> Void
    
    @State private var pulse = false
    
    init(
        style: Style = .circle,
        accessibilityLabel: String = "Chiedi all'AI",
        action: @escaping () -> Void
    ) {
        self.style = style
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch style {
        case .circle:
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58, height: 58)
                    .scaleEffect(pulse ? 1.02 : 0.98)
                    .shadow(color: .blue.opacity(0.30), radius: 14, x: 0, y: 6)
                
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    .frame(width: 58, height: 58)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
