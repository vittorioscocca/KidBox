//
//  KBHealthInsight.swift
//  KidBox
//

import Foundation
import SwiftData

/// Insight mensile generato dall'analisi pattern sulla storia sanitaria dei figli.
@Model
final class KBHealthInsight {
    @Attribute(.unique) var id: String
    var familyId: String
    var fullText: String
    var monthKey: String
    var createdAt: Date
    var isRead: Bool

    init(
        id: String = UUID().uuidString,
        familyId: String,
        fullText: String,
        monthKey: String,
        createdAt: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.fullText = fullText
        self.monthKey = monthKey
        self.createdAt = createdAt
        self.isRead = isRead
    }
}
