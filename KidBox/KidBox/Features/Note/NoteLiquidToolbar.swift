//
//  NoteLiquidToolbar.swift
//  KidBox
//

import SwiftUI
import UIKit

struct NoteLiquidToolbar: View {
    let onCommand: (RichTextCommand) -> Void
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            
            // ── Pannello avanzato (sopra la base row) ─────────────────────
            if isExpanded {
                expandedPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // ── Base row ──────────────────────────────────────────────────
            baseRow
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: -2)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isExpanded)
    }
    
    // MARK: - Base row
    
    private var baseRow: some View {
        HStack(spacing: 0) {
            
            // Aa — apre/chiude il pannello; diventa blu quando aperto
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                Text("Aa")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isExpanded ? .accentColor : .primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            
            baseDivider()
            
            // Bold
            ToolbarIconBtn(title: "B", titleFont: .system(size: 17, weight: .bold)) {
                send(.bold)
            }
            // Italic
            ToolbarIconBtn(title: "I", titleFont: .system(size: 17).italic()) {
                send(.italic)
            }
            // Underline
            ToolbarIconBtn(sf: "underline") { send(.underline) }
            // Strikethrough
            ToolbarIconBtn(sf: "strikethrough") { send(.strikethrough) }
            
            baseDivider()
            
            // Checklist (○)
            ToolbarIconBtn(sf: "circle") { send(.checklist) }
            
            Spacer(minLength: 0)
            
            // Dismiss keyboard — chiude anche il pannello
            Button {
                withAnimation { isExpanded = false }
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil)
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Expanded panel
    
    private var expandedPanel: some View {
        VStack(spacing: 0) {
            Divider()
            
            // Riga 1: stili paragrafo
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    StyleChip("Corpo",   font: .system(size: 14)) { send(.body) }
                    StyleChip("Titolo",  font: .system(size: 18, weight: .bold)) { send(.h1) }
                    StyleChip("H2",      font: .system(size: 15, weight: .semibold)) { send(.h2) }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 50)
            
            Divider()
            
            // Riga 2: inline + blockquote
            HStack(spacing: 6) {
                FmtBtn(title: "B",  font: .system(size: 16, weight: .bold))  { send(.bold) }
                FmtBtn(title: "I",  font: .system(size: 16).italic())        { send(.italic) }
                FmtBtn(sf: "underline")                                       { send(.underline) }
                FmtBtn(sf: "strikethrough")                                   { send(.strikethrough) }
                Spacer(minLength: 0)
                FmtBtn(sf: "text.quote")                                      { send(.quote) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Riga 3: liste + indent
            HStack(spacing: 6) {
                FmtBtn(sf: "list.bullet")    { send(.bullet) }
                FmtBtn(sf: "list.number")    { send(.number) }
                FmtBtn(sf: "circle")         { send(.checklist) }
                Spacer(minLength: 0)
                FmtBtn(sf: "decrease.indent") { send(.indentLess) }
                FmtBtn(sf: "increase.indent") { send(.indentMore) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Helpers
    
    private func send(_ cmd: RichTextCommand) {
        onCommand(cmd)
        // Chiude il pannello dopo ogni comando (come Apple Notes)
        withAnimation { isExpanded = false }
    }
    
    private func baseDivider() -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 0.5, height: 22)
            .padding(.horizontal, 4)
    }
}

// MARK: - Sub-components

private struct ToolbarIconBtn: View {
    var title: String? = nil
    var titleFont: Font = .body
    var sf: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Group {
                if let t = title {
                    Text(t).font(titleFont)
                } else if let s = sf {
                    Image(systemName: s).font(.system(size: 16))
                }
            }
            .foregroundColor(.primary)
            .frame(width: 40, height: 44)
        }
        .buttonStyle(.plain)
    }
}

private struct FmtBtn: View {
    var title: String? = nil
    var font: Font = .body
    var sf: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Group {
                if let t = title {
                    Text(t).font(font)
                } else if let s = sf {
                    Image(systemName: s).font(.system(size: 15))
                }
            }
            .foregroundColor(.primary)
            .frame(width: 44, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct StyleChip: View {
    let label: String
    let font: Font
    let action: () -> Void
    init(_ label: String, font: Font, action: @escaping () -> Void) {
        self.label = label; self.font = font; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemBackground))
                )
                .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }
}
