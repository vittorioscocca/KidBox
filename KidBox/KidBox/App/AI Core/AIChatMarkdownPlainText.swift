//
//  AIChatMarkdownPlainText.swift
//  KidBox
//

import Foundation

enum AIChatMarkdownPlainText {

    /// Testo da copiare negli appunti: struttura leggibile senza simboli markdown (`##`, `**`, ecc.).
    static func forClipboard(_ raw: String) -> String {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let blocks = parseBlocks(trimmed)
        guard !blocks.isEmpty else { return stripInlineMarkdown(trimmed) }

        let parts = blocks.map { plainText(for: $0) }.filter { !$0.isEmpty }
        return parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Blocks

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet([String], ordered: Bool)
        case code(String)
    }

    private static func plainText(for block: Block) -> String {
        switch block {
        case .heading(_, let text):
            return stripInlineMarkdown(text)
        case .paragraph(let text):
            return stripInlineMarkdown(text)
        case .bullet(let items, let ordered):
            return items.enumerated().map { index, item in
                let prefix = ordered ? "\(index + 1). " : "• "
                return prefix + stripInlineMarkdown(item)
            }.joined(separator: "\n")
        case .code(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func parseBlocks(_ text: String) -> [Block] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [Block] = []
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
                let heading = String(trimmed.dropFirst(level + 1))
                out.append(.heading(level: level, text: heading))
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
                    } else { break }
                }
                out.append(.bullet(items, ordered: false))
                continue
            }

            if trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let range = t.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                        items.append(String(t[range.upperBound...]))
                        i += 1
                    } else { break }
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
                    t.hasPrefix("- ") || t.hasPrefix("* ") ||
                    t.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
                    break
                }
                paragraphLines.append(lines[i])
                i += 1
            }
            pushParagraph(paragraphLines.joined(separator: "\n"))
        }
        return out
    }

    // MARK: - Inline

    private static func stripInlineMarkdown(_ source: String) -> String {
        var result = source

        // [label](url) → label
        result = replaceRegex(#"\[([^\]]+)\]\([^)]*\)"#, in: result, with: "$1")
        // **bold** / __bold__
        result = replaceRegex(#"\*\*([^*]+)\*\*"#, in: result, with: "$1")
        result = replaceRegex(#"__([^_]+)__"#, in: result, with: "$1")
        // *italic* (single asterisk)
        result = replaceRegex(#"(?<!\*)\*([^*]+)\*(?!\*)"#, in: result, with: "$1")
        // `code`
        result = replaceRegex(#"`([^`]+)`"#, in: result, with: "$1")
        // Residual heading markers at line start
        result = result
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var l = String(line)
                if l.hasPrefix("### ") { l = String(l.dropFirst(4)) }
                else if l.hasPrefix("## ") { l = String(l.dropFirst(3)) }
                else if l.hasPrefix("# ") { l = String(l.dropFirst(2)) }
                return l
            }
            .joined(separator: "\n")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceRegex(
        _ pattern: String,
        in text: String,
        with template: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
