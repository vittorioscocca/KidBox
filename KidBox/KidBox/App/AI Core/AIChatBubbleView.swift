//
//  AIChatBubbleView.swift
//  KidBox
//
//  Created by vscocca on 06/03/26.
//

import SwiftUI

private enum AITextBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet([String], ordered: Bool)
    case code(String)

    var id: String {
        switch self {
        case .heading(let level, let text): return "h\(level)-\(text)"
        case .paragraph(let text): return "p-\(text)"
        case .bullet(let items, let ordered): return "l-\(ordered)-\(items.joined(separator: "|"))"
        case .code(let text): return "c-\(text)"
        }
    }
}

private struct AIClaudeMarkdownText: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let headingText):
                    Text(markdownAttributed(headingText))
                        .font(level == 2 ? .title3.weight(.semibold) : .headline.weight(.semibold))
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                        .padding(.top, 6)
                        .padding(.bottom, 10)

                case .paragraph(let paragraph):
                    Text(markdownAttributed(paragraph))
                        .font(.body)
                        .lineSpacing(5)
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)

                case .bullet(let items, let ordered):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text(ordered ? "\(index + 1)." : "•")
                                    .font(.body)
                                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                                    .frame(width: 18, alignment: .leading)
                                Text(markdownAttributed(item))
                                    .font(.body)
                                    .lineSpacing(5)
                                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.bottom, 8)

                case .code(let code):
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                }
            }
        }
        .textSelection(.enabled)
    }

    private var blocks: [AITextBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [AITextBlock] = []
        var i = 0

        func pushParagraph(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out.append(.paragraph(trimmed)) }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                i += 1
                var codeLines: [String] = []
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                out.append(.code(codeLines.joined(separator: "\n")))
                i += 1
                continue
            }

            if trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") {
                let level = trimmed.hasPrefix("### ") ? 3 : 2
                let text = String(trimmed.dropFirst(level + 1))
                out.append(.heading(level: level, text: text))
                i += 1
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("- ") || t.hasPrefix("* ") {
                        items.append(String(t.dropFirst(2)))
                        i += 1
                    } else {
                        break
                    }
                }
                out.append(.bullet(items, ordered: false))
                continue
            }

            if let _ = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let range = t.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                        items.append(String(t[range.upperBound...]))
                        i += 1
                    } else {
                        break
                    }
                }
                out.append(.bullet(items, ordered: true))
                continue
            }

            if trimmed.isEmpty {
                i += 1
                continue
            }

            var paragraphLines = [line]
            i += 1
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("## ") || t.hasPrefix("### ") || t.hasPrefix("```") ||
                    t.hasPrefix("- ") || t.hasPrefix("* ") || t.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
                    break
                }
                paragraphLines.append(lines[i])
                i += 1
            }
            pushParagraph(paragraphLines.joined(separator: "\n"))
        }
        return out
    }

    private func markdownAttributed(_ source: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: source,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            )
        } catch {
            return AttributedString(source)
        }
    }
}

struct AIChatBubbleView: View {
    let text: String
    let isUser: Bool
    let date: Date
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if isUser {
                    Text(text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        bubbleBackground,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 18,
                            bottomLeadingRadius: 18,
                            bottomTrailingRadius: 6,
                            topTrailingRadius: 18
                        )
                    )
                    .shadow(
                        color: KBTheme.shadow(colorScheme),
                        radius: 3,
                        x: 0,
                        y: 1
                    )
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .trailing)
                } else {
                    AIClaudeMarkdownText(text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
                
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, isUser ? 4 : 0)
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
    
    private var bubbleBackground: Color {
        isUser ? KBTheme.bubbleTint : KBTheme.cardBackground(colorScheme)
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

struct AIChatTypingIndicator: View {
    @State private var isAnimating = false
    private let assistantTextInset: CGFloat = 12
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(KBTheme.bubbleTint)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isAnimating ? 1.0 : 0.72)
                        .opacity(isAnimating ? 1.0 : 0.35)
                        .animation(
                            .easeInOut(duration: 0.7)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.22),
                            value: isAnimating
                        )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)

            Spacer()
        }
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
        .padding(.leading, assistantTextInset)
    }
}
