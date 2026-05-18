//
//  KBPackingItem.swift
//  KidBox
//

import Foundation
import SwiftData

enum PackingCategory: String, CaseIterable {
    case documents
    case clothing
    case health
    case kids
    case other

    var label: String {
        switch self {
        case .documents: return "Documenti"
        case .clothing: return "Abbigliamento"
        case .health: return "Salute"
        case .kids: return "Bambini"
        case .other: return "Altro"
        }
    }
}

@Model
final class KBPackingItem {
    @Attribute(.unique) var id: String
    var familyId: String
    var tripId: String
    var label: String
    var categoryRaw: String
    var isChecked: Bool
    var isAIGenerated: Bool
    var fromMedicalProfile: Bool
    var updatedAt: Date

    var category: PackingCategory { PackingCategory(rawValue: categoryRaw) ?? .other }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        tripId: String,
        label: String,
        categoryRaw: String = "other",
        isAIGenerated: Bool = false,
        fromMedicalProfile: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.tripId = tripId
        self.label = label
        self.categoryRaw = categoryRaw
        self.isChecked = false
        self.isAIGenerated = isAIGenerated
        self.fromMedicalProfile = fromMedicalProfile
        self.updatedAt = .now
    }
}
