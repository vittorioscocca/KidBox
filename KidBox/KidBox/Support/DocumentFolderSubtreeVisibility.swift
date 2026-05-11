//
//  DocumentFolderSubtreeVisibility.swift
//  KidBox — regola elenco cartelle: visibile se vuota nel sottoalbero o se c’è almeno un
//  documento che l’utente corrente può vedere.
//

import Foundation

enum DocumentFolderSubtreeVisibility {

    static func expenseId(fromCategoryId id: String) -> String? {
        guard id.hasPrefix("exp-cat-") else { return nil }
        let rest = String(id.dropFirst("exp-cat-".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    static func expenseId(fromNotes notes: String?) -> String? {
        guard let notes, notes.hasPrefix("expense:") else { return nil }
        let rest = String(notes.dropFirst("expense:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    /// Include `rootId` e tutte le sottocartelle attive.
    static func collectDescendantFolderIds(rootId: String, categories: [KBDocumentCategory]) -> Set<String> {
        let active = categories.filter { !$0.isDeleted }
        var byParent: [String: [KBDocumentCategory]] = [:]
        for c in active {
            let pk = c.parentId ?? ""
            byParent[pk, default: []].append(c)
        }
        var result = Set<String>()
        var queue = [rootId]
        var i = 0
        while i < queue.count {
            let id = queue[i]
            i += 1
            if !result.insert(id).inserted { continue }
            for child in byParent[id, default: []] {
                queue.append(child.id)
            }
        }
        return result
    }

    static func docsInSubtree(
        folder: KBDocumentCategory,
        allCategories: [KBDocumentCategory],
        allDocuments: [KBDocument],
    ) -> [KBDocument] {
        let subtreeIds = collectDescendantFolderIds(rootId: folder.id, categories: allCategories)
        let expenseFolderId = expenseId(fromCategoryId: folder.id)
        return allDocuments.filter { doc in
            if doc.isDeleted { return false }
            let cat = doc.categoryId ?? ""
            if !cat.isEmpty, subtreeIds.contains(cat) { return true }
            if let eid = expenseFolderId, expenseId(fromNotes: doc.notes) == eid {
                return cat.isEmpty || subtreeIds.contains(cat)
            }
            return false
        }
    }

    static func folderIsBrowsable(
        folder: KBDocumentCategory,
        allCategories: [KBDocumentCategory],
        allDocuments: [KBDocument],
        viewerUid: String?,
    ) -> Bool {
        if folder.isDeleted { return false }
        let subtreeDocs = docsInSubtree(folder: folder, allCategories: allCategories, allDocuments: allDocuments)
        if subtreeDocs.isEmpty { return true }
        return subtreeDocs.contains { $0.isVisibleToCurrentUser(currentUid: viewerUid) }
    }
}
