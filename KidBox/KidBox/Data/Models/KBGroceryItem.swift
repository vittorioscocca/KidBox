//
//  KBGroceryItem.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class KBGroceryItem {
    
    // MARK: - Identity
    @Attribute(.unique) var id: String
    var familyId: String
    
    // MARK: - Content
    var name: String
    var category: String?
    var notes: String?
    /// Quante confezioni servono. `nil` (o 1) significa una sola: la lista non
    /// scrive "x 1", che sarebbe rumore su quasi tutte le righe.
    var quantity: Int?
    
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
        quantity: Int? = nil,
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
        self.quantity = quantity
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

    /// Simbolo e tinta per categoria: sono il segno che si legge da lontano
    /// mentre si spinge il carrello, dove il nome della categoria è già scritto
    /// sopra il gruppo. Simboli SF e non emoji, come nel resto dell'app: si
    /// tingono, seguono il peso del testo e non dipendono dal font di sistema.
    static func symbol(for category: String?) -> String {
        switch normalized(category) {
        case "Frutta e Verdura": return "carrot.fill"
        case "Carne e Pesce":    return "fish.fill"
        case "Latticini":        return "waterbottle.fill"
        case "Pane e Cereali":   return "fork.knife"
        case "Surgelati":        return "snowflake"
        case "Bevande":          return "cup.and.saucer.fill"
        case "Dolci e Snack":    return "birthday.cake.fill"
        case "Pulizia":          return "bubbles.and.sparkles.fill"
        case "Cura Personale":   return "comb.fill"
        default:                 return "cart.fill"
        }
    }

    static func tint(for category: String?) -> Color {
        switch normalized(category) {
        case "Frutta e Verdura": return .green
        case "Carne e Pesce":    return .red
        case "Latticini":        return .blue
        case "Pane e Cereali":   return .orange
        case "Surgelati":        return .cyan
        case "Bevande":          return .teal
        case "Dolci e Snack":    return .pink
        case "Pulizia":          return .mint
        case "Cura Personale":   return .purple
        default:                 return .gray
        }
    }

    private static func normalized(_ category: String?) -> String {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? uncategorized : trimmed
    }

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
