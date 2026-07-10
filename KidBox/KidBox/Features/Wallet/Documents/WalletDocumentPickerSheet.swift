//
//  WalletDocumentPickerSheet.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Sfoglia le cartelle/documenti già presenti nella sezione Documenti e
//  permette di scegliere un documento esistente (es. una foto della Tessera
//  Sanitaria caricata in passato) da collegare al Wallet, senza duplicarlo.
//  Stessa logica di fetch cartelle/documenti radice di
//  `DocumentFolderViewModel.fetchFolders/fetchDocs`, qui semplificata per la
//  sola navigazione in lettura.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct WalletDocumentPickerSheet: View {
    let familyId: String
    let onSelect: (KBDocument) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            WalletDocumentPickerFolderView(
                familyId: familyId, folderId: nil, folderTitle: "Documenti",
                onSelect: onSelect, onCancel: onCancel
            )
        }
    }
}

private struct WalletDocumentPickerFolderView: View {
    let familyId: String
    let folderId: String?
    let folderTitle: String
    let onSelect: (KBDocument) -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var folders: [KBDocumentCategory] = []
    @State private var documents: [KBDocument] = []

    var body: some View {
        List {
            if folders.isEmpty && documents.isEmpty {
                Text("Nessun documento in questa cartella.")
                    .foregroundStyle(.secondary)
            }
            if !folders.isEmpty {
                Section("Cartelle") {
                    ForEach(folders, id: \.id) { folder in
                        NavigationLink {
                            WalletDocumentPickerFolderView(
                                familyId: familyId, folderId: folder.id, folderTitle: folder.title,
                                onSelect: onSelect, onCancel: onCancel
                            )
                        } label: {
                            Label(folder.title, systemImage: "folder.fill")
                        }
                    }
                }
            }
            if !documents.isEmpty {
                Section("Documenti") {
                    ForEach(documents, id: \.id) { document in
                        Button {
                            onSelect(document)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: document.isPDFDocument ? "doc.richtext.fill" : "photo.fill")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(document.title)
                                        .foregroundStyle(.primary)
                                    Text(document.fileName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(folderTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annulla") { onCancel() }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let fid = familyId
        let currentUid = Auth.auth().currentUser?.uid
        do {
            let cats: [KBDocumentCategory]
            let docs: [KBDocument]
            if let pid = folderId {
                cats = try modelContext.fetch(FetchDescriptor<KBDocumentCategory>(
                    predicate: #Predicate { $0.familyId == fid && $0.parentId == pid && $0.isDeleted == false }))
                docs = try modelContext.fetch(FetchDescriptor<KBDocument>(
                    predicate: #Predicate { $0.familyId == fid && $0.categoryId == pid && $0.isDeleted == false }))
            } else {
                let catsA = try modelContext.fetch(FetchDescriptor<KBDocumentCategory>(
                    predicate: #Predicate { $0.familyId == fid && $0.parentId == nil && $0.isDeleted == false }))
                let catsB = try modelContext.fetch(FetchDescriptor<KBDocumentCategory>(
                    predicate: #Predicate { $0.familyId == fid && $0.parentId == "" && $0.isDeleted == false }))
                var catMap: [String: KBDocumentCategory] = [:]
                for c in catsA { catMap[c.id] = c }
                for c in catsB { catMap[c.id] = c }
                cats = catMap.values.sorted { $0.sortOrder < $1.sortOrder }

                let docsA = try modelContext.fetch(FetchDescriptor<KBDocument>(
                    predicate: #Predicate { $0.familyId == fid && $0.categoryId == nil && $0.isDeleted == false }))
                let docsB = try modelContext.fetch(FetchDescriptor<KBDocument>(
                    predicate: #Predicate { $0.familyId == fid && $0.categoryId == "" && $0.isDeleted == false }))
                var docMap: [String: KBDocument] = [:]
                for d in docsA { docMap[d.id] = d }
                for d in docsB { docMap[d.id] = d }
                docs = docMap.values.sorted { $0.updatedAt > $1.updatedAt }
            }
            folders = cats.sorted { $0.sortOrder < $1.sortOrder }
            documents = docs.filteredToVisibleDocuments(currentUid: currentUid)
        } catch {
            folders = []
            documents = []
        }
    }
}
