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
/// - Important: This repository persists data locally and is designed for local-first usage.
///   Server sync will be handled by a dedicated SyncEngine layer.
final class SwiftDataRoutineRepository: RoutineRepository {
    
    // MARK: - Dependencies
    private let context: ModelContext
    
    /// Creates a repository bound to a specific SwiftData `ModelContext`.
    init(context: ModelContext) {
        self.context = context
    }
    
    // MARK: - Queries
    
    /// Returns active, non-deleted routines for a child, ordered by `sortOrder`.
    func listActiveRoutines(familyId: String, childId: String) throws -> [KBRoutine] {
        let descriptor = FetchDescriptor<KBRoutine>(
            predicate: #Predicate {
                $0.familyId == familyId &&
                $0.childId == childId &&
                $0.isActive == true &&
                $0.isDeleted == false
            },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.title)]
        )
        return try context.fetch(descriptor)
    }
    
    // MARK: - Commands
    
    /// Inserts a new routine and saves the context.
    func createRoutine(_ routine: KBRoutine) throws {
        KBLog.data.debug("Create routine id=\(routine.id, privacy: .public)")
        context.insert(routine)
        try context.save()
    }
    
    /// Updates a routine in-place and saves the context.
    ///
    /// - Note: SwiftData tracks changes; this method mainly ensures `updatedAt` is refreshed.
    func updateRoutine(_ routine: KBRoutine) throws {
        KBLog.data.debug("Update routine id=\(routine.id, privacy: .public)")
        routine.updatedAt = Date()
        try context.save()
    }
    
    /// Soft deletes a routine by setting `isDeleted = true`.
    func softDeleteRoutine(_ routine: KBRoutine, updatedBy: String) throws {
        KBLog.data.debug("Soft delete routine id=\(routine.id, privacy: .public)")
        routine.isDeleted = true
        routine.updatedBy = updatedBy
        routine.updatedAt = Date()
        try context.save()
    }
    
    /// Appends a completion event for a routine for a given day.
    ///
    /// This method is intentionally append-only to avoid conflicts during sync:
    /// if two parents check the same routine, both events can coexist without corruption.
    func addRoutineCheck(familyId: String, childId: String, routineId: String, day: Date, checkedBy: String) throws {
        let dayKey = day.kbDayKey()
        let check = KBRoutineCheck(
            familyId: familyId,
            childId: childId,
            routineId: routineId,
            dayKey: dayKey,
            checkedBy: checkedBy
        )
        
        KBLog.routine.info("Add routine check routineId=\(routineId, privacy: .public) dayKey=\(dayKey, privacy: .public)")
        context.insert(check)
        try context.save()
    }
}
