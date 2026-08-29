//
//  KBLinkedExpense.swift
//  KidBox
//
//  La spesa di famiglia che nasce da un'altra scheda.
//
//  Un intervento sull'auto, una scadenza di casa, una visita, un esame: sono
//  cose diverse, ma il pezzo "se ha un costo diventa una voce in Spese" è lo
//  stesso, e le regole con cui vive devono restare identiche ovunque. Stanno
//  qui una volta sola:
//
//  - costo > 0 e nessuna spesa collegata → la crea;
//  - costo > 0 e spesa già collegata → la aggiorna (titolo, importo, data, note);
//  - costo tolto → la spesa collegata sparisce: la scheda sta dicendo che non
//    c'è un costo, e lasciarla in giro falserebbe i conti.
//
//  Chi chiama salva l'id restituito nel proprio `linkedExpenseId`. Eliminando
//  la scheda la spesa **resta**: i soldi sono usciti comunque.
//

import Foundation
import SwiftData
import FirebaseAuth

enum KBLinkedExpense {

    /// - Returns: l'id della spesa da conservare, o `nil` se non ce n'è più una.
    @MainActor
    @discardableResult
    static func sync(
        linkedExpenseId: String?,
        amount: Double?,
        title: String,
        fallbackTitle: String,
        date: Date,
        notes: String?,
        categorySlug: String,
        familyId: String,
        modelContext: ModelContext
    ) -> String? {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let value = amount ?? 0

        let existing: KBExpense? = {
            guard let linkedExpenseId else { return nil }
            let desc = FetchDescriptor<KBExpense>(predicate: #Predicate { $0.id == linkedExpenseId })
            return try? modelContext.fetch(desc).first
        }()

        guard value > 0 else {
            guard let existing else { return nil }
            existing.isDeleted = true
            existing.updatedAt = now
            existing.updatedBy = uid
            existing.syncState = .pendingDelete
            try? modelContext.save()
            SyncCenter.shared.enqueueExpenseDelete(expenseId: existing.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            return nil
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let expenseTitle = trimmedTitle.isEmpty ? fallbackTitle : trimmedTitle

        if let existing {
            existing.title = expenseTitle
            existing.amount = value
            existing.date = date
            existing.notes = notes
            existing.updatedAt = now
            existing.updatedBy = uid
            existing.syncState = .pendingUpsert
            try? modelContext.save()
            SyncCenter.shared.enqueueExpenseUpsert(expenseId: existing.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            return existing.id
        }

        // La categoria deve esistere prima di agganciarcisi: su una famiglia che
        // non ha mai aperto le Spese non è ancora stata creata.
        KBExpenseCategory.seedDefaults(familyId: familyId, context: modelContext)

        let expense = KBExpense(
            familyId: familyId,
            title: expenseTitle,
            amount: value,
            date: date,
            categoryId: KBExpenseCategory.defaultCategoryId(familyId: familyId, slug: categorySlug),
            notes: notes,
            attachedDocumentId: nil,
            createdByUid: uid
        )
        expense.syncState = .pendingUpsert
        modelContext.insert(expense)
        try? modelContext.save()
        SyncCenter.shared.enqueueExpenseUpsert(expenseId: expense.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        AppAnalytics.contentCreated(type: "expenses")
        return expense.id
    }
}
