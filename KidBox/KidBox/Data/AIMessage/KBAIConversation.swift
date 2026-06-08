//
//  KBAIConversation.swift
//  KidBox
//

import Foundation
import SwiftData

/// AI provider used for a conversation.
enum AIProvider: String, Codable, CaseIterable {
    case claude = "claude"
    case openai = "openai"
    
    var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "ChatGPT (OpenAI)"
        }
    }
    
    var iconName: String {
        switch self {
        case .claude: return "sparkles"
        case .openai: return "brain"
        }
    }
}

/// A full AI conversation scoped to a specific medical visit.
@Model
final class KBAIConversation {
    @Attribute(.unique) var id: String
    
    var familyId: String
    var childId: String
    var visitId: String
    var providerRaw: String
    var createdAt: Date

    /// Owner of the conversation (Firebase uid). AI chats are private per-user,
    /// sincronizzate solo tra i dispositivi dello stesso utente.
    var ownerUserId: String = ""

    /// Last modification timestamp — used for cross-device Last-Writer-Wins sync.
    var updatedAt: Date = Date()

    // Summary / compression
    var summary: String?
    var summaryUpdatedAt: Date?
    var summarizedMessageCount: Int
    
    @Relationship(deleteRule: .cascade, inverse: \KBAIMessage.conversation)
    var messages: [KBAIMessage] = []
    
    var provider: AIProvider {
        get { AIProvider(rawValue: providerRaw) ?? .claude }
        set { providerRaw = newValue.rawValue }
    }
    
    /// Messages sorted chronologically (safe to use in UI).
    var sortedMessages: [KBAIMessage] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }
    
    var hasSummary: Bool {
        guard let summary else { return false }
        return !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        visitId: String,
        provider: AIProvider,
        ownerUserId: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        summary: String? = nil,
        summaryUpdatedAt: Date? = nil,
        summarizedMessageCount: Int = 0
    ) {
        self.id = id
        self.familyId = familyId
        self.childId = childId
        self.visitId = visitId
        self.providerRaw = provider.rawValue
        self.ownerUserId = ownerUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.summary = summary
        self.summaryUpdatedAt = summaryUpdatedAt
        self.summarizedMessageCount = summarizedMessageCount
    }

    /// Deterministic Firestore document id derived from the conversation scope
    /// (provider + visit/scope id), so every device dello stesso utente scrive
    /// sullo stesso documento e le conversazioni convergono.
    var remoteDocId: String {
        let raw = "\(providerRaw)__\(visitId)"
        // Firestore doc id non può contenere "/" e ha un limite pratico di
        // lunghezza: sostituiamo i caratteri problematici.
        return raw
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")
    }
}
