//
//  NoteFormattingToolbar.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import SwiftUI
import UIKit

// MARK: - Text Styles

enum NoteTextStyle: String, CaseIterable {
    case body       = "Corpo"
    case title      = "Titolo"
    case heading    = "Intestazione"
    case subheading = "Sottoint."
    case mono       = "Mono"
}

// MARK: - Actions

enum NoteFormattingAction {
    case bold, italic, underline, strikethrough
    case setStyle(NoteTextStyle)
    case bulletList, dashedList, numberedList, checklist
    case indentMore, indentLess
    case blockquote
    case insertTable
}

// MARK: - Markdown Inserter

struct NoteMarkdownInserter {
    static func apply(action: NoteFormattingAction, to text: String) -> String {
        switch action {
        case .bold:          return wrapLines(text, open: "**", close: "**")
        case .italic:        return wrapLines(text, open: "_", close: "_")
        case .underline:     return wrapLines(text, open: "<u>", close: "</u>")
        case .strikethrough: return wrapLines(text, open: "~~", close: "~~")
        case .setStyle(let s): return applyStyle(s, to: text)
        case .bulletList:    return prefixLines(text, prefix: "- ")
        case .dashedList:    return prefixLines(text, prefix: "– ")
        case .numberedList:  return numberLines(text)
        case .checklist:     return prefixLines(text, prefix: "- [ ] ")
        case .indentMore:    return prefixLines(text, prefix: "    ")
        case .indentLess:    return removePrefixLines(text, prefix: "    ")
        case .blockquote:    return prefixLines(text, prefix: "> ")
        case .insertTable:
            // questa action la gestiamo a livello toolbar (inserimento al cursore)
            return text
        }
    }
    
    private static func wrapLines(_ text: String, open: String, close: String) -> String {
        text.components(separatedBy: "\n").map { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            if line.hasPrefix(open) && line.hasSuffix(close) && line.count > open.count + close.count {
                return String(line.dropFirst(open.count).dropLast(close.count))
            }
            return "\(open)\(line)\(close)"
        }.joined(separator: "\n")
    }
    
    private static func prefixLines(_ text: String, prefix: String) -> String {
        text.components(separatedBy: "\n").map { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            if line.hasPrefix(prefix) { return String(line.dropFirst(prefix.count)) }
            return "\(prefix)\(line)"
        }.joined(separator: "\n")
    }
    
    private static func removePrefixLines(_ text: String, prefix: String) -> String {
        text.components(separatedBy: "\n").map { line in
            line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line
        }.joined(separator: "\n")
    }
    
    private static func numberLines(_ text: String) -> String {
        var idx = 1
        return text.components(separatedBy: "\n").map { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            defer { idx += 1 }
            return "\(idx). \(line)"
        }.joined(separator: "\n")
    }
    
    private static func applyStyle(_ style: NoteTextStyle, to text: String) -> String {
        let prefix: String
        switch style {
        case .title:      prefix = "# "
        case .heading:    prefix = "## "
        case .subheading: prefix = "### "
        case .mono:       prefix = ""
        case .body:       prefix = ""
        }
        return text.components(separatedBy: "\n").map { line in
            var s = line
            for h in ["### ", "## ", "# "] {
                if s.hasPrefix(h) { s = String(s.dropFirst(h.count)); break }
            }
            if s.hasPrefix("`") && s.hasSuffix("`") && s.count > 2 {
                s = String(s.dropFirst().dropLast())
            }
            guard !s.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            switch style {
            case .mono: return "`\(s)`"
            case .body: return s
            default:    return "\(prefix)\(s)"
            }
        }.joined(separator: "\n")
    }
}

// MARK: - Toolbar View

struct NoteFormattingToolbar: View {
    @Binding var fullText: String
    @Binding var selectedRange: NSRange
    @Binding var isExpanded: Bool
    
    @State private var selectedStyle: NoteTextStyle = .body
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            baseBar
                .frame(height: 44)
                .background(.ultraThinMaterial)
            if isExpanded {
                expandedSheet
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }
    
    // MARK: Base bar
    private var baseBar: some View {
        HStack(spacing: 0) {
            TBButton(isActive: isExpanded) {
                Text("Aa").font(.system(size: 15, weight: .medium))
            } action: { withAnimation { isExpanded.toggle() } }
            
            Divider().frame(height: 22)
            
            TBButton { Image(systemName: "checklist") }
            action: { applyToSelectionOrLine(.checklist) }
            
            Divider().frame(height: 22)
            
            TBButton { Image(systemName: "tablecells") }
            action: { insertTableAtSelection() }
            
            Spacer()
            
            TBButton {
                Image(systemName: "keyboard.chevron.compact.down")
            } action: {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
                withAnimation { isExpanded = false }
            }
        }
        .padding(.horizontal, 8)
    }
    
