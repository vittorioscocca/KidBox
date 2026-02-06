//
//  TodoListView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import OSLog

struct TodoListView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    // Family “attiva” deterministica
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    
    // Query todos (dinamica via init)
    @Query private var todos: [KBTodoItem]
    
    @State private var newTitle: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    
    private let remote = TodoRemoteStore()
    private let familyId: String
    private let childId: String
    
    init() {
        self.familyId = ""
        self.childId = ""
        _todos = Query(filter: #Predicate<KBTodoItem> { _ in false })
    }
    
    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId = childId
        
        _todos = Query(
            filter: #Predicate<KBTodoItem> { todo in
                todo.familyId == familyId &&
                todo.childId == childId &&
                todo.isDeleted == false
            },
            sort: [SortDescriptor(\KBTodoItem.createdAt, order: .reverse)]
        )
    }
    
    var body: some View {
        let family = families.first
        let child = family?.children.first
        
        if familyId.isEmpty || childId.isEmpty {
            return AnyView(TodoListViewFactory(family: family, child: child))
        }
        
        return AnyView(content)
    }
    
    private var content: some View {
        Form {
            Section {
                if familyId.isEmpty || childId.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Non sei ancora in una famiglia.")
                            .font(.headline)
                        Text("Entra con un codice oppure crea una famiglia dalle impostazioni.")
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Button("Entra con codice") { coordinator.navigate(to: .joinFamily) }
                            Button("Impostazioni Family") { coordinator.navigate(to: .familySettings) }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Es. Comprare pannolini", text: $newTitle)
                        
                        Button(isSaving ? "Salvataggio…" : "Aggiungi") {
                            Task { await addTodo() }
                        }
                        .disabled(isSaving || newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } header: {
                Text("Aggiungi")
            }
            
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            
            Section("Todo") {
                if todos.isEmpty {
                    Text("Nessun todo")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(todos) { todo in
                        Button {
                            Task { await toggleDone(todo) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(todo.title).foregroundStyle(.primary)
                                    
                                    if todo.syncState != .synced {
                                        Text(syncLabel(for: todo))
                                            .font(.caption)
                                            .foregroundStyle(todo.syncState == .error ? .red : .secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: syncIcon(for: todo))
                                    .foregroundStyle(todo.syncState == .error ? .red : .secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteTodos)
                }
            }
        }
        .navigationTitle("Todo")
        .onAppear {
            guard !familyId.isEmpty, !childId.isEmpty else { return }
            
            SyncCenter.shared.startTodoRealtime(
                familyId: familyId,
                childId: childId,
                modelContext: modelContext,
                remote: remote
            )
            
            Task { await SyncCenter.shared.flush(modelContext: modelContext, remote: remote) }
        }
        .onDisappear {
            SyncCenter.shared.stopTodoRealtime()
        }
    }
    
    // MARK: - Actions
    
    @MainActor
    private func addTodo() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID().uuidString
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        let local = KBTodoItem(
            id: id,
            familyId: familyId,
            childId: childId,
            title: title,
            notes: nil,
            dueAt: nil,
            isDone: false,
            doneAt: nil,
            doneBy: nil,
            updatedBy: uid,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        
        local.syncState = .pendingUpsert
        local.lastSyncError = nil
        
        modelContext.insert(local)
        
        do {
            try modelContext.save()
            newTitle = ""
        } catch {
            errorMessage = "SwiftData save failed: \(error.localizedDescription)"
            return
        }
        
        SyncCenter.shared.enqueueTodoUpsert(todoId: id, familyId: familyId, modelContext: modelContext)
        await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
    }
    
    @MainActor
    private func toggleDone(_ todo: KBTodoItem) async {
        errorMessage = nil
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        todo.isDone.toggle()
        todo.updatedBy = uid
        todo.updatedAt = now
        todo.doneAt = todo.isDone ? now : nil
        todo.doneBy = todo.isDone ? uid : nil
        
        todo.syncState = .pendingUpsert
        todo.lastSyncError = nil
        
        do {
            try modelContext.save()
        } catch {
            errorMessage = "SwiftData save failed: \(error.localizedDescription)"
            return
        }
        
        SyncCenter.shared.enqueueTodoUpsert(todoId: todo.id, familyId: todo.familyId, modelContext: modelContext)
        await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
    }
    
    private func deleteTodos(offsets: IndexSet) {
        Task { @MainActor in
            errorMessage = nil
            let uid = Auth.auth().currentUser?.uid ?? "local"
            let now = Date()
            
            for index in offsets {
                let todo = todos[index]
                
                todo.isDeleted = true
                todo.updatedBy = uid
                todo.updatedAt = now
                
                todo.syncState = .pendingDelete
                todo.lastSyncError = nil
                
                SyncCenter.shared.enqueueTodoDelete(todoId: todo.id, familyId: todo.familyId, modelContext: modelContext)
            }
            
            do {
                try modelContext.save()
            } catch {
                errorMessage = "SwiftData save failed: \(error.localizedDescription)"
                return
            }
            
            await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
        }
    }
    
    private func syncIcon(for todo: KBTodoItem) -> String {
        switch todo.syncState {
        case .synced: return "checkmark"
        case .pendingUpsert, .pendingDelete: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle"
        }
    }
    
    private func syncLabel(for todo: KBTodoItem) -> String {
        switch todo.syncState {
        case .synced:
            return "Sincronizzato"
        case .pendingUpsert:
            return "In sincronizzazione…"
        case .pendingDelete:
            return "Eliminazione in corso…"
        case .error:
            return todo.lastSyncError ?? "Errore di sincronizzazione"
        }
    }
}

private struct TodoListViewFactory: View {
    let family: KBFamily?
    let child: KBChild?
    
    var body: some View {
        if let family, let child {
            TodoListView(familyId: family.id, childId: child.id)
        } else {
            TodoListView(familyId: "", childId: "")
        }
    }
}
