//
//  ChatMessageActionsOverlay.swift
//  KidBox  ← solo main app target
//
//  Pressione lunga su un messaggio, come WhatsApp: lo sfondo si sfoca, al
//  centro compare una copia della bolla con sopra la barra delle reazioni e
//  sotto il menu. Un messaggio troppo lungo si taglia (con una sfumatura) così
//  il menu resta sempre intero. Il menu di sistema (.contextMenu) non permette
//  una barra toccabile sopra il messaggio, per questo è disegnato a mano.
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
    let repliedTo: KBChatMessage?
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
            let menuHeight = CGFloat(menuRows) * rowHeight + 12
            // Quel che resta per la bolla dopo barra, menu e margini.
            let bubbleMax = max(80, geo.size.height - barHeight - menuHeight - gap * 2 - 24)
            
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.18))
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                
                VStack(alignment: request.isOwn ? .trailing : .leading, spacing: gap) {
                    reactionBar
                        .frame(height: barHeight)
                        .padding(.leading, request.isOwn ? 0 : 54)
                        .padding(.trailing, request.isOwn ? 12 : 0)
                    
                    bubblePreview(maxHeight: bubbleMax)
                    
                    menu
                        .frame(width: menuWidth)
                        .padding(.leading, request.isOwn ? 0 : 54)
                        .padding(.trailing, request.isOwn ? 12 : 0)
                }
                .frame(maxWidth: .infinity, alignment: request.isOwn ? .trailing : .leading)
                .scaleEffect(appeared ? 1 : 0.92)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(appeared ? 1 : 0)
        }
        .task {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { appeared = true }
            suggestions = await KBSuggestedActionsCache.actions(for: request.message)
        }
    }
    
    // MARK: Copia della bolla
    
    /// La stessa bolla della chat, senza tocchi. Se è più alta dello spazio
    /// libero si vede l'inizio, sfumato in fondo.
    private func bubblePreview(maxHeight: CGFloat) -> some View {
        ChatHeightCap(maxHeight: maxHeight) {
            ChatBubble(
                message: request.message,
                isOwn: request.isOwn,
                currentUID: request.currentUID,
                onReactionTap: { _ in },
                onLongPress: {},
                onEdit: nil,
                onDelete: nil,
                onReply: {},
                repliedTo: request.repliedTo,
                onReplyContextTap: {},
                highlightedMessageId: nil,
                searchText: ""
            )
        }
        .clipped()
        .mask {
            GeometryReader { g in
                let cut = g.size.height >= maxHeight - 1
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: cut ? 0.85 : 1),
                        .init(color: cut ? .clear : .black, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .allowsHitTesting(false)
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

/// Altezza vera del contenuto, ma mai oltre `maxHeight` (il resto si taglia).
/// `frame(maxHeight:)` invece prendeva tutto lo spazio e staccava il menu
/// dai messaggi corti.
private struct ChatHeightCap: Layout {
    let maxHeight: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let sub = subviews.first else { return .zero }
        let s = sub.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: s.width, height: min(s.height, maxHeight))
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
