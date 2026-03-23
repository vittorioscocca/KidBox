//
//  KBExpense.swift
//  KidBox
//
//  Created by vscocca on 23/03/26.
//

import Foundation
import SwiftData

// MARK: - Expense

/// Singola spesa di famiglia.
@Model
final class KBExpense {
    @Attribute(.unique) var id: String
    var familyId: String
    
    /// Titolo / descrizione breve (es. "Supermercato Carrefour")
    var title: String
    
    /// Importo in euro
    var amount: Double
    
    /// Data della spesa
    var date: Date
    
    /// ID della categoria (riferimento debole a `KBExpenseCategory.id`)
    var categoryId: String?
    
    /// Note libere opzionali
    var notes: String?
    
    /// Riferimento a un documento allegato (ID di `KBDocument`, opzionale)
    var attachedDocumentId: String?
    
    /// Piccola anteprima JPEG del documento/ricevuta (max ~80 KB)
    @Attribute(.externalStorage) var receiptThumbnailData: Data?
    
    /// Chi ha inserito la spesa (UID Firebase)
    var createdByUid: String?
    
    /// Chi ha fatto l'ultimo aggiornamento (UID Firebase)
    var updatedBy: String?
    
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    
    // MARK: - Sync
    
    var syncStateRaw: Int
    var lastSyncError: String?
    
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .pendingUpsert }
        set { syncStateRaw = newValue.rawValue }
    }
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        title: String,
        amount: Double,
        date: Date = Date(),
        categoryId: String? = nil,
        notes: String? = nil,
        attachedDocumentId: String? = nil,
        createdByUid: String? = nil
    ) {
        self.id                 = id
        self.familyId           = familyId
        self.title              = title
        self.amount             = amount
        self.date               = date
        self.categoryId         = categoryId
        self.notes              = notes
        self.attachedDocumentId = attachedDocumentId
        self.createdByUid       = createdByUid
        self.updatedBy          = createdByUid
        self.createdAt          = Date()
        self.updatedAt          = Date()
        self.isDeleted          = false
        self.syncStateRaw       = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError      = nil
    }
}