    // MARK: Expanded sheet
    private var expandedSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Style chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(NoteTextStyle.allCases, id: \.self) { style in
                        StyleChip(style: style, isSelected: selectedStyle == style) {
                            selectedStyle = style
                            applyToSelectionOrLine(.setStyle(style))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            Divider().padding(.horizontal, 16)
            
            // Inline formatting
            HStack(spacing: 8) {
                FmtBtn { Text("B").font(.system(size: 17, weight: .bold)) }
                action: { applyToSelectionOrLine(.bold) }
                
                FmtBtn { Text("I").font(.system(size: 17, weight: .regular).italic()) }
                action: { applyToSelectionOrLine(.italic) }
                
                FmtBtn { Text("U").font(.system(size: 17)).underline() }
                action: { applyToSelectionOrLine(.underline) }
                
                FmtBtn { Text("S").font(.system(size: 17)).strikethrough() }
                action: { applyToSelectionOrLine(.strikethrough) }
                
                Spacer()
                
                FmtBtn { Image(systemName: "text.quote") }
                action: { applyToSelectionOrLine(.blockquote) }
            }
            .padding(.horizontal, 16)
            
            // Lists + indent
            HStack(spacing: 8) {
                FmtBtn { Image(systemName: "list.bullet") }   action: { applyToSelectionOrLine(.bulletList) }
                FmtBtn { Image(systemName: "list.dash") }     action: { applyToSelectionOrLine(.dashedList) }
                FmtBtn { Image(systemName: "list.number") }   action: { applyToSelectionOrLine(.numberedList) }
                FmtBtn { Image(systemName: "checklist") }     action: { applyToSelectionOrLine(.checklist) }
                Spacer()
                FmtBtn { Image(systemName: "decrease.indent") } action: { applyToSelectionOrLine(.indentLess) }
                FmtBtn { Image(systemName: "increase.indent") } action: { applyToSelectionOrLine(.indentMore) }
            }
            .padding(.horizontal, 16)
            
            Spacer(minLength: 6)
        }
        .padding(.top, 14)
        .frame(height: 210)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Core helpers
    
    private func clamp(_ range: NSRange, length: Int) -> NSRange {
        let loc = max(0, min(range.location, length))
        let len = max(0, min(range.length, length - loc))
        return NSRange(location: loc, length: len)
    }
    
    /// Applica al testo selezionato; se non c’è selezione, applica alla riga dove sta il cursore.
    private func applyToSelectionOrLine(_ action: NoteFormattingAction) {
        let ns = fullText as NSString
        let fullLen = ns.length
        
        let sel = clamp(selectedRange, length: fullLen)
        let targetRange: NSRange = {
            if sel.length > 0 {
                return sel
            } else {
                var lr = ns.lineRange(for: NSRange(location: sel.location, length: 0))
                // togli newline finale dalla lineRange (se presente)
                if lr.length > 0 {
                    let endIndex = lr.location + lr.length - 1
                    if endIndex < fullLen {
                        let lastChar = ns.substring(with: NSRange(location: endIndex, length: 1))
                        if lastChar == "\n" {
                            lr.length -= 1
                        }
                    }
                }
                return lr
            }
        }()
        
        guard targetRange.location <= fullLen,
              targetRange.location + targetRange.length <= fullLen
        else { return }
        
        let oldSub = ns.substring(with: targetRange)
        let newSub = NoteMarkdownInserter.apply(action: action, to: oldSub)
        if oldSub == newSub { return }
        
        let mutable = NSMutableString(string: fullText)
        mutable.replaceCharacters(in: targetRange, with: newSub)
        fullText = mutable as String
        
        // aggiorna selezione/cursore in modo sensato
        let delta = (newSub as NSString).length - (oldSub as NSString).length
        if sel.length > 0 {
            selectedRange = NSRange(location: targetRange.location, length: targetRange.length + delta)
        } else {
            selectedRange = NSRange(location: targetRange.location + (newSub as NSString).length, length: 0)
        }
    }
    
    /// Inserisce una tabella nel punto di inserimento (o sostituisce la selezione).
    private func insertTableAtSelection() {
        let table = """
        
        | Col 1 | Col 2 |
        |-------|-------|
        | Cella | Cella |
        
        """
        replaceSelection(with: table)
    }
    
    private func replaceSelection(with replacement: String) {
        let ns = fullText as NSString
        let fullLen = ns.length
        let sel = clamp(selectedRange, length: fullLen)
        
        let mutable = NSMutableString(string: fullText)
        mutable.replaceCharacters(in: sel, with: replacement)
        fullText = mutable as String
        
        let repLen = (replacement as NSString).length
        selectedRange = NSRange(location: sel.location + repLen, length: 0)
    }
}

// MARK: - Sub-components

private struct TBButton<Label: View>: View {
    var isActive: Bool = false
    @ViewBuilder let label: () -> Label
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            label()
                .foregroundColor(isActive ? .accentColor : .primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}

private struct StyleChip: View {
    let style: NoteTextStyle
    let isSelected: Bool
    let action: () -> Void
    
    private var chipFont: Font {
        switch style {
        case .title:      return .system(size: 19, weight: .bold)
        case .heading:    return .system(size: 16, weight: .semibold)
        case .subheading: return .system(size: 14, weight: .semibold)
        case .mono:       return .system(size: 13, weight: .regular, design: .monospaced)
        case .body:       return .system(size: 14, weight: .regular)
        }
    }
    
    var body: some View {
        Button(action: action) {
            Text(style.rawValue)
                .font(chipFont)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
                .foregroundColor(isSelected ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

private struct FmtBtn<Label: View>: View {
    @ViewBuilder let label: () -> Label
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            label()
                .foregroundColor(.primary)
                .frame(width: 46, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }
}
