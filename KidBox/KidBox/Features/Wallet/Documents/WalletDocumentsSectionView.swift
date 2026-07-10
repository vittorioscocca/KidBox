//
//  WalletDocumentsSectionView.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Sezione "Documenti" del Wallet: elenco a schede (stessa lingua visiva dei
//  biglietti) dei documenti d'identità acquisiti, raggruppati per titolare.
//  Possiede il proprio toolbar (Seleziona + "+") — il tab Biglietti in
//  `WalletHomeView` ha il proprio "+" indipendente.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct WalletDocumentsSectionView: View {
    let familyId: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var documents: [KBDocument]
    @Query private var children: [KBChild]
    @Query private var members: [KBFamilyMember]

    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @State private var isDeleting = false

    @State private var showAddChoice = false
    @State private var showAddSheet = false
    @State private var showLinkExistingSheet = false

    // Layout stack sovrapposto (stessa impostazione di `WalletHomeView.cardStack`).
    private let cardHeight: CGFloat = 172
    private let peekHeight: CGFloat = 68

    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _documents = Query(
            filter: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBDocument.updatedAt, order: .reverse)]
        )
        _children = Query(filter: #Predicate<KBChild> { $0.familyId == fid })
        _members = Query(filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted })
    }

    private var currentUid: String? { Auth.auth().currentUser?.uid }

    private var walletDocuments: [KBDocument] {
        documents
            .filter { $0.walletDocumentKind != nil }
            .filter { $0.isVisibleToCurrentUser(currentUid: currentUid) }
    }

    private func ownerName(for document: KBDocument) -> String {
        guard let childId = document.childId, !childId.isEmpty else { return "Famiglia" }
        if let child = children.first(where: { $0.id == childId }) { return child.name }
        if let member = members.first(where: { $0.userId == childId }) { return member.displayName ?? "Membro famiglia" }
        return "Famiglia"
    }

    var body: some View {
        Group {
            if walletDocuments.isEmpty {
                ContentUnavailableView(
                    "Nessun documento",
                    systemImage: "cross.case",
                    description: Text("Acquisisci la Tessera Sanitaria o un altro documento d'identità.")
                )
            } else {
                cardStack
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isSelecting {
                    Button(role: .destructive) {
                        Task { await deleteSelected() }
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Elimina (\(selectedIds.count))")
                        }
                    }
                    .disabled(selectedIds.isEmpty || isDeleting)

                    Button("Annulla") {
                        isSelecting = false
                        selectedIds.removeAll()
                    }
                } else {
                    if !walletDocuments.isEmpty {
                        Button("Seleziona") {
                            isSelecting = true
                            selectedIds.removeAll()
                        }
                    }
                    Button {
                        showAddChoice = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .confirmationDialog("Nuovo documento", isPresented: $showAddChoice, titleVisibility: .visible) {
            Button("Scansiona nuovo documento") { showAddSheet = true }
            Button("Collega documento già in Documenti") { showLinkExistingSheet = true }
            Button("Annulla", role: .cancel) {}
        }
        .sheet(isPresented: $showAddSheet) {
            AddWalletDocumentSheet(familyId: familyId) { _ in }
        }
        .sheet(isPresented: $showLinkExistingSheet) {
            LinkExistingWalletDocumentSheet(familyId: familyId) { _ in }
        }
    }

    // MARK: - Stack sovrapposto

    private var cardStack: some View {
        ScrollView {
            // Spacing negativo: ogni card copre la precedente lasciandone
            // visibili solo `peekHeight` pt — stesso effetto dei biglietti.
            let overlap = cardHeight - peekHeight
            VStack(spacing: -overlap) {
                ForEach(Array(walletDocuments.enumerated()), id: \.element.id) { index, document in
                    cardRow(for: document)
                        .zIndex(Double(index))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func cardRow(for document: KBDocument) -> some View {
        let selected = selectedIds.contains(document.id)
        let card = WalletDocumentCardView(
            document: document,
            ownerName: ownerName(for: document),
            isSelectionMode: isSelecting,
            isSelected: selected,
            height: cardHeight
        )

        if isSelecting {
            Button {
                if selected { selectedIds.remove(document.id) } else { selectedIds.insert(document.id) }
            } label: {
                card
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                WalletDocumentDetailView(familyId: familyId, documentId: document.id)
            } label: {
                card
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    Task { await delete(documents: [document]) }
                } label: {
                    Label("Elimina", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Delete

    private func deleteSelected() async {
        let toDelete = walletDocuments.filter { selectedIds.contains($0.id) }
        await delete(documents: toDelete)
        isSelecting = false
        selectedIds.removeAll()
    }

    /// Hard delete (Storage + Firestore + locale), stesso servizio già usato
    /// dalla sezione Documenti generica (`DocumentFolderViewModel.deleteDocumentCore`).
    private func delete(documents toDelete: [KBDocument]) async {
        guard !toDelete.isEmpty else { return }
        isDeleting = true
        defer { isDeleting = false }

        let deleteService = DocumentDeleteService()
        for doc in toDelete {
            do {
                try await deleteService.deleteDocumentHard(familyId: familyId, doc: doc)
            } catch {
                // best-effort: continua con gli altri anche se uno fallisce
            }
            await WalletDocumentReminderService.shared.cancelReminders(documentId: doc.id)
            modelContext.delete(doc)
        }
        try? modelContext.save()
    }
}
