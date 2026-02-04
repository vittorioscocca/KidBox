//
//  Protocols.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation

/// Defines operations for managing routines and their daily completion events.
///
/// - Note: Routine completion is modeled as append-only events (`KBRoutineCheck`)
///   to reduce sync conflicts between parents.
protocol RoutineRepository {
    func listActiveRoutines(familyId: String, childId: String) throws -> [KBRoutine]
    func createRoutine(_ routine: KBRoutine) throws
    func updateRoutine(_ routine: KBRoutine) throws
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
protocol TodoRepository {
    func listUndatedOpenTodos(familyId: String, childId: String, limit: Int) throws -> [KBTodoItem]
    func createTodo(_ todo: KBTodoItem) throws
    func updateTodo(_ todo: KBTodoItem) throws
    func softDeleteTodo(_ todo: KBTodoItem, updatedBy: String) throws
}

/// Defines operations for managing dated events (calendar).
protocol EventRepository {
    func nextEvent(familyId: String, childId: String, from: Date) throws -> KBEvent?
    
    /// Returns events within the current week (based on provided calendar).
    func listEventsThisWeek(
        familyId: String,
        childId: String,
        from: Date,
        calendar: Calendar
    ) throws -> [KBEvent]
    
    func createEvent(_ event: KBEvent) throws
    func updateEvent(_ event: KBEvent) throws
    func softDeleteEvent(_ event: KBEvent, updatedBy: String) throws
}
