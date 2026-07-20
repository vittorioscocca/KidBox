//
//  KBGroceryItem.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import Foundation
import SwiftData

@Model
final class KBGroceryItem {
    
    // MARK: - Identity
    @Attribute(.unique) var id: String
    var familyId: String
    
    // MARK: - Content
    var name: String
    var category: String?
    var notes: String?
    
    // MARK: - State
    var isPurchased: Bool
    var purchasedAt: Date?
    var purchasedBy: String?
    
    // MARK: - Soft delete
    var isDeleted: Bool
    
    // MARK: - Sync metadata
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String?
    var createdBy: String?
    var syncStateRaw: Int
    var lastSyncError: String?
    
    // MARK: - Computed sync state
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        name: String,
        category: String? = nil,
        notes: String? = nil,
        isPurchased: Bool = false,
        purchasedAt: Date? = nil,
        purchasedBy: String? = nil,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        updatedBy: String? = nil,
        createdBy: String? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.name = name
        self.category = category
        self.notes = notes
        self.isPurchased = isPurchased
        self.purchasedAt = purchasedAt
        self.purchasedBy = purchasedBy
        self.isDeleted = isDeleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.createdBy = createdBy
        self.syncStateRaw = KBSyncState.synced.rawValue
    }
}

// MARK: - Category display

/// Categorie suggerite per la lista della spesa. Il valore salvato in `category`
/// resta in italiano (per compatibilità dati tra membri della famiglia con lingue
/// diverse); `displayName(for:)` restituisce l'etichetta localizzata da mostrare
/// in UI. Le categorie inserite liberamente dall'utente (non in questo elenco)
/// vengono mostrate invariate.
enum KBGroceryCategory {
    static let suggested = [
        "Frutta e Verdura", "Carne e Pesce", "Latticini", "Pane e Cereali",
        "Surgelati", "Bevande", "Dolci e Snack", "Pulizia", "Cura Personale", "Altro"
    ]

    /// Etichetta per categoria "non specificata" (item senza `category`).
    static let uncategorized = "Altro"

    static func displayName(for category: String) -> String {
        switch category {
        case "Frutta e Verdura": return NSLocalizedString("Frutta e Verdura", comment: "Grocery category")
        case "Carne e Pesce":    return NSLocalizedString("Carne e Pesce", comment: "Grocery category")
        case "Latticini":        return NSLocalizedString("Latticini", comment: "Grocery category")
        case "Pane e Cereali":   return NSLocalizedString("Pane e Cereali", comment: "Grocery category")
        case "Surgelati":        return NSLocalizedString("Surgelati", comment: "Grocery category")
        case "Bevande":          return NSLocalizedString("Bevande", comment: "Grocery category")
        case "Dolci e Snack":    return NSLocalizedString("Dolci e Snack", comment: "Grocery category")
        case "Pulizia":          return NSLocalizedString("Pulizia", comment: "Grocery category")
        case "Cura Personale":   return NSLocalizedString("Cura Personale", comment: "Grocery category")
        case "Altro":            return NSLocalizedString("Altro", comment: "Grocery category: other")
        default:                 return category
        }
    }
}
