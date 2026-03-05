//
//  KBAIConversation.swift
//  KidBox
//
//  Created by vscocca on 05/03/26.
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
///
/// - One conversation per visit is the expected pattern, but multiple are allowed
///   (e.g. if the user switches provider or starts a new session).
/// - Messages are ordered by `createdAt`.
@Model
final class KBAIConversation {
    @Attribute(.unique) var id: String
    var familyId: String
    var childId: String
    var visitId: String
    var providerRaw: String
    var createdAt: Date
    
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
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        visitId: String,
        provider: AIProvider,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.familyId = familyId
        self.childId = childId
        self.visitId = visitId
        self.providerRaw = provider.rawValue
        self.createdAt = createdAt
    }
}
