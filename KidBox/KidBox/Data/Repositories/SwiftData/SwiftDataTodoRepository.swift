//
//  SwiftDataTodoRepository.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData
import OSLog

/// SwiftData-backed implementation of `TodoRepository`.
///
/// This repository is **local-first** and persists todos in SwiftData.
/// Remote sync is handled elsewhere (e.g. SyncCenter / outbox).
///
/// Conventions:
/// - All queries are scoped by `familyId` + `childId`.
/// - Soft delete is implemented via `isDeleted`.
final class SwiftDataTodoRepository: TodoRepository {
    
    // MARK: - Dependencies
    
    /// SwiftData context used for fetch/insert/save operations.
    private let context: ModelContext
    
    /// Creates a repository bound to a specific SwiftData `ModelContext`.
    init(context: ModelContext) {
        self.context = context
        KBLog.data.kbDebug("SwiftDataTodoRepository init")
    }
    
    // MARK: - Queries
    
    /// Returns a preview list of undated, open todos (backlog) limited to `limit`.
    ///
    /// Behavior (unchanged):
    /// - Filters by `familyId`, `childId`, `isDeleted == false`, `isDone == false`, `dueAt == nil`.
    /// - Sorts by `createdAt` descending.
    /// - Applies `fetchLimit = limit`.
    func listUndatedOpenTodos(familyId: String, childId: String, limit: Int) throws -> [KBTodoItem] {
        KBLog.data.kbDebug("listUndatedOpenTodos start familyId=\(familyId) childId=\(childId) limit=\(limit)")
        
        var descriptor = FetchDescriptor<KBTodoItem>(
            predicate: #Predicate {
                $0.familyId == familyId &&
                $0.childId == childId &&
                $0.isDeleted == false &&
                $0.isDone == false &&
                $0.dueAt == nil
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        
        let items = try context.fetch(descriptor)
        KBLog.data.kbDebug("listUndatedOpenTodos done count=\(items.count)")
        return items
    }
    
    // MARK: - Commands
    
    /// Inserts a new todo and persists it.
    ///
    /// Behavior (unchanged):
    /// - Inserts into the context.
    /// - Saves the context.
    func createTodo(_ todo: KBTodoItem) throws {
        KBLog.data.kbInfo("createTodo id=\(todo.id)")
        context.insert(todo)
        try context.save()
        KBLog.data.kbDebug("createTodo saved id=\(todo.id)")
    }
    
    /// Persists changes to an existing todo and refreshes `updatedAt`.
    ///
    /// Behavior (unchanged):
    /// - Sets `updatedAt = Date()`.
    /// - Saves the context.
    func updateTodo(_ todo: KBTodoItem) throws {
        KBLog.data.kbInfo("updateTodo id=\(todo.id)")
        todo.updatedAt = Date()
        try context.save()
        KBLog.data.kbDebug("updateTodo saved id=\(todo.id)")
    }
    
    /// Soft deletes a todo by marking `isDeleted = true` and persisting it.
    ///
    /// Behavior (unchanged):
    /// - Sets `isDeleted = true`.
    /// - Sets `updatedBy` and `updatedAt = Date()`.
    /// - Saves the context.
    func softDeleteTodo(_ todo: KBTodoItem, updatedBy: String) throws {
        KBLog.data.kbInfo("softDeleteTodo id=\(todo.id)")
        todo.isDeleted = true
        todo.updatedBy = updatedBy
        todo.updatedAt = Date()
        try context.save()
        KBLog.data.kbDebug("softDeleteTodo saved id=\(todo.id)")
    }
}
