//
//  ReactionPickerSheet.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//

import SwiftUI
import FirebaseAuth

/// Sheet compatto per scegliere una reazione emoji su un messaggio.
/// Si apre con long press su una bubble.
struct ReactionPickerSheet: View {
    
    let message: KBChatMessage
    let onSelect: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private let emojis = ["❤️", "😂", "👍", "😮", "😢", "🔥", "🎉", "👏"]
    
    var body: some View {
        VStack(spacing: 12) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
            
            // Emoji row
            HStack(spacing: 8) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        onSelect(emoji)
                        dismiss()
                    } label: {
                        Text(emoji)
                            .font(.system(size: 30))
                            .padding(8)
                            .background(
                                isSelected(emoji)
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isSelected(emoji) ? 1.15 : 1.0)
                    .animation(.spring(response: 0.2), value: isSelected(emoji))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
    
    private func isSelected(_ emoji: String) -> Bool {
        // Controlla se l'utente corrente ha già messo questa reazione
        guard let uid = message.reactions[emoji] else { return false }
        return uid.contains(getCurrentUID())
    }
    
    private func getCurrentUID() -> String {
        Auth.auth().currentUser?.uid ?? ""
    }
}
