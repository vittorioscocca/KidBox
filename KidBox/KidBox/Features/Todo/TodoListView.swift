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
    @StateObject private var syncer = TodoRealtimeSyncer()
    
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
        // placeholder: verrà ricalcolato in body via re-init? No.
        // Quindi: usiamo init(familyId:childId:) + factory sotto.
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
        
        // Se questa view è stata costruita senza ids, la ricostruiamo correttamente
        // (così puoi continuare a navigare a .todo senza passare parametri in giro)
        if familyId.isEmpty || childId.isEmpty {
            return AnyView(
                TodoListViewFactory(family: family, child: child)
            )
        }
        
        return AnyView(
            content
        )
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
                            Button("Entra con codice") {
                                coordinator.navigate(to: .joinFamily)
                            }
                            Button("Impostazioni Family") {
                                coordinator.navigate(to: .familySettings)
                            }
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
                                Text(todo.title)
                                    .foregroundStyle(.primary)
                                Spacer()
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
            syncer.start(familyId: familyId, childId: childId, modelContext: modelContext)
        }
        .onDisappear {
            syncer.stop()
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
        
        // 1) Local
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
        modelContext.insert(local)
        
        do {
            try modelContext.save()
            newTitle = ""
        } catch {
            errorMessage = "SwiftData save failed: \(error.localizedDescription)"
            return
        }
        
        // 2) Remote (MVP: no rollback)
        do {
            try await remote.upsert(todo: .init(
                id: id,
                familyId: familyId,
                childId: childId,
                title: title,
                isDone: false
            ))
        } catch {
            errorMessage = "Firestore write failed: \(error.localizedDescription)"
        }
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
        
        do {
            try modelContext.save()
        } catch {
            errorMessage = "SwiftData save failed: \(error.localizedDescription)"
            return
        }
        
        do {
            try await remote.upsert(todo: .init(
                id: todo.id,
                familyId: todo.familyId,
                childId: todo.childId,
                title: todo.title,
                isDone: todo.isDone
            ))
        } catch {
            errorMessage = "Firestore update failed: \(error.localizedDescription)"
        }
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
                
                // MVP: non cancelliamo fisicamente, soft-delete
                do {
                    try await remote.softDelete(todoId: todo.id, familyId: todo.familyId)
                } catch {
                    // non blocco
                    KBLog.sync.error("Remote softDelete failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            
            do {
                try modelContext.save()
            } catch {
                errorMessage = "SwiftData save failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Factory che ricrea la view con i parametri giusti
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
