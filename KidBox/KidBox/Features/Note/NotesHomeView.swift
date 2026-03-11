//
//  NotesHomeView.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct NotesHomeView: View {
    let familyId: String
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    @Query private var notes: [KBNote]
    @Query private var members: [KBFamilyMember]
    
    @State private var searchQuery = ""
    @State private var pinnedIds: Set<String> = []
    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    
    // MARK: - Sezioni temporali
    
    private enum NoteSection: String {
        case pinned = "In evidenza"
        case week7  = "Ultimi 7 giorni"
        case days30 = "Ultimi 30 giorni"
        case older  = "Più vecchie"
    }
    
    private var sectioned: [(NoteSection, [KBNote])] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = notes.filter { !$0.isDeleted }
        let filtered = q.isEmpty ? base : base.filter {
            $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q)
        }
        
        let now = Date()
        let cal = Calendar.current
        
        var pinned: [KBNote] = []
        var week7:  [KBNote] = []
        var days30: [KBNote] = []
        var older:  [KBNote] = []
        
        for note in filtered.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            if pinnedIds.contains(note.id) {
                pinned.append(note)
                continue
            }
            let days = cal.dateComponents([.day], from: note.updatedAt, to: now).day ?? 0
            if days <= 7       { week7.append(note) }
            else if days <= 30 { days30.append(note) }
            else               { older.append(note) }
        }
        
        return [
            (.pinned, pinned),
            (.week7,  week7),
            (.days30, days30),
            (.older,  older),
        ].filter { !$1.isEmpty }
    }
    
    private var allVisibleIds: [String] {
        sectioned.flatMap { $0.1 }.map { $0.id }
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
    
    // MARK: - Body
    
    var body: some View {
        contentView
            .navigationTitle("Note")
            .searchable(text: $searchQuery, prompt: "Cerca nelle note")
            .onAppear {
                SyncCenter.shared.startNotesRealtime(familyId: familyId, modelContext: modelContext)
                loadPinned()
                BadgeManager.shared.activeSections.insert("notes")  // ← attivo
                Task {
                    BadgeManager.shared.clearNotes()
                    await CountersService.shared.reset(familyId: familyId, field: .notes)
                }
                if let text = coordinator.pendingShareText {
                    coordinator.pendingShareText = nil
                    // Crea una nuova nota con il testo e naviga al detail
                    let uid = Auth.auth().currentUser?.uid ?? "local"
                    let noteId = UUID().uuidString
                    let note = KBNote(
                        id: noteId, familyId: familyId,
                        title: text.components(separatedBy: "\n").first ?? text,
                        body: text,
                        createdBy: uid, createdByName: "",
                        updatedBy: uid, updatedByName: "",
                        createdAt: .now, updatedAt: .now,
                        isDeleted: false
                    )
                    note.syncState = .pendingUpsert
                    modelContext.insert(note)
                    try? modelContext.save()
                    SyncCenter.shared.enqueueNoteUpsert(
                        noteId: noteId, familyId: familyId, modelContext: modelContext
                    )
                    // Naviga al detail così l'utente può rifinire
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        coordinator.navigate(to: .noteDetail(familyId: familyId, noteId: noteId))
                    }
                }
            }
            .onDisappear {
                SyncCenter.shared.stopNotesRealtime()
                BadgeManager.shared.activeSections.remove("notes")  // ← non più attivo
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isSelecting {
                        Button("Fine") {
                            isSelecting = false
                            selectedIds = []
                        }
                    } else {
                        Button("Seleziona") {
                            isSelecting = true
                        }
                        Button { createNewNote() } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
                
                ToolbarItemGroup(placement: .bottomBar) {
                    if isSelecting {
                        Button(role: .destructive) {
                            deleteSelected()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text(selectedIds.isEmpty ? "Elimina" : "Elimina (\(selectedIds.count))")
                            }
                            .foregroundStyle(selectedIds.isEmpty ? .secondary : Color.red)
                        }
                        .disabled(selectedIds.isEmpty)
                        
                        Spacer()
                        
                        Button {
                            let all = allVisibleIds
                            selectedIds = selectedIds.count == all.count ? [] : Set(all)
                        } label: {
                            Text(selectedIds.count == allVisibleIds.count ? "Deseleziona tutto" : "Seleziona tutto")
                        }
                    }
                }
            }
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentView: some View {
        if notes.isEmpty {
            NotesEmptyStateView { createNewNote() }
        } else if sectioned.isEmpty {
            NotesNoResultsView(query: searchQuery)
        } else {
            List {
                ForEach(sectioned, id: \.0.rawValue) { section, sectionNotes in
                    Section(section.rawValue) {
                        ForEach(sectionNotes, id: \.id) { note in
                            noteRow(note)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.default, value: isSelecting)
        }
    }
    
    @ViewBuilder
    private func noteRow(_ note: KBNote) -> some View {
        Button {
            if isSelecting {
                if selectedIds.contains(note.id) {
                    selectedIds.remove(note.id)
                } else {
                    selectedIds.insert(note.id)
                }
            } else {
                coordinator.navigate(to: .noteDetail(familyId: familyId, noteId: note.id))
            }
        } label: {
            HStack(spacing: 10) {
                if isSelecting {
                    Image(systemName: selectedIds.contains(note.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedIds.contains(note.id) ? Color.accentColor : .secondary)
                        .animation(.spring(response: 0.2), value: selectedIds.contains(note.id))
                }
                
                if pinnedIds.contains(note.id) {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                
                KBNoteCardView(
                    note: note,
                    members: members,
                    searchQuery: searchQuery
                )
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: !isSelecting) {
            if !isSelecting {
                Button(role: .destructive) {
                    delete(note)
                } label: {
                    Label("Elimina", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: !isSelecting) {
            if !isSelecting {
                Button {
                    togglePin(note)
                } label: {
                    Label(
                        pinnedIds.contains(note.id) ? "Rimuovi" : "In evidenza",
                        systemImage: pinnedIds.contains(note.id) ? "pin.slash" : "pin"
                    )
                }
                .tint(.orange)
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
        SyncCenter.shared.enqueueNoteDelete(noteId: note.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    private func deleteSelected() {
        guard !selectedIds.isEmpty else { return }
        let toDelete = notes.filter { selectedIds.contains($0.id) }
        
        for note in toDelete {
            note.isDeleted = true
            note.syncState = .pendingDelete
            note.lastSyncError = nil
            pinnedIds.remove(note.id)
        }
        
        try? modelContext.save()
        savePinned()
        
        for note in toDelete {
            SyncCenter.shared.enqueueNoteDelete(
                noteId: note.id,
                familyId: familyId,
                modelContext: modelContext
            )
        }
        
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        selectedIds = []
        isSelecting = false
    }
    
    private func togglePin(_ note: KBNote) {
        if pinnedIds.contains(note.id) {
            pinnedIds.remove(note.id)
        } else {
            pinnedIds.insert(note.id)
        }
        savePinned()
    }
    
    // MARK: - Pin persistence
    
    private var pinnedKey: String { "kb.notes.pinned.\(familyId)" }
    
    private func loadPinned() {
        pinnedIds = Set(UserDefaults.standard.stringArray(forKey: pinnedKey) ?? [])
    }
    
    private func savePinned() {
        UserDefaults.standard.set(Array(pinnedIds), forKey: pinnedKey)
    }
}

// MARK: - Empty state

private struct NotesEmptyStateView: View {
    let onNewNote: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 52)).foregroundStyle(.secondary)
            Text("Nessuna nota").font(.title3).fontWeight(.semibold)
            Text("Crea la prima nota della famiglia\ntoccando il tasto in alto a destra.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { onNewNote() } label: {
                Label("Nuova nota", systemImage: "square.and.pencil")
                    .font(.subheadline).fontWeight(.medium)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.accentColor).foregroundStyle(.white).clipShape(Capsule())
            }
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - No results state

private struct NotesNoResultsView: View {
    let query: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Nessun risultato").font(.title3).fontWeight(.semibold)
            Text("Nessuna nota contiene \"\(query)\"")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
