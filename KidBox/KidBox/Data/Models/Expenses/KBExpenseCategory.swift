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
    
    static let defaultCategories: [(slug: String, name: String, icon: String, colorHex: String)] = [
        ("spesa",           "Spesa",          "cart.fill",              "#4CAF50"),
        ("casa",            "Casa",           "house.fill",             "#2196F3"),
        ("trasporti",       "Trasporti",      "car.fill",               "#FF9800"),
        ("salute",          "Salute",         "heart.fill",             "#E91E63"),
        ("istruzione",      "Istruzione",     "book.fill",              "#9C27B0"),
        ("sport",           "Sport",          "figure.run",             "#00BCD4"),
        ("abbigliamento",   "Abbigliamento",  "tshirt.fill",            "#FF5722"),
        ("ristoranti",      "Ristoranti",     "fork.knife",             "#795548"),
        ("intrattenimento", "Intrattenimento","gamecontroller.fill",    "#607D8B"),
        ("viaggi",          "Viaggi",         "airplane",               "#03A9F4"),
        ("elettronica",     "Elettronica",    "desktopcomputer",        "#3F51B5"),
        ("animali",         "Animali domestici", "pawprint.fill",       "#8BC34A"),
        ("altro",           "Altro",          "ellipsis.circle.fill",   "#9E9E9E"),
    ]
    
    /// Genera un ID deterministico per una categoria default.
    ///
    /// Il formato è "expcat-{familyId}-{slug}" — stesso ID su tutti i
    /// dispositivi della stessa famiglia, quindi il categoryId di una spesa
    /// sincronizzata via Firestore matcha sempre la categoria locale.
    static func defaultCategoryId(familyId: String, slug: String) -> String {
        "expcat-\(familyId)-\(slug)"
    }
    
    /// Inserisce le categorie di default nel context se non già presenti.
    ///
    /// FIX: gli ID sono ora deterministici (expcat-{familyId}-{slug}).
    /// In questo modo tutti i dispositivi della stessa famiglia generano
    /// gli stessi ID, e il categoryId di una spesa sincronizzata via
    /// Firestore matcha la categoria locale → il grafico a torta appare
    /// correttamente su tutti i dispositivi.
    ///
    /// MIGRAZIONE: se esistono già categorie default con ID random (vecchio
    /// comportamento), vengono eliminate e ricreate con ID deterministici.
    /// Le spese collegate vengono aggiornate con il nuovo categoryId.
    static func seedDefaults(familyId: String, context: ModelContext) {
        let fid = familyId
        
        // 1. Fetch delle categorie default esistenti
        let descriptor = FetchDescriptor<KBExpenseCategory>(
            predicate: #Predicate { $0.familyId == fid && $0.isDefault == true }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        
        // 2. Controlla se esiste già almeno una con ID deterministico
        //    (inizia con "expcat-"). Se sì, il seed è già stato fatto
        //    con il nuovo formato → nessuna azione necessaria.
        let alreadyMigrated = existing.contains { $0.id.hasPrefix("expcat-") }
        if alreadyMigrated && existing.count == defaultCategories.count {
            KBLog.persistence.kbDebug("seedDefaults: already seeded with deterministic IDs familyId=\(familyId)")
            return
        }
        
        // 3. Migrazione: rimuovi le vecchie con ID random e ricrea con ID deterministici.
        //    Aggiorna anche le spese che puntano ai vecchi categoryId.
        if !existing.isEmpty {
            KBLog.persistence.kbInfo("seedDefaults: migrating \(existing.count) categories to deterministic IDs familyId=\(familyId)")
            
            // Mappa slug → nuovo ID deterministico
            let slugToNewId: [String: String] = Dictionary(
                uniqueKeysWithValues: defaultCategories.map {
                    ($0.slug, defaultCategoryId(familyId: familyId, slug: $0.slug))
                }
            )
            
            // Mappa vecchio ID → nuovo ID (per aggiornare le spese)
            var oldToNew: [String: String] = [:]
            for old in existing {
                // Trova lo slug dalla categoria esistente cercando per nome
                if let match = defaultCategories.first(where: { $0.name == old.name }),
                   let newId = slugToNewId[match.slug] {
                    oldToNew[old.id] = newId
                }
            }
            
            // Elimina le vecchie categorie
            for old in existing {
                context.delete(old)
            }
            
            // Aggiorna le spese collegate ai vecchi ID
            if !oldToNew.isEmpty {
                let expDesc = FetchDescriptor<KBExpense>(
                    predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
                )
                let spese = (try? context.fetch(expDesc)) ?? []
                for spesa in spese {
                    if let oldCatId = spesa.categoryId,
                       let newCatId = oldToNew[oldCatId] {
                        KBLog.persistence.kbDebug("seedDefaults: migrating expense categoryId \(oldCatId) → \(newCatId) expenseId=\(spesa.id)")
                        spesa.categoryId = newCatId
                        spesa.updatedAt  = Date()
                    }
                }
            }
            
            try? context.save()
        }
        
        // 4. Crea le categorie con ID deterministici
        KBLog.persistence.kbInfo("seedDefaults: creating \(defaultCategories.count) categories with deterministic IDs familyId=\(familyId)")
        for (idx, cat) in defaultCategories.enumerated() {
            let obj = KBExpenseCategory(
                id: defaultCategoryId(familyId: familyId, slug: cat.slug),
                familyId: familyId,
                name: cat.name,
                icon: cat.icon,
                colorHex: cat.colorHex,
                isDefault: true,
                sortIndex: idx
            )
            context.insert(obj)
            KBLog.persistence.kbDebug("seedDefaults: inserted catId=\(obj.id) name=\(cat.name)")
        }
        
        try? context.save()
        KBLog.persistence.kbInfo("seedDefaults: done familyId=\(familyId)")
    }
}
