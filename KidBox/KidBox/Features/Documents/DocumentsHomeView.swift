//
//  DocumentsView.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import FirebaseAuth

struct DocumentsHomeView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    @Query(sort: \KBDocumentCategory.sortOrder, order: .forward) private var categories: [KBDocumentCategory]
    
    @State private var showCreateCategory = false
    
    private var familyId: String { families.first?.id ?? "" }
    
    private var visibleCategories: [KBDocumentCategory] {
        guard !familyId.isEmpty else { return [] }
        return categories.filter { $0.familyId == familyId && !$0.isDeleted }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                
                if familyId.isEmpty {
                    emptyNoFamily
                } else if visibleCategories.isEmpty {
                    emptyNoCategories
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(visibleCategories) { cat in
                            CategoryCard(cat: cat) {
                                coordinator.navigate(to: .documentsCategory(
                                    familyId: familyId,
                                    categoryId: cat.id,
                                    title: cat.title
                                ))
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Documenti")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateCategory = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nuova categoria")
                .disabled(familyId.isEmpty)
            }
        }
        .sheet(isPresented: $showCreateCategory) {
            CreateCategorySheet(
                familyId: familyId,
                onDone: { showCreateCategory = false }
            )
        }
        .onAppear {
            // se vuoi, qui puoi far partire realtime documents/categorie
            // SyncCenter.shared.startDocumentsRealtime(familyId: familyId, modelContext: modelContext)
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Categorie")
                .font(.title2).bold()
            Text("Archivia e ritrova al volo: documenti di famiglia e del bimbo/a.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var emptyNoFamily: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Prima crea o unisciti a una famiglia.")
                .font(.headline)
            Button("Vai a Family") {
                coordinator.navigate(to: .familySettings)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
    
    private var emptyNoCategories: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Nessuna categoria")
                .font(.headline)
            Text("Crea la prima categoria (es. Identità, Salute, Scuola…).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button("Crea categoria") {
                showCreateCategory = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

private struct CategoryCard: View {
    let cat: KBDocumentCategory
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    SyncPill(state: cat.syncState, error: cat.lastSyncError)
                }
                
                Text(cat.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("Apri categoria")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
