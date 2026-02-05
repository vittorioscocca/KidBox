//
//  DebugSeeder.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData
import OSLog

/// Seeds the local SwiftData store with a minimal dataset for development.
///
/// The seed is idempotent: it will not run if at least one `KBFamily` exists.
/// This allows you to relaunch the app without duplicating data.
///
/// - Important: This is compiled and executed only in DEBUG builds.

enum DebugSeeder {
    
    static func seedIfNeeded(context: ModelContext) {
#if DEBUG
        do {
            let existingFamilies = try context.fetch(FetchDescriptor<KBFamily>())
            guard existingFamilies.isEmpty else {
                KBLog.persistence.debug("Seed skipped (family already exists)")
                return
            }
            
            let userId = "debug-user"
            let now = Date()
            
            // Family
            let family = KBFamily(
                id: UUID().uuidString,
                name: "Famiglia Rossi",
                createdBy: userId,
                updatedBy: userId,
                createdAt: now,
                updatedAt: now
            )
            
            // Child (relationship-based)
            let child = KBChild(
                id: UUID().uuidString,
                name: "Sofia",
                birthDate: nil,
                createdBy: userId,
                createdAt: now
            )
            
            family.children.append(child)
            
            // Insert ONLY the root (family) is enough when using relationships
            context.insert(family)
            
            // Routines / Todos / Events:
            // ⚠️ Qui devi decidere: questi modelli usano ancora familyId/childId string?
            // Se sì, continuiamo a popolarli con family.id e child.id come prima.
            
            // 3 routines (ordered)
            context.insert(KBRoutine(familyId: family.id, childId: child.id, title: "Preparare latte", sortOrder: 0, updatedBy: userId))
            context.insert(KBRoutine(familyId: family.id, childId: child.id, title: "Vitamina", sortOrder: 1, updatedBy: userId))
            context.insert(KBRoutine(familyId: family.id, childId: child.id, title: "Borsa nido", sortOrder: 2, updatedBy: userId))
            
            // 2 todos
            context.insert(KBTodoItem(familyId: family.id, childId: child.id, title: "Comprare pannolini", updatedBy: userId))
            context.insert(KBTodoItem(familyId: family.id, childId: child.id, title: "Prenotare pediatra", updatedBy: userId))
            
            // 1 event (tomorrow 09:00)
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
            
            try context.save()
            KBLog.persistence.info("DEBUG seed created (familyId=\(family.id, privacy: .public))")
            
        } catch {
            KBLog.persistence.error("DEBUG seed failed: \(error.localizedDescription, privacy: .public)")
        }
#endif
    }
}
