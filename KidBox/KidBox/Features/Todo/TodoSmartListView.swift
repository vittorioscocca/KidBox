//
//  TodoSmartListView.swift
//  KidBox
//
//  Created by vscocca on 25/02/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct TodoSmartListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query private var todos: [KBTodoItem]
    @Query private var members: [KBFamilyMember]
    
    private let remote = TodoRemoteStore()
    private let familyId: String
    private let childId: String
    private let kind: TodoSmartKind
    
    @State private var didStartRealtime = false
    @State private var showEditSheet = false
    @State private var editingTodoId: String? = nil
    @State private var showDeleteAllCompletedAlert = false
    
    init(familyId: String, childId: String, kind: TodoSmartKind) {
        self.familyId = familyId
        self.childId = childId
        self.kind = kind
        
        // ✅ Query base: semplice, il compiler non impazzisce
        _todos = Query(
            filter: #Predicate<KBTodoItem> { t in
                t.familyId == familyId &&
                t.childId == childId &&
                t.isDeleted == false
            },
            sort: [SortDescriptor(\KBTodoItem.updatedAt, order: .reverse)]
        )
    }
    
    // MARK: - Filtro Swift per kind
    
    private var filteredTodos: [KBTodoItem] {
        let me = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? now
        
        switch kind {
        case .all:
            return todos
            
        case .today:
            return todos.filter { t in
                guard !t.isDone, let due = t.dueAt else { return false }
                return due >= startOfDay && due < endOfDay
            }
            
        case .assignedToMe:
            return todos.filter { t in
                !t.isDone && t.assignedTo == me
            }
            
        case .notAssignedToMe:
            return todos.filter { t in
                !t.isDone && t.assignedTo != me
            }
            
        case .completed:
            return todos.filter { $0.isDone }
            
        case .notCompleted:
            return todos.filter { !$0.isDone }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        List {
            if filteredTodos.isEmpty {
                Text("Nessun elemento")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredTodos) { todo in
                    row(todo)
                }
                .onDelete(perform: deleteTodos)
            }
        }
        .navigationTitle(title)
        .toolbar {
            if kind != .completed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingTodoId = nil
                        showEditSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteAllCompletedAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(filteredTodos.isEmpty)
                }
            }
        }
        .alert("Elimina completati", isPresented: $showDeleteAllCompletedAlert) {
            Button("Elimina", role: .destructive) {
                deleteAllCompleted()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Vuoi eliminare tutti i to-do completati? L'operazione non è reversibile.")
        }
        .sheet(isPresented: $showEditSheet) {
            TodoEditView(
                familyId: familyId,
                childId: childId,
                listId: "",
                todoIdToEdit: editingTodoId
            )
        }
        .onAppear {
            guard !didStartRealtime else { return }
            didStartRealtime = true
            
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
    
    // MARK: - Helpers
    
    private var title: String {
        switch kind {
        case .today:            return "Oggi"
        case .all:              return "Tutti"
        case .assignedToMe:     return "Assegnati a me"
        case .completed:        return "Completati"
        case .notAssignedToMe:  return "Non assegnati a me"
        case .notCompleted:     return "Non Completati"
        }
    }
    
    private func row(_ todo: KBTodoItem) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await toggleDone(todo) }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    if let name = displayName(for: todo.assignedTo) {
                        Label(name, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let due = todo.dueAt {
                        Text(due.formatted(.dateTime.day().month().hour().minute()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if (todo.priorityRaw ?? 0) == 1 {
                        Text("Urgente")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.2)))
                            .foregroundStyle(.red)
                    }
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingTodoId = todo.id
            showEditSheet = true
        }
    }
    
    private func displayName(for uid: String?) -> String? {
        guard let uid else { return nil }
        return members.first(where: { $0.userId == uid })?.displayName
    }
    
    @MainActor
    private func toggleDone(_ todo: KBTodoItem) async {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        todo.isDone.toggle()
        todo.updatedBy = uid
        todo.updatedAt = now
        todo.doneAt = todo.isDone ? now : nil
        todo.doneBy = todo.isDone ? uid : nil
        todo.syncState = .pendingUpsert
        
        try? modelContext.save()
        
        SyncCenter.shared.enqueueTodoUpsert(todoId: todo.id, familyId: familyId, modelContext: modelContext)
        await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
    }
    
    private func deleteAllCompleted() {
        Task { @MainActor in
            let uid = Auth.auth().currentUser?.uid ?? "local"
            let now = Date()
            
            for todo in filteredTodos {
                todo.isDeleted = true
                todo.updatedBy = uid
                todo.updatedAt = now
                todo.syncState = .pendingDelete
                todo.lastSyncError = nil
                
                SyncCenter.shared.enqueueTodoDelete(todoId: todo.id, familyId: familyId, modelContext: modelContext)
            }
            
            try? modelContext.save()
            await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
        }
    }
    
    private func deleteTodos(offsets: IndexSet) {
        Task { @MainActor in
            let uid = Auth.auth().currentUser?.uid ?? "local"
            
            for i in offsets {
                let todo = filteredTodos[i]
                todo.isDeleted = true
                todo.updatedBy = uid
                todo.syncState = .pendingDelete
                
                SyncCenter.shared.enqueueTodoDelete(todoId: todo.id, familyId: familyId, modelContext: modelContext)
            }
            
            try? modelContext.save()
            await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
        }
    }
}
