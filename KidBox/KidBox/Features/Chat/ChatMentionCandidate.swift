//
//  ChatMentionCandidate.swift
//  KidBox
//
//  Lightweight in-memory rappresentazione dei membri famiglia attivi che possono
//  essere citati in chat con `@DisplayName`. È stata estratta dal model SwiftData
//  per disaccoppiare la `ChatInputBar`/`ChatViewModel` dalla query @Query e per
//  poter passare snapshot stabili al picker delle menzioni.
//

import Foundation

struct ChatMentionCandidate: Identifiable, Equatable, Hashable {
    /// `userId` del membro (UID Firebase Auth).
    let uid: String
    /// Nome visualizzato del membro (es. "Mario Rossi"). Usato come token
    /// `@<displayName>` nel testo del messaggio.
    let displayName: String
    /// URL avatar opzionale per il picker.
    let photoURL: String?

    var id: String { uid }
}
