//
//  SwiftDataRoutineRepository.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData
import OSLog

/// SwiftData-backed implementation of `RoutineRepository`.
///
/// This repository is **local-first** and persists routines and routine checks in SwiftData.
/// Remote sync (Firestore/outbox) is handled elsewhere (e.g. `SyncCenter`).
///
/// Key behaviors:
/// - Queries always scope by `familyId` + `childId`.
/// - Soft delete via `isDeleted`.
/// - Routine checks are **append-only** to reduce sync conflicts.
final class SwiftDataRoutineRepository: RoutineRepository {
    
    // MARK: - Dependencies
    
    /// SwiftData context used for fetch/insert/save operations.
    private let context: ModelContext
    
    /// Creates a repository bound to a specific SwiftData `ModelContext`.
    init(context: ModelContext) {
        self.context = context
        KBLog.data.kbDebug("SwiftDataRoutineRepository init")
    }
    
    // MARK: - Queries
    
    /// Returns active, non-deleted routines for a child, ordered by `sortOrder` then `title`.
    ///
    /// Behavior (unchanged):
    /// - Filters by `familyId`, `childId`, `isActive == true`, `isDeleted == false`.
    /// - Sorts by `sortOrder`, then `title`.
    func listActiveRoutines(familyId: String, childId: String) throws -> [KBRoutine] {
        KBLog.data.kbDebug("listActiveRoutines start familyId=\(familyId) childId=\(childId)")
        
        let descriptor = FetchDescriptor<KBRoutine>(
            predicate: #Predicate {
                $0.familyId == familyId &&
                $0.childId == childId &&
                $0.isActive == true &&
                $0.isDeleted == false
            },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.title)]
        )
        
        let items = try context.fetch(descriptor)
        KBLog.data.kbDebug("listActiveRoutines done count=\(items.count)")
        return items
    }
    
    // MARK: - Commands
    
    /// Inserts a new routine and persists it.
    ///
    /// Behavior (unchanged):
    /// - Inserts into the context.
    /// - Saves the context.
    func createRoutine(_ routine: KBRoutine) throws {
        KBLog.data.kbInfo("createRoutine id=\(routine.id)")
        context.insert(routine)
        try context.save()
        KBLog.data.kbDebug("createRoutine saved id=\(routine.id)")
    }
    
    /// Persists changes to an existing routine and refreshes `updatedAt`.
    ///
    /// Behavior (unchanged):
    /// - Sets `updatedAt = Date()`.
    /// - Saves the context.
    func updateRoutine(_ routine: KBRoutine) throws {
        KBLog.data.kbInfo("updateRoutine id=\(routine.id)")
        routine.updatedAt = Date()
        try context.save()
        KBLog.data.kbDebug("updateRoutine saved id=\(routine.id)")
    }
    
    /// Soft deletes a routine by marking `isDeleted = true` and persisting it.
    ///
    /// Behavior (unchanged):
    /// - Sets `isDeleted = true`.
    /// - Sets `updatedBy` and `updatedAt = Date()`.
    /// - Saves the context.
    func softDeleteRoutine(_ routine: KBRoutine, updatedBy: String) throws {
        KBLog.data.kbInfo("softDeleteRoutine id=\(routine.id)")
        routine.isDeleted = true
        routine.updatedBy = updatedBy
        routine.updatedAt = Date()
        try context.save()
        KBLog.data.kbDebug("softDeleteRoutine saved id=\(routine.id)")
    }
    
    /// Appends a completion event for a routine for a given day.
    ///
    /// This method is intentionally append-only to avoid conflicts during sync:
    /// if two parents check the same routine, both events can coexist without corruption.
    ///
    /// Behavior (unchanged):
    /// - Computes `dayKey` from `day`.
    /// - Inserts a new `KBRoutineCheck`.
    /// - Saves the context.
    func addRoutineCheck(
        familyId: String,
        childId: String,
        routineId: String,
        day: Date,
        checkedBy: String
    ) throws {
        let dayKey = day.kbDayKey()
        
        let check = KBRoutineCheck(
            familyId: familyId,
            childId: childId,
            routineId: routineId,
            dayKey: dayKey,
            checkedBy: checkedBy
        )
        
        KBLog.routine.kbInfo("addRoutineCheck routineId=\(routineId) dayKey=\(dayKey)")
        context.insert(check)
        try context.save()
        KBLog.routine.kbDebug("addRoutineCheck saved routineId=\(routineId) dayKey=\(dayKey)")
    }
}
