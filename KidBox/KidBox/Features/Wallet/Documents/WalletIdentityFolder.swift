//
//  WalletIdentityFolder.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Cartella radice "Documenti d'identità" nella sezione Documenti: sia i
//  documenti scansionati dal Wallet sia quelli collegati da una cartella
//  esistente finiscono qui, così restano visibili e organizzati in Documenti
//  (non spariscono) oltre che nella sezione Documenti del Wallet.
//

import Foundation
import SwiftData

enum WalletIdentityFolder {

    static let title = "Documenti d'identità"

    /// Trova (o crea) la cartella radice "Documenti d'identità" e ne restituisce l'id.
    @MainActor
    static func findOrCreate(familyId: String, uid: String, modelContext: ModelContext) throws -> String {
        let fid = familyId
        let folderTitle = title
        let existing = try modelContext.fetch(FetchDescriptor<KBDocumentCategory>(
            predicate: #Predicate<KBDocumentCategory> {
                $0.familyId == fid && $0.parentId == nil && $0.isDeleted == false && $0.title == folderTitle
            }
        )).first
        if let existing { return existing.id }

        let now = Date()
        let category = KBDocumentCategory(
            familyId: familyId, title: folderTitle, sortOrder: 0, parentId: nil,
            updatedBy: uid, createdAt: now, updatedAt: now, isDeleted: false
        )
        modelContext.insert(category)
        try modelContext.save()
        SyncCenter.shared.enqueueDocumentCategoryUpsert(
            categoryId: category.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)

        let dto = RemoteDocumentCategoryDTO(
            id: category.id, familyId: familyId, title: category.title,
            sortOrder: category.sortOrder, parentId: category.parentId,
            isDeleted: false, updatedAt: now, updatedBy: uid)
        Task.detached(priority: .userInitiated) {
            try? await DocumentCategoryRemoteStore().upsert(dto: dto)
        }
        return category.id
    }
}
