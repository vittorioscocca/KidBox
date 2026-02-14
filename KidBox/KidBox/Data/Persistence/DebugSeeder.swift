//
//  DebugSeeder.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// Seeds the local SwiftData store with a minimal dataset for development.
///
/// The seed is idempotent:
/// - If at least one `KBFamily` already exists, seeding is skipped.
/// - This allows relaunching the app without duplicating debug data.
///
/// Scope:
/// - DEBUG builds only.
/// - Creates:
///     - 1 family
///     - 1 child (via relationship)
///     - 3 routines
///     - 2 todos
///     - 1 calendar event
///
/// - Important:
///   This must never run in production builds.
enum DebugSeeder {
    
    /// Seeds debug data if the database is empty.
    ///
    /// - Parameter context: SwiftData `ModelContext`.
    static func seedIfNeeded(context: ModelContext) {
#if DEBUG
        KBLog.persistence.kbInfo("DEBUG seed check started")
        
        do {
            let existingFamilies = try context.fetch(FetchDescriptor<KBFamily>())
            
            guard existingFamilies.isEmpty else {
                KBLog.persistence.kbDebug("Seed skipped (family already exists)")
                return
            }
            
            KBLog.persistence.kbInfo("No families found, creating debug seed data")
            
            let userId = "debug-user"
            let now = Date()
            
            // MARK: - Family
            
            let family = KBFamily(
                id: UUID().uuidString,
                name: "Famiglia Rossi",
                createdBy: userId,
                updatedBy: userId,
                createdAt: now,
                updatedAt: now
            )
            
            KBLog.persistence.kbDebug("Family created (in-memory)")
            
            // MARK: - Child (relationship-based)
            
            let child = KBChild(
                id: UUID().uuidString,
                familyId: family.id,
                name: "Sofia",
                birthDate: nil,
                createdBy: userId,
                createdAt: now,
                updatedBy: userId,
                updatedAt: now
            )
            
            family.children.append(child)
            KBLog.persistence.kbDebug("Child appended to family")
            
            // Insert only root when using relationships
            context.insert(family)
            
            // MARK: - Routines (ordered)
            
            context.insert(KBRoutine(
                familyId: family.id,
                childId: child.id,
                title: "Preparare latte",
                sortOrder: 0,
                updatedBy: userId
            ))
            
            context.insert(KBRoutine(
                familyId: family.id,
                childId: child.id,
                title: "Vitamina",
                sortOrder: 1,
                updatedBy: userId
            ))
            
            context.insert(KBRoutine(
                familyId: family.id,
                childId: child.id,
                title: "Borsa nido",
                sortOrder: 2,
                updatedBy: userId
            ))
            
            KBLog.persistence.kbDebug("Routines inserted")
            
            // MARK: - Todos
            
            context.insert(KBTodoItem(
                familyId: family.id,
                childId: child.id,
                title: "Comprare pannolini",
                updatedBy: userId
            ))
            
            context.insert(KBTodoItem(
                familyId: family.id,
                childId: child.id,
                title: "Prenotare pediatra",
                updatedBy: userId
            ))
            
            KBLog.persistence.kbDebug("Todo items inserted")
            
            // MARK: - Event (tomorrow 09:00)
            
            let cal = Calendar.current
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
            let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            
            context.insert(KBEvent(
                familyId: family.id,
                childId: child.id,
                type: "nido",
                title: "Nido",
                startAt: start,
                notes: nil,
                updatedBy: userId
            ))
            
            KBLog.persistence.kbDebug("Event inserted")
            
            try context.save()
            
            KBLog.persistence.kbInfo("DEBUG seed created successfully (familyId=\(family.id))")
            
        } catch {
            KBLog.persistence.kbError("DEBUG seed failed: \(error.localizedDescription)")
        }
#endif
    }
}
