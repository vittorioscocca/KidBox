//
//  NotesHomeView.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - Swipeable card wrapper

private struct SwipeToDeleteCard<Content: View>: View {
    let content: Content
    let onDelete: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var showConfirm = false
    
    private let deleteWidth: CGFloat = 72
    private let triggerThreshold: CGFloat = 60
    
    init(onDelete: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDelete = onDelete
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                showConfirm = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.title3)
                    Text("Elimina")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
                .frame(width: deleteWidth)
                .frame(maxHeight: .infinity)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .opacity(offset < -8 ? 1 : 0)
            
            content
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            let translation = value.translation.width
                            guard translation < 0 else { offset = 0; return }
                            offset = max(translation, -(deleteWidth + 16))
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                offset = value.translation.width < -triggerThreshold ? -deleteWidth : 0
                            }
                        }
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: offset)
        }
        .confirmationDialog("Eliminare questa nota?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { withAnimation { onDelete() } }
            Button("Annulla", role: .cancel) { withAnimation { offset = 0 } }
        }
        .onTapGesture {
            if offset != 0 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = 0 }
            }
        }
    }
}

// MARK: - Empty state

private struct NotesEmptyStateView: View {
    let onNewNote: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Nessuna nota")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Crea la prima nota della famiglia\ntoccando il tasto in alto a destra.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onNewNote()
            } label: {
                Label("Nuova nota", systemImage: "square.and.pencil")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - No results state

private struct NotesNoResultsView: View {
    let query: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Nessun risultato")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Nessuna nota contiene \"\(query)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - NotesHomeView

struct NotesHomeView: View {
    let familyId: String
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    @Query private var notes: [KBNote]
    @Query private var members: [KBFamilyMember]
    
    @State private var searchQuery = ""
    
    private var filteredNotes: [KBNote] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return notes }
        return notes.filter {
            $0.title.lowercased().contains(q) ||
            $0.body.lowercased().contains(q)
        }
    }
    
    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _notes = Query(
            filter: #Predicate<KBNote> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBNote.updatedAt, order: .reverse)]
        )
        _members = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted },
            sort: \.displayName
        )
    }
    
    var body: some View {
        Group {
            if notes.isEmpty {
                NotesEmptyStateView { createNewNote() }
            } else if filteredNotes.isEmpty {
                NotesNoResultsView(query: searchQuery)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                        ForEach(filteredNotes, id: \.id) { note in
                            SwipeToDeleteCard {
                                delete(note)
                            } content: {
                                KBNoteCardView(
                                    note: note,
                                    members: members,
                                    searchQuery: searchQuery  // ← passa la query per l'highlight
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    coordinator.navigate(to: .noteDetail(familyId: familyId, noteId: note.id))
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Note")
        .searchable(text: $searchQuery, prompt: "Cerca nelle note")
        .onAppear {
            SyncCenter.shared.startNotesRealtime(familyId: familyId, modelContext: modelContext)
        }
        .onDisappear {
            SyncCenter.shared.stopNotesRealtime()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { createNewNote() } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func createNewNote() {
        let id = UUID().uuidString
        coordinator.navigate(to: .noteDetail(familyId: familyId, noteId: id))
    }
    
    private func delete(_ note: KBNote) {
        note.isDeleted = true
        note.syncState = .pendingDelete
        note.lastSyncError = nil
        try? modelContext.save()
        
        SyncCenter.shared.enqueueNoteDelete(
            noteId: note.id,
            familyId: familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
}
