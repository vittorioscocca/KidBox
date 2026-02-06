//
//  TodoRealtimeSyncer.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import SwiftData
import FirebaseFirestore
import Combine
import OSLog

@MainActor
final class TodoRealtimeSyncer: ObservableObject {
    
    private let remote: TodoRemoteStore
    private var listener: ListenerRegistration?
    
    init(remote: TodoRemoteStore = TodoRemoteStore()) {
        self.remote = remote
    }
    
    func start(familyId: String, childId: String, modelContext: ModelContext) {
        stop()
        
        listener = remote.listenTodos(
            familyId: familyId,
            childId: childId
        ) { [weak self] changes in
            guard let self else { return }
            self.apply(changes: changes, modelContext: modelContext)
        }
    }
    
    func stop() {
        listener?.remove()
        listener = nil
    }
    
    deinit {
        listener?.remove()
    }
    
    // MARK: - Apply changes to SwiftData
    
    private func apply(changes: [TodoRemoteChange], modelContext: ModelContext) {
        do {
            for change in changes {
                switch change {
                case .upsert(let dto):
                    let todo = try fetchOrCreateTodo(id: dto.id, modelContext: modelContext)
                    todo.familyId = dto.familyId
                    todo.childId = dto.childId
                    todo.title = dto.title
                    todo.isDone = dto.isDone
                    todo.isDeleted = dto.isDeleted
                    todo.updatedAt = dto.updatedAt ?? todo.updatedAt
                    todo.updatedBy = dto.updatedBy ?? todo.updatedBy
                    
                case .remove(let id):
                    if let existing = try fetchTodo(id: id, modelContext: modelContext) {
                        modelContext.delete(existing)
                    }
                }
            }
            
            try modelContext.save()
        } catch {
            // qui puoi loggare, ma evita di spammare UI
            KBLog.sync.error("Realtime apply failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func fetchTodo(id: String, modelContext: ModelContext) throws -> KBTodoItem? {
        let pid = id
        let desc = FetchDescriptor<KBTodoItem>(predicate: #Predicate { $0.id == pid })
        return try modelContext.fetch(desc).first
    }
    
    private func fetchOrCreateTodo(id: String, modelContext: ModelContext) throws -> KBTodoItem {
        if let existing = try fetchTodo(id: id, modelContext: modelContext) {
            return existing
        }
        // valori placeholder: verranno sovrascritti dall’upsert
        let now = Date()
        let todo = KBTodoItem(
            id: id,
            familyId: "",
            childId: "",
            title: "",
            notes: nil,
            dueAt: nil,
            isDone: false,
            doneAt: nil,
            doneBy: nil,
            updatedBy: "remote",
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        modelContext.insert(todo)
        return todo
    }
}
