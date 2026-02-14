//
//  LocalDataWiper.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftData
import Foundation
internal import os

/// Models che espongono un `familyId` utilizzabile nei predicate SwiftData.
protocol HasFamilyId {
    var familyId: String { get }
}

/// Wipe locale (SwiftData + file cache) quando l’utente lascia una famiglia.
/// - Important:
///   - Nessun `print`.
///   - Log solo a fine operazione e in caso di errore (quando chiamato dal service).
///   - Non cambia la logica: stessa sequenza di delete + save + wipe filesystem.
enum LocalDataWiper {
    
    // MARK: - Leave family (local only)
    
    /// Elimina TUTTI i dati locali associati a `familyId` (solo locale).
    /// Usato tipicamente dopo "leave family" (server-side) o per cleanup locale.
    @MainActor
    static func wipeFamily(
        familyId: String,
        context: ModelContext
    ) throws {
        
        let fid = familyId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fid.isEmpty else { return }
        
        do {
            // Leaf entities
            try delete(KBDocument.self, familyId: fid, context: context)
            try delete(KBDocumentCategory.self, familyId: fid, context: context)
            
            try delete(KBRoutineCheck.self, familyId: fid, context: context)
            try delete(KBRoutine.self, familyId: fid, context: context)
            
            try delete(KBTodoItem.self, familyId: fid, context: context)
            try delete(KBEvent.self, familyId: fid, context: context)
            try delete(KBCustodySchedule.self, familyId: fid, context: context)
            
            try delete(KBFamilyMember.self, familyId: fid, context: context)
            
            // Children (relationship-based)
            try deleteChildren(familyId: fid, context: context)
            
            // Root
            try deleteFamily(familyId: fid, context: context)
            
            try context.save()
            
            // Filesystem cache
            try wipeLocalFiles(familyId: fid)
            
            KBLog.persistence.info("Local wipe completed for familyId=\(fid, privacy: .public)")
        } catch {
            KBLog.persistence.error("Local wipe failed for familyId=\(fid, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    // MARK: - Typed deletes (NO cast)
    
    /// Cancella tutte le entità `T` con `familyId == ...`
    @MainActor
    private static func delete<T: PersistentModel & HasFamilyId>(
        _ type: T.Type,
        familyId: String,
        context: ModelContext
    ) throws {
        let fid = familyId
        let desc = FetchDescriptor<T>(
            predicate: #Predicate { $0.familyId == fid }
        )
        let items = try context.fetch(desc)
        items.forEach { context.delete($0) }
    }
    
    /// Wipe totale di TUTTO il DB locale (dev/debug/reset).
    @MainActor
    static func wipeAll(context: ModelContext) throws {
        do {
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
        } catch {
            KBLog.persistence.error("Local FULL wipe failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    // MARK: - Helpers
    
    /// Cancella tutte le entità che matchano un predicate (helper generico).
    @MainActor
    private static func delete<T: PersistentModel>(
        where predicate: Predicate<T>,
        context: ModelContext
    ) throws {
        let items = try context.fetch(FetchDescriptor(predicate: predicate))
        items.forEach { context.delete($0) }
    }
    
    /// Cancella TUTTE le entità di un tipo (helper generico).
    @MainActor
    private static func deleteAll<T: PersistentModel>(
        _ type: T.Type,
        context: ModelContext
    ) throws {
        let items = try context.fetch(FetchDescriptor<T>())
        items.forEach { context.delete($0) }
    }
    
    /// Children: delete relationship-based (evita cast e rispetta il grafo SwiftData).
    @MainActor
    private static func deleteChildren(
        familyId: String,
        context: ModelContext
    ) throws {
        let fid = familyId
        let desc = FetchDescriptor<KBFamily>(
            predicate: #Predicate { $0.id == fid }
        )
        guard let family = try context.fetch(desc).first else { return }
        
        family.children.forEach { context.delete($0) }
        family.children.removeAll()
    }
    
    /// Root family delete.
    @MainActor
    private static func deleteFamily(
        familyId: String,
        context: ModelContext
    ) throws {
        let fid = familyId
        let desc = FetchDescriptor<KBFamily>(
            predicate: #Predicate { $0.id == fid }
        )
        try context.fetch(desc).forEach { context.delete($0) }
    }
    
    // MARK: - Filesystem
    
    /// Elimina la cache locale dei documenti (DocumentLocalCache) per `familyId`.
    private static func wipeLocalFiles(familyId: String) throws {
        let base = try DocumentLocalCache.baseDir()
        let dir = base.appendingPathComponent(familyId, isDirectory: true)
        
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
    }
}
