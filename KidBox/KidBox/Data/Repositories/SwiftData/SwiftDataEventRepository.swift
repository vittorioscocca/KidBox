//
//  SwiftDataEventRepository.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData
import OSLog

/// SwiftData-backed implementation of `EventRepository`.
///
/// This repository is **local-first** and operates only on the provided `ModelContext`.
/// It exposes query helpers (read) and commands (write) for `KBEvent` entities.
///
/// Notes:
/// - Uses `familyId` + `childId` scoping for all queries.
/// - Uses `isDeleted` for soft-deletion filtering.
/// - Does **not** perform any remote sync by itself (that stays in SyncCenter / remote stores).
final class SwiftDataEventRepository: EventRepository {
    
    // MARK: - Dependencies
    
    /// SwiftData context used for fetch/insert/save operations.
    private let context: ModelContext
    
    /// Creates a repository bound to a specific SwiftData `ModelContext`.
    init(context: ModelContext) {
        self.context = context
        KBLog.data.kbDebug("SwiftDataEventRepository init")
    }
    
    // MARK: - Queries
    
    /// Returns the next upcoming event starting at or after `from`.
    ///
    /// Behavior (unchanged):
    /// - Filters by `familyId`, `childId`, `isDeleted == false`.
    /// - Returns the first event ordered by `startAt` with `fetchLimit = 1`.
    func nextEvent(familyId: String, childId: String, from: Date) throws -> KBEvent? {
        KBLog.data.kbDebug("nextEvent start familyId=\(familyId) childId=\(childId)")
        
        var descriptor = FetchDescriptor<KBEvent>(
            predicate: #Predicate {
                $0.familyId == familyId &&
                $0.childId == childId &&
                $0.isDeleted == false &&
                $0.startAt >= from
            },
            sortBy: [SortDescriptor(\.startAt)]
        )
        descriptor.fetchLimit = 1
        
        let item = try context.fetch(descriptor).first
        KBLog.data.kbDebug("nextEvent done found=\(item != nil)")
        return item
    }
    
    /// Returns all events in the current week interval for the provided `calendar`.
    ///
    /// Behavior (unchanged):
    /// - Week range = `[startOfWeek, endOfWeek)`.
    /// - Filters by `familyId`, `childId`, `isDeleted == false` and `startAt` range.
    /// - Sorted by `startAt` ascending.
    func listEventsThisWeek(
        familyId: String,
        childId: String,
        from: Date,
        calendar: Calendar = .current
    ) throws -> [KBEvent] {
        KBLog.data.kbDebug("listEventsThisWeek start familyId=\(familyId) childId=\(childId)")
        
        let startOfWeek = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: from)
        )!
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
        
        let descriptor = FetchDescriptor<KBEvent>(
            predicate: #Predicate {
                $0.familyId == familyId &&
                $0.childId == childId &&
                $0.isDeleted == false &&
                $0.startAt >= startOfWeek &&
                $0.startAt < endOfWeek
            },
            sortBy: [SortDescriptor(\.startAt)]
        )
        
        let items = try context.fetch(descriptor)
        KBLog.data.kbDebug("listEventsThisWeek done count=\(items.count)")
        return items
    }
    
    // MARK: - Commands
    
    /// Inserts a new event and persists it.
    ///
    /// Behavior (unchanged):
    /// - Inserts into the context.
    /// - Saves the context.
    func createEvent(_ event: KBEvent) throws {
        KBLog.data.kbInfo("createEvent id=\(event.id)")
        context.insert(event)
        try context.save()
        KBLog.data.kbDebug("createEvent saved id=\(event.id)")
    }
    
    /// Persists changes to an existing event and updates `updatedAt`.
    ///
    /// Behavior (unchanged):
    /// - Sets `updatedAt = Date()`.
    /// - Saves the context.
    func updateEvent(_ event: KBEvent) throws {
        KBLog.data.kbInfo("updateEvent id=\(event.id)")
        event.updatedAt = Date()
        try context.save()
        KBLog.data.kbDebug("updateEvent saved id=\(event.id)")
    }
    
    /// Marks an event as deleted (soft delete) and persists it.
    ///
    /// Behavior (unchanged):
    /// - Sets `isDeleted = true`.
    /// - Sets `updatedBy` and `updatedAt = Date()`.
    /// - Saves the context.
    func softDeleteEvent(_ event: KBEvent, updatedBy: String) throws {
        KBLog.data.kbInfo("softDeleteEvent id=\(event.id)")
        event.isDeleted = true
        event.updatedBy = updatedBy
        event.updatedAt = Date()
        try context.save()
        KBLog.data.kbDebug("softDeleteEvent saved id=\(event.id)")
    }
}
