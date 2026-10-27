//
//  ChatMessageActionsOverlay.swift
//  KidBox  ← solo main app target
//
//  Pressione lunga su un messaggio, come WhatsApp: lo sfondo si scurisce
//  lasciando nitida la bolla, sopra compare la barra delle reazioni e sotto il
//  menu. Il menu di sistema (.contextMenu) non permette una barra toccabile
//  sopra il messaggio, per questo è disegnato a mano.
//  «Azioni suggerite» si apre dentro il menu stesso: un tocco esegue l'azione.
//

import SwiftUI

// MARK: - Richiesta (la costruisce la bolla, la mostra ChatView)

struct ChatMenuAction: Identifiable {
    let id: String
    let title: String
    let icon: String
    var isDestructive = false
    let perform: () -> Void
}

struct ChatMessageActionsRequest: Identifiable {
    let id = UUID()
    let message: KBChatMessage
    /// Cornice della bolla in coordinate globali.
    let frame: CGRect
    let isOwn: Bool
    let currentUID: String
    let actions: [ChatMenuAction]
    let onReact: (String) -> Void
    let onMoreReactions: () -> Void
    let onSuggestedAction: ((KBSaveAction) -> Void)?
}

// MARK: - Overlay

struct ChatMessageActionsOverlay: View {
    let request: ChatMessageActionsRequest
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var suggestions: [KBSaveAction] = []
    @State private var showingSuggestions = false

    private let emojis = ["👍", "❤️", "😂", "😮", "😢", "🙏"]
    private let barHeight: CGFloat = 52
    private let rowHeight: CGFloat = 46
    private let menuWidth: CGFloat = 250
    private let gap: CGFloat = 8

    private var visibleSuggestions: [KBSaveAction] {
        suggestions.filter { $0.suggestedKind?.isEnabled ?? false }
    }

    private var menuRows: Int {
        showingSuggestions
        ? visibleSuggestions.count + 1
        : request.actions.count + (visibleSuggestions.isEmpty ? 0 : 1)
    }

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let bubble = request.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            let menuHeight = CGFloat(menuRows) * rowHeight + 12
            let fitsBelow = bubble.maxY + gap + menuHeight <= geo.size.height - 4
            let menuTop = fitsBelow
                ? bubble.maxY + gap
                : max(4 + barHeight + gap, bubble.minY - gap - menuHeight)
            let barTop = fitsBelow
                ? max(4, bubble.minY - gap - barHeight)
                : max(4, menuTop - gap - barHeight)

            ZStack(alignment: .topLeading) {
                dimLayer(bubble: bubble)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                reactionBar
                    .frame(height: barHeight)
                    .fixedSize(horizontal: true, vertical: false)
                    .alignmentGuide(.leading) { d in
                        -xFor(width: d.width, bubble: bubble, container: geo.size.width)
                    }
                    .offset(y: barTop)

                menu
                    .frame(width: menuWidth)
                    .alignmentGuide(.leading) { _ in
                        -xFor(width: menuWidth, bubble: bubble, container: geo.size.width)
                    }
                    .offset(y: menuTop)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.96)
        }
        .task {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { appeared = true }
            suggestions = await KBSuggestedActionsCache.actions(for: request.message)
        }
    }

    /// Allineata al bordo della bolla (a destra per i propri messaggi), dentro lo schermo.
    private func xFor(width: CGFloat, bubble: CGRect, container: CGFloat) -> CGFloat {
        let x = request.isOwn ? bubble.maxX - width : bubble.minX
        return min(max(8, x), container - width - 8)
    }

    // MARK: Sfondo con la bolla ritagliata

    private func dimLayer(bubble: CGRect) -> some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(0.18))
            .mask {
                Rectangle()
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 18)
                            .frame(width: bubble.width, height: bubble.height)
                            .offset(x: bubble.minX, y: bubble.minY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
    }

    // MARK: Reazioni

    private var reactionBar: some View {
        HStack(spacing: 4) {
            ForEach(emojis, id: \.self) { emoji in
                Button {
                    request.onReact(emoji)
                    close()
                } label: {
                    Text(emoji)
                        .font(.system(size: 28))
                        .frame(width: 42, height: 42)
                        .background(
                            isSelected(emoji) ? Color.accentColor.opacity(0.18) : .clear,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
            }
            Button {
                close()
                request.onMoreReactions()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
    }

    private func isSelected(_ emoji: String) -> Bool {
        request.message.reactions[emoji]?.contains(request.currentUID) ?? false
    }

    // MARK: Menu

    private var menu: some View {
        VStack(spacing: 0) {
            if showingSuggestions {
                row(title: "Azioni suggerite", icon: "chevron.left", tint: .secondary) {
                    withAnimation(.easeInOut(duration: 0.2)) { showingSuggestions = false }
                }
                .fontWeight(.semibold)
                ForEach(visibleSuggestions) { action in
                    if let kind = action.suggestedKind {
                        Divider()
                        row(title: kind.title, icon: kind.icon, tint: kind.color) {
                            kind.markUsed()
                            close()
                            request.onSuggestedAction?(action)
                        }
                    }
                }
            } else {
                ForEach(Array(mainRows.enumerated()), id: \.element.id) { index, action in
                    if index > 0 { Divider() }
                    row(title: action.title,
                        icon: action.icon,
                        tint: action.isDestructive ? .red : .primary,
                        textColor: action.isDestructive ? .red : .primary,
                        trailingChevron: action.id == "suggested",
                        perform: action.perform)
                }
            }
        }
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    /// Le voci della bolla con «Azioni suggerite» prima di Elimina, se ce ne sono.
    private var mainRows: [ChatMenuAction] {
        var rows = request.actions
        guard !visibleSuggestions.isEmpty, request.onSuggestedAction != nil else { return rows }
        let item = ChatMenuAction(id: "suggested", title: "Azioni suggerite", icon: "sparkles") {
            // Il banner compare qui: per i 30 giorni conta come mostrato.
            for kind in Set(visibleSuggestions.compactMap(\.suggestedKind)) { kind.noteShown() }
            withAnimation(.easeInOut(duration: 0.2)) { showingSuggestions = true }
        }
        let at = rows.firstIndex(where: \.isDestructive) ?? rows.count
        rows.insert(item, at: at)
        return rows
    }

    private func row(
        title: String,
        icon: String,
        tint: Color,
        textColor: Color = .primary,
        trailingChevron: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            HStack(spacing: 12) {
                Text(LocalizedStringKey(title))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if trailingChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 22)
            }
            .padding(.horizontal, 16)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.15)) { appeared = false }
        onDismiss()
    }
}
