//
//  KBAIMessage.swift
//  KidBox
//
//  Created by vscocca on 05/03/26.
//

import Foundation
import SwiftData

/// Role of a message in an AI conversation.
enum AIMessageRole: String, Codable {
    case user
    case assistant
}

/// A single message inside a `KBAIConversation`.
///
/// - Note: Content is stored as plain text. Images/attachments are referenced
///   by URL and never stored inline in SwiftData.
@Model
final class KBAIMessage {
    @Attribute(.unique) var id: String
    var roleRaw: String
    var content: String
    var createdAt: Date
    var conversation: KBAIConversation?
    
    /// Convenience accessor for the typed role.
    var role: AIMessageRole {
        get { AIMessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }
    
    init(
        id: String = UUID().uuidString,
        role: AIMessageRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
    }
}
