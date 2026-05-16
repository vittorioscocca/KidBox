//
//  KBMemoryFact.swift
//  KidBox
//

import Foundation
import SwiftData

enum MemoryFactCategory: String, Codable, CaseIterable {
    case salute
    case abitudini
    case preferenze
    case scuola
    case relazioni
    case casa
    case wallet
    case animali
    case altro
}

@Model
final class KBMemoryFact {
    @Attribute(.unique) var id: String
    var familyId: String
    var content: String
    var categoryRaw: String
    var createdAt: Date
    var updatedAt: Date
    var sourceConversationId: String?

    var category: MemoryFactCategory {
        get { MemoryFactCategory(rawValue: categoryRaw) ?? .altro }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        content: String,
        category: MemoryFactCategory,
        sourceConversationId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.familyId = familyId
        self.content = content
        self.categoryRaw = category.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceConversationId = sourceConversationId
    }
}
