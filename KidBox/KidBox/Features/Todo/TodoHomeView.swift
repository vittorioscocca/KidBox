//
//  TodoHomeView.swift
//  KidBox
//
//  Created by vscocca on 25/02/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct TodoHomeView: View {
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    // Family/Child attivi
    @Query(sort: \KBFamily.updatedAt, order: .reverse)
    private var families: [KBFamily]
    
    // Liste Todo
    @Query(sort: \KBTodoList.createdAt, order: .forward)
    private var allLists: [KBTodoList]
    
    @Query(sort: \KBTodoItem.updatedAt, order: .reverse)
    private var allTodos: [KBTodoItem]
    
    private var visibleTodos: [KBTodoItem] {
        guard !familyId.isEmpty, !childId.isEmpty else { return [] }
        return allTodos.filter {
            $0.familyId == familyId &&
            $0.childId == childId &&
            !$0.isDeleted
        }
    }
    
    private var todayCount: Int {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? now
        
        return visibleTodos.filter { t in
            guard !t.isDone, let due = t.dueAt else { return false }
            return due >= start && due < end
        }.count
    }
    
    private var allCount: Int {
        visibleTodos.filter { !$0.isDone }.count
    }
    
    private var assignedToMeCount: Int {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        return visibleTodos.filter { !$0.isDone && $0.assignedTo == uid }.count
    }
    
    private var completedCount: Int {
        visibleTodos.filter { $0.isDone }.count
    }
    
    private var notCompletedCount: Int {
        visibleTodos.filter { !$0.isDone }.count
    }
    
    private var notAssignedToMeCount: Int {
        let uid = Auth.auth().currentUser?.uid ?? ""
        return visibleTodos.filter {
            !$0.isDone && $0.assignedTo != uid
        }.count
    }
    
    // UI state create/edit list
    @State private var showListEditor = false
    @State private var listNameDraft = ""
    @State private var editingListId: String? = nil
    
    // ✅ Sync
    @State private var didStartRealtime = false
    private let remote = TodoRemoteStore()
    
    private var activeFamily: KBFamily? { families.first }
    private var activeChild: KBChild? { activeFamily?.children.first }
    
    private var familyId: String { activeFamily?.id ?? "" }
    private var childId: String { activeChild?.id ?? "" }
    
    private var visibleLists: [KBTodoList] {
        guard !familyId.isEmpty, !childId.isEmpty else { return [] }
        return allLists.filter { $0.familyId == familyId && $0.childId == childId && !$0.isDeleted }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                cardsSection
                listsSection
            }
            .padding()
        }
        .navigationTitle("To-Do")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingListId = nil
                    listNameDraft = ""
                    showListEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nuova lista")
            }
        }
        .onAppear {
            startRealtimeIfNeeded()
        }
        .onDisappear {
            SyncCenter.shared.stopTodoListRealtime()
            SyncCenter.shared.stopTodoRealtime()
            didStartRealtime = false
        }
        .sheet(isPresented: $showListEditor) {
            listEditorSheet
        }
    }
    
    // MARK: - Realtime
    
    private func startRealtimeIfNeeded() {
        guard !didStartRealtime, !familyId.isEmpty, !childId.isEmpty else { return }
        didStartRealtime = true
        SyncCenter.shared.startTodoListRealtime(
            familyId: familyId,
            childId: childId,
            modelContext: modelContext,
            remote: remote
        )
        // ✅ Avvia il listener dei todo per aggiornare i contatori in realtime.
        // Viene anche riavviato da TodoListView.onDisappear al ritorno dalla lista.
        SyncCenter.shared.startTodoRealtime(
            familyId: familyId,
            childId: childId,
            modelContext: modelContext,
            remote: remote
        )
    }
    
    // MARK: - Cards
    
    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Panoramica")
                .font(.headline)
            
            let fid = familyId
            let cid = childId
            
            HStack(spacing: 12) {
                card(
                    title: "Oggi",
                    count: todayCount,
                    icon: "calendar",
                    tint: .orange
                ) {
                    coordinator.navigate(to: .todoSmart(familyId: fid, childId: cid, kind: .today))
                }
                
                card(
                    title: "Tutti",
                    count: allCount,
                    icon: "list.bullet",
                    tint: .blue
                ) {
                    coordinator.navigate(to: .todoSmart(familyId: fid, childId: cid, kind: .all))
                }
            }
            
            HStack(spacing: 12) {
                card(
                    title: "Assegnati a me",
                    count: assignedToMeCount,
                    icon: "person.fill.checkmark",
                    tint: .teal
                ) {
                    coordinator.navigate(to: .todoSmart(familyId: fid, childId: cid, kind: .assignedToMe))
                }
                
                card(
                    title: "Completati",
                    count: completedCount,
                    icon: "checkmark.seal.fill",
                    tint: .green
                ) {
                    coordinator.navigate(to: .todoSmart(familyId: fid, childId: cid, kind: .completed))
                }
            }
            
            HStack(spacing: 12) {
                card(
                    title: "Non assegnati a me",
                    count: notAssignedToMeCount,
                    icon: "person.crop.circle.badge.xmark",
                    tint: .purple
                ) {
                    coordinator.navigate(to: .todoSmart(familyId: fid, childId: cid, kind: .notAssignedToMe))
                }
                
                card(
                    title: "Non completati",
                    count: notCompletedCount,
                    icon: "circle",
                    tint: .red
                ) {
                    coordinator.navigate(to: .todoSmart(familyId: fid, childId: cid, kind: .notCompleted))
                }
            }
        }
    }
    
    private func card(
        title: String,
        count: Int,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(tint)
                    
                    Spacer()
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(tint)
                            )
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
                
                Text(title)
                    .font(.headline)
                
                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Lists
    
    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Le mie liste")
                .font(.headline)
            
            if familyId.isEmpty || childId.isEmpty {
                Text("Crea o unisciti a una famiglia per usare i To-Do.")
                    .foregroundStyle(.secondary)
            } else if visibleLists.isEmpty {
                Text("Nessuna lista")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(visibleLists) { list in
                        Button {
                            coordinator.navigate(
                                to: .todoList(familyId: list.familyId, childId: list.childId, listId: list.id)
                            )
                        } label: {
                            HStack {
                                Image(systemName: "list.bullet")
                                    .foregroundStyle(.secondary)
                                Text(list.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.systemGray6))
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Modifica") {
                                editingListId = list.id
                                listNameDraft = list.name
                                showListEditor = true
                            }
                            Button("Elimina", role: .destructive) {
                                deleteList(list)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var listEditorSheet: some View {
        NavigationStack {
            Form {
                TextField("Nome lista", text: $listNameDraft)
            }
            .navigationTitle(editingListId == nil ? "Nuova lista" : "Modifica lista")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { saveList() }
                        .disabled(listNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        showListEditor = false
                        editingListId = nil
                        listNameDraft = ""
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    
    private func saveList() {
        guard !familyId.isEmpty, !childId.isEmpty else { return }
        
        let name = listNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        let listId: String
        
        if let eid = editingListId,
           let list = visibleLists.first(where: { $0.id == eid }) {
            // modifica esistente
            list.name = name
            list.updatedAt = Date()
            listId = list.id
        } else {
            // nuova lista
            let list = KBTodoList(
                familyId: familyId,
                childId: childId,
                name: name
            )
            modelContext.insert(list)
            listId = list.id
        }
        
        try? modelContext.save()
        
        // ✅ Sync remoto
        SyncCenter.shared.enqueueTodoListUpsert(listId: listId, familyId: familyId, modelContext: modelContext)
        Task { await SyncCenter.shared.flush(modelContext: modelContext, remote: remote) }
        
        showListEditor = false
        self.editingListId = nil
        self.listNameDraft = ""
    }
    
    private func deleteList(_ list: KBTodoList) {
        let listId = list.id
        let fid = familyId
        
        // 🔹 1) Trova tutti i todo collegati
        let desc = FetchDescriptor<KBTodoItem>(
            predicate: #Predicate {
                $0.familyId == fid &&
                $0.childId == childId &&
                $0.listId == listId &&
                $0.isDeleted == false
            }
        )
        
        let todosToDelete = (try? modelContext.fetch(desc)) ?? []
        
        // 🔹 2) Soft delete todos
        for todo in todosToDelete {
            todo.isDeleted = true
            todo.syncState = .pendingDelete
            todo.lastSyncError = nil
            
            SyncCenter.shared.enqueueTodoDelete(
                todoId: todo.id,
                familyId: fid,
                modelContext: modelContext
            )
        }
        
        // 🔹 3) Soft delete lista
        list.isDeleted = true
        try? modelContext.save()
        
        // 🔹 4) Sync lista
        SyncCenter.shared.enqueueTodoListDelete(
            listId: listId,
            familyId: fid,
            modelContext: modelContext
        )
        
        Task {
            await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
        }
    }
}
