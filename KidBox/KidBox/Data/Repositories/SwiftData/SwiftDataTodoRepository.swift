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
final class SwiftDataTodoRepository: TodoRepository {
    
    // MARK: - Dependencies
    private let context: ModelContext
    
    init(context: ModelContext) { self.context = context }
    
    // MARK: - Queries
    
    /// Returns a preview list of undated, open todos (backlog) limited to `limit`.
    func listUndatedOpenTodos(familyId: String, childId: String, limit: Int) throws -> [KBTodoItem] {
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
        return try context.fetch(descriptor)
    }
    
    // MARK: - Commands
    
    func createTodo(_ todo: KBTodoItem) throws {
        KBLog.data.debug("Create todo id=\(todo.id, privacy: .public)")
        context.insert(todo)
        try context.save()
    }
    
    func updateTodo(_ todo: KBTodoItem) throws {
        KBLog.data.debug("Update todo id=\(todo.id, privacy: .public)")
        todo.updatedAt = Date()
        try context.save()
    }
    
    func softDeleteTodo(_ todo: KBTodoItem, updatedBy: String) throws {
        KBLog.data.debug("Soft delete todo id=\(todo.id, privacy: .public)")
        todo.isDeleted = true
        todo.updatedBy = updatedBy
        todo.updatedAt = Date()
        try context.save()
    }
}
