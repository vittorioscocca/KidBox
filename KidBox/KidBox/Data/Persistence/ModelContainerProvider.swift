//
//  ModelContainerProvider.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// Creates and configures the SwiftData `ModelContainer` for KidBox.
///
/// KidBox is local-first:
/// - SwiftData provides the on-device persistence layer.
/// - Remote sync (Firestore/Storage) is handled separately by the sync layer.
///
/// Use cases:
/// - App runtime (persistent store on disk)
/// - Previews/tests (optional in-memory store)
enum ModelContainerProvider {
    
    /// Builds a `ModelContainer` containing all KidBox SwiftData models.
    ///
    /// - Parameter inMemory: Use `true` for previews/tests to avoid writing to disk.
    /// - Returns: Configured `ModelContainer`.
    ///
    /// - Important:
    ///   This must succeed for the app to run. On failure the app terminates with `fatalError`.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        KBLog.persistence.kbInfo("Creating ModelContainer inMemory=\(inMemory)")
        
        // Schema includes all persisted models used by the app.
        let schema = Schema([
            KBFamily.self,
            KBFamilyMember.self,
            KBChild.self,
            KBRoutine.self,
            KBRoutineCheck.self,
            KBEvent.self,
            KBTodoItem.self,
            KBCustodySchedule.self,
            KBUserProfile.self,
            KBDocument.self,
            KBDocumentCategory.self,
            KBSyncOp.self
        ])
        
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            KBLog.persistence.kbInfo("ModelContainer created successfully")
            return container
        } catch {
            KBLog.persistence.kbError("ModelContainer creation failed: \(error.localizedDescription)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
