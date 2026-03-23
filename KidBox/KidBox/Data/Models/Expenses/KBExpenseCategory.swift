//
//  KBExpenseCategory.swift
//  KidBox
//
//  Created by vscocca on 23/03/26.
//

import Foundation
import SwiftData

// MARK: - Category

/// Categoria spesa (predefinita o custom).
@Model
final class KBExpenseCategory {
    @Attribute(.unique) var id: String
    var familyId: String
    var name: String
    var icon: String          // SF Symbol name
    var colorHex: String      // es. "#FF6B6B"
    var isDefault: Bool
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        name: String,
        icon: String,
        colorHex: String,
        isDefault: Bool = false,
        sortIndex: Int = 0
    ) {
        self.id        = id
        self.familyId  = familyId
        self.name      = name
        self.icon      = icon
        self.colorHex  = colorHex
        self.isDefault = isDefault
        self.sortIndex = sortIndex
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isDeleted = false
    }
}

// MARK: - Default categories helper

extension KBExpenseCategory {
    
    static let defaultCategories: [(name: String, icon: String, colorHex: String)] = [
        ("Spesa",         "cart.fill",               "#4CAF50"),
        ("Casa",          "house.fill",               "#2196F3"),
        ("Trasporti",     "car.fill",                 "#FF9800"),
        ("Salute",        "heart.fill",               "#E91E63"),
        ("Istruzione",    "book.fill",                "#9C27B0"),
        ("Sport",         "figure.run",               "#00BCD4"),
        ("Abbigliamento", "tshirt.fill",              "#FF5722"),
        ("Ristoranti",    "fork.knife",               "#795548"),
        ("Intrattenimento","gamecontroller.fill",     "#607D8B"),
        ("Viaggi",        "airplane",                 "#03A9F4"),
        ("Elettronica",   "desktopcomputer",          "#3F51B5"),
        ("Animali",       "pawprint.fill",            "#8BC34A"),
        ("Altro",         "ellipsis.circle.fill",     "#9E9E9E"),
    ]
    
    /// Genera e inserisce le categorie di default nel context se non già presenti.
    static func seedDefaults(familyId: String, context: ModelContext) {
        let fid = familyId
        let descriptor = FetchDescriptor<KBExpenseCategory>(
            predicate: #Predicate { $0.familyId == fid && $0.isDefault == true }
        )
        guard (try? context.fetch(descriptor))?.isEmpty ?? true else { return }
        
        for (idx, cat) in defaultCategories.enumerated() {
            let obj = KBExpenseCategory(
                familyId: familyId,
                name: cat.name,
                icon: cat.icon,
                colorHex: cat.colorHex,
                isDefault: true,
                sortIndex: idx
            )
            context.insert(obj)
        }
    }
}

