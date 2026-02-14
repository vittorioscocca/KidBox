//
//  Protocols.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation

/// Defines operations for managing routines and their daily completion events.
///
/// A routine is a reusable task (e.g. “vitamina”, “borsa nido”) that can be checked daily.
/// Completion is modeled as append-only events (`KBRoutineCheck`) to reduce sync conflicts
/// between multiple caregivers/devices.
///
/// Design notes:
/// - Repositories are local-first (typically SwiftData) and may be synced by a separate layer.
/// - “Undo/uncheck” is intentionally out of scope for MVP: checks are append-only.
protocol RoutineRepository {
    
    // MARK: - Queries
    
    /// Returns active, non-deleted routines for a given child.
    func listActiveRoutines(familyId: String, childId: String) throws -> [KBRoutine]
    
    // MARK: - Commands
    
    /// Persists a new routine.
    func createRoutine(_ routine: KBRoutine) throws
    
    /// Persists updates to an existing routine (typically refreshes `updatedAt`).
    func updateRoutine(_ routine: KBRoutine) throws
    
    /// Soft deletes a routine (marks as deleted instead of removing).
    func softDeleteRoutine(_ routine: KBRoutine, updatedBy: String) throws
    
    /// Creates a completion event for the given day (append-only).
    ///
    /// - Important: This should not toggle state; it adds an event.
    ///   Uncheck/undo is intentionally out of scope for MVP.
    func addRoutineCheck(
        familyId: String,
        childId: String,
        routineId: String,
        day: Date,
        checkedBy: String
    ) throws
}

/// Defines operations for managing shared todo items.
///
/// Todos are shared within a family/child scope and may optionally have a due date.
/// Deletions are typically modeled as soft deletes to remain sync-friendly.
protocol TodoRepository {
    
    // MARK: - Queries
    
    /// Returns a preview list of undated, open todos (backlog) limited to `limit`.
    func listUndatedOpenTodos(familyId: String, childId: String, limit: Int) throws -> [KBTodoItem]
    
    // MARK: - Commands
    
    /// Persists a new todo item.
    func createTodo(_ todo: KBTodoItem) throws
    
    /// Persists updates to an existing todo item (typically refreshes `updatedAt`).
    func updateTodo(_ todo: KBTodoItem) throws
    
    /// Soft deletes a todo item.
    func softDeleteTodo(_ todo: KBTodoItem, updatedBy: String) throws
}

/// Defines operations for managing dated events (calendar).
///
/// Events represent scheduled items (e.g. “pediatra”, “nido”) with a start date and optional end date.
/// Deletions are typically modeled as soft deletes to remain sync-friendly.
protocol EventRepository {
    
    // MARK: - Queries
    
    /// Returns the next upcoming event starting at or after `from`.
    func nextEvent(familyId: String, childId: String, from: Date) throws -> KBEvent?
    
    /// Returns events within the current week interval (based on the provided `calendar`).
    func listEventsThisWeek(
        familyId: String,
        childId: String,
        from: Date,
        calendar: Calendar
    ) throws -> [KBEvent]
    
    // MARK: - Commands
    
    /// Persists a new event.
    func createEvent(_ event: KBEvent) throws
    
    /// Persists updates to an existing event (typically refreshes `updatedAt`).
    func updateEvent(_ event: KBEvent) throws
    
    /// Soft deletes an event.
    func softDeleteEvent(_ event: KBEvent, updatedBy: String) throws
}
