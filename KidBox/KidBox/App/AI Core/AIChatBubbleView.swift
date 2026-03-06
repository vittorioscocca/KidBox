//
//  AIChatBubbleView.swift
//  KidBox
//
//  Created by vscocca on 06/03/26.
//

import SwiftUI

private struct AIChatMarkdownText: View {
    let text: String
    let isUser: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Text(displayText)
            .textSelection(.enabled)
            .font(.body)
            .foregroundStyle(isUser ? .white : KBTheme.primaryText(colorScheme))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    private var displayText: String {
        normalizeMarkdownLikeText(text)
    }
    
    private func normalizeMarkdownLikeText(_ input: String) -> String {
        var output = input
        
        // Normalizza ritorni a capo
        output = output.replacingOccurrences(of: "\r\n", with: "\n")
        output = output.replacingOccurrences(of: "\r", with: "\n")
        
        // Titoli markdown -> testo normale con spazio sopra
        output = output.replacingOccurrences(of: "## ", with: "\n")
        output = output.replacingOccurrences(of: "# ", with: "\n")
        
        // Grassetto markdown -> rimuove i marker
        output = output.replacingOccurrences(of: "**", with: "")
        output = output.replacingOccurrences(of: "__", with: "")
        
        // Evita testi attaccati dopo i :
        output = output.replacingOccurrences(of: ":", with: ":\n")
        
        // Mantieni leggibili gli elenchi
        output = output.replacingOccurrences(of: "\n- ", with: "\n• ")
        output = output.replacingOccurrences(of: "- ", with: "• ")
        
        // Assicura spazio prima degli elenchi numerati se attaccati
        output = output.replacingOccurrences(
            of: #"(?<!\n)(\d+\.) "#,
            with: "\n$1 ",
            options: .regularExpression
        )
        
        // Riduce i buchi enormi ma lascia respirare il testo
        output = output.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AIChatBubbleView: View {
    let text: String
    let isUser: Bool
    let date: Date
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isUser {
                ZStack {
                    Circle()
                        .fill(KBTheme.bubbleTint.opacity(0.12))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KBTheme.bubbleTint)
                }
            } else {
                Spacer(minLength: 36)
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                AIChatMarkdownText(
                    text: text,
                    isUser: isUser
                )
                .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    bubbleBackground,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: isUser ? 18 : 6,
                        bottomLeadingRadius: 18,
                        bottomTrailingRadius: isUser ? 6 : 18,
                        topTrailingRadius: 18
                    )
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: isUser ? 18 : 6,
                        bottomLeadingRadius: 18,
                        bottomTrailingRadius: isUser ? 6 : 18,
                        topTrailingRadius: 18
                    )
                    .stroke(
                        isUser ? Color.clear : KBTheme.separator(colorScheme),
                        lineWidth: isUser ? 0 : 1
                    )
                )
                .shadow(
                    color: KBTheme.shadow(colorScheme),
                    radius: 3,
                    x: 0,
                    y: 1
                )
                
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            
            if isUser {
                Circle()
                    .fill(KBTheme.bubbleTint.opacity(0.14))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(KBTheme.bubbleTint)
                    }
            } else {
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
    
    private var bubbleBackground: Color {
        isUser ? KBTheme.bubbleTint : KBTheme.cardBackground(colorScheme)
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

struct AIChatTypingIndicator: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase = 0
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle()
                    .fill(KBTheme.bubbleTint.opacity(0.12))
                    .frame(width: 28, height: 28)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KBTheme.bubbleTint)
            }
            
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(KBTheme.bubbleTint.opacity(phase == index ? 1 : 0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                KBTheme.cardBackground(colorScheme),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 6,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 6,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18
                )
                .stroke(KBTheme.separator(colorScheme), lineWidth: 1)
            )
            
            Spacer()
        }
        .task {
            while true {
                try? await Task.sleep(for: .milliseconds(280))
                phase = (phase + 1) % 3
            }
        }
    }
}
