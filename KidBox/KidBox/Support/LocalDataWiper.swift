//
//  LocalDataWiper.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftData
import OSLog

protocol HasFamilyId {
    var familyId: String { get }
}

enum LocalDataWiper {
    
    // MARK: - Leave family (local only)
    
    @MainActor
    static func wipeFamily(
        familyId: String,
        context: ModelContext
    ) throws {
        
        // Leaf entities
        try delete(KBDocument.self, familyId: familyId, context: context)
        try delete(KBDocumentCategory.self, familyId: familyId, context: context)
        
        try delete(KBRoutineCheck.self, familyId: familyId, context: context)
        try delete(KBRoutine.self, familyId: familyId, context: context)
        
        try delete(KBTodoItem.self, familyId: familyId, context: context)
        try delete(KBEvent.self, familyId: familyId, context: context)
        try delete(KBCustodySchedule.self, familyId: familyId, context: context)
        
        try delete(KBFamilyMember.self, familyId: familyId, context: context)
        
        // Children (relationship-based)
        try deleteChildren(familyId: familyId, context: context)
        
        // Root
        try deleteFamily(familyId: familyId, context: context)
        
        try context.save()
        
        try wipeLocalFiles(familyId: familyId)
        
        KBLog.persistence.info("Local wipe completed for familyId=\(familyId)")
    }
    
    // MARK: - Typed deletes (NO cast)
    
    @MainActor
    private static func delete<T: PersistentModel & HasFamilyId>(
        _ type: T.Type,
        familyId: String,
        context: ModelContext
    ) throws {
        let desc = FetchDescriptor<T>(
            predicate: #Predicate { $0.familyId == familyId }
        )
        let items = try context.fetch(desc)
        items.forEach { context.delete($0) }
    }
    
    @MainActor
    static func wipeAll(context: ModelContext) throws {
        
        try deleteAll(KBDocument.self, context: context)
        try deleteAll(KBDocumentCategory.self, context: context)
        
        try deleteAll(KBRoutineCheck.self, context: context)
        try deleteAll(KBRoutine.self, context: context)
        
        try deleteAll(KBTodoItem.self, context: context)
        try deleteAll(KBEvent.self, context: context)
        try deleteAll(KBCustodySchedule.self, context: context)
        
        try deleteAll(KBChild.self, context: context)
        try deleteAll(KBFamilyMember.self, context: context)
        try deleteAll(KBFamily.self, context: context)
        
        try deleteAll(KBUserProfile.self, context: context)
        
        try context.save()
        
        KBLog.persistence.info("Local FULL wipe completed")
    }
    
    // MARK: - Helpers
    
    @MainActor
    private static func delete<T: PersistentModel>(
        where predicate: Predicate<T>,
        context: ModelContext
    ) throws {
        let items = try context.fetch(FetchDescriptor(predicate: predicate))
        items.forEach { context.delete($0) }
    }
    
    @MainActor
    private static func deleteAll<T: PersistentModel>(
        _ type: T.Type,
        context: ModelContext
    ) throws {
        let items = try context.fetch(FetchDescriptor<T>())
        items.forEach { context.delete($0) }
    }
    
    @MainActor
    private static func deleteChildren(
        familyId: String,
        context: ModelContext
    ) throws {
        let desc = FetchDescriptor<KBFamily>(
            predicate: #Predicate { $0.id == familyId }
        )
        guard let family = try context.fetch(desc).first else { return }
        
        family.children.forEach { context.delete($0) }
        family.children.removeAll()
    }
    
    @MainActor
    private static func deleteFamily(
        familyId: String,
        context: ModelContext
    ) throws {
        let desc = FetchDescriptor<KBFamily>(
            predicate: #Predicate { $0.id == familyId }
        )
        try context.fetch(desc).forEach { context.delete($0) }
    }
    
    // MARK: - Filesystem
    
    private static func wipeLocalFiles(familyId: String) throws {
        let base = try DocumentLocalCache.baseDir()
        let dir = base.appendingPathComponent(familyId, isDirectory: true)
        
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
    }
}
