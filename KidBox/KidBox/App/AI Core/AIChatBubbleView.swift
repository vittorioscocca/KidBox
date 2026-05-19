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
    var streamReveal: Bool = false
    var onStreamingTick: (() -> Void)? = nil
    var onStreamingComplete: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var revealedCount = 0
    @State private var revealTask: Task<Void, Never>?

    private var displayText: String {
        guard streamReveal, !isUser else { return text }
        guard revealedCount > 0 else { return "" }
        return String(text.prefix(revealedCount))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Group {
                    if isUser {
                        Text(displayText)
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
                        AIClaudeMarkdownText(text: displayText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                        .animation(nil, value: revealedCount)
                    }
                }
                .contextMenu {
                    if canCopyMessage {
                        Button { copyMessageToPasteboard() } label: {
                            Label("Copia messaggio", systemImage: "doc.on.doc")
                        }
                    }
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
        .onAppear { syncRevealAnimation() }
        .onChange(of: streamReveal) { _, _ in syncRevealAnimation() }
        .onChange(of: text) { _, _ in
            if !streamReveal { revealedCount = text.count }
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
        }
    }

    private func syncRevealAnimation() {
        revealTask?.cancel()
        if streamReveal, !isUser, !text.isEmpty {
            revealedCount = 0
            revealTask = Task { @MainActor in
                await runTypewriterReveal()
            }
        } else {
            revealedCount = text.count
        }
    }

    @MainActor
    private func runTypewriterReveal() async {
        let total = text.count
        let baseIntervalNs: UInt64 = total > 1_200 ? 6_000_000 : (total > 400 ? 10_000_000 : 14_000_000)
        var index = 0
        while index < total {
            if Task.isCancelled { return }
            let step = revealStep(from: index)
            index = min(index + step, total)
            revealedCount = index
            onStreamingTick?()
            if index < total {
                try? await Task.sleep(nanoseconds: baseIntervalNs * UInt64(step))
            }
        }
        onStreamingComplete?()
    }

    private func revealStep(from index: Int) -> Int {
        guard index < text.count else { return 1 }
        let i = text.index(text.startIndex, offsetBy: index)
        let ch = text[i]
        if ch == "\n" { return 1 }
        if ch == " " { return 2 }
        return min(4, text.count - index)
    }

    private var bubbleBackground: Color {
        isUser ? KBTheme.bubbleTint : KBTheme.cardBackground(colorScheme)
    }

    private var canCopyMessage: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func copyMessageToPasteboard() {
        guard canCopyMessage else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIPasteboard.general.string = AIChatMarkdownPlainText.forClipboard(text)
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
