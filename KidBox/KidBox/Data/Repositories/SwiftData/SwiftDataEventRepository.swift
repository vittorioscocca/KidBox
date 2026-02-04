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
final class SwiftDataEventRepository: EventRepository {
    
    // MARK: - Dependencies
    private let context: ModelContext
    
    init(context: ModelContext) { self.context = context }
    
    // MARK: - Queries
    
    /// Returns the next upcoming event starting at or after `from`.
    func nextEvent(familyId: String, childId: String, from: Date) throws -> KBEvent? {
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
        return try context.fetch(descriptor).first
    }
    
    /// Returns all events in the current week interval for the provided `calendar`.
    func listEventsThisWeek(familyId: String, childId: String, from: Date, calendar: Calendar = .current) throws -> [KBEvent] {
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: from))!
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
        return try context.fetch(descriptor)
    }
    
    // MARK: - Commands
    
    func createEvent(_ event: KBEvent) throws {
        KBLog.data.debug("Create event id=\(event.id, privacy: .public)")
        context.insert(event)
        try context.save()
    }
    
    func updateEvent(_ event: KBEvent) throws {
        KBLog.data.debug("Update event id=\(event.id, privacy: .public)")
        event.updatedAt = Date()
        try context.save()
    }
    
    func softDeleteEvent(_ event: KBEvent, updatedBy: String) throws {
        KBLog.data.debug("Soft delete event id=\(event.id, privacy: .public)")
        event.isDeleted = true
        event.updatedBy = updatedBy
        event.updatedAt = Date()
        try context.save()
    }
}
