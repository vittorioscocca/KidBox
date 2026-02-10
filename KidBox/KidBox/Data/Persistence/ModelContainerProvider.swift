//
//  ModelContainerProvider.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData
import OSLog

/// Creates and configures the SwiftData `ModelContainer` for KidBox.
///
/// - Important: KidBox uses a local-first database. Server sync will be handled separately
///   (e.g. Firestore) by a SyncEngine layer.
/// - Parameter inMemory: Use `true` for previews/tests.
enum ModelContainerProvider {
    
    /// Builds a `ModelContainer` containing all KidBox SwiftData models.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        KBLog.persistence.info("Creating ModelContainer (inMemory: \(inMemory))")
        
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
        
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            KBLog.persistence.info("ModelContainer created successfully")
            return container
        } catch {
            KBLog.persistence.fault("ModelContainer creation failed: \(error.localizedDescription, privacy: .public)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
