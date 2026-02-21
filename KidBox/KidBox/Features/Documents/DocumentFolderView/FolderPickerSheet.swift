//
//  FolderPickerSheet.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//

import SwiftUI
import SwiftData

/// Sheet per scegliere una cartella destinazione per Sposta / Copia.
///
/// - Mostra la gerarchia completa delle cartelle della famiglia
/// - Esclude la cartella sorgente e tutti i suoi discendenti (non puoi spostare dentro te stesso)
/// - Permette di scegliere "Root" (senza cartella padre)
struct FolderPickerSheet: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let familyId: String
    /// ID delle cartelle da escludere (la sorgente + i suoi figli)
    let excludedFolderIds: Set<String>
    /// Titolo dello sheet ("Sposta in…" o "Copia in…")
    let title: String
    /// Callback con l'id cartella scelta (nil = root)
    let onSelect: (String?) -> Void
    
    @State private var allFolders: [KBDocumentCategory] = []
    
    var body: some View {
        NavigationStack {
            List {
                // Root
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    Label("Documenti (radice)", systemImage: "house.fill")
                        .foregroundStyle(.primary)
                }
                
                // Albero ricorsivo
                ForEach(rootFolders) { folder in
                    FolderPickerRow(
                        folder: folder,
                        allFolders: allFolders,
                        excluded: excludedFolderIds,
                        depth: 0,
                        onSelect: { id in
                            onSelect(id)
                            dismiss()
                        }
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                }
            }
            .onAppear { loadFolders() }
        }
    }
    
    private var rootFolders: [KBDocumentCategory] {
        allFolders
            .filter { ($0.parentId == nil || $0.parentId == "") && !excludedFolderIds.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private func loadFolders() {
        let fid = familyId
        let desc = FetchDescriptor<KBDocumentCategory>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        )
        allFolders = (try? modelContext.fetch(desc)) ?? []
    }
}

// MARK: - Row ricorsiva

private struct FolderPickerRow: View {
    let folder: KBDocumentCategory
    let allFolders: [KBDocumentCategory]
    let excluded: Set<String>
    let depth: Int
    let onSelect: (String) -> Void
    
    var body: some View {
        Group {
            Button {
                onSelect(folder.id)
            } label: {
                HStack(spacing: 6) {
                    // indentazione visiva
                    if depth > 0 {
                        Color.clear.frame(width: CGFloat(depth) * 16)
                    }
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.orange)
                    Text(folder.title)
                        .foregroundStyle(.primary)
                }
            }
            
            ForEach(children) { child in
                FolderPickerRow(
                    folder: child,
                    allFolders: allFolders,
                    excluded: excluded,
                    depth: depth + 1,
                    onSelect: onSelect
                )
            }
        }
    }
    
    private var children: [KBDocumentCategory] {
        let pid = folder.id
        return allFolders
            .filter { $0.parentId == pid && !excluded.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}//
//  FolderPickerSheet.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//

