//
//  SyncCenter+DocumentsEvents.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import SwiftData

extension SyncCenter {
    
    // MARK: - Public enqueue (Documents)
    
    func enqueueDocumentUpsert(documentId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.document.rawValue,
            entityId: documentId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    func enqueueDocumentDelete(documentId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.document.rawValue,
            entityId: documentId,
            opType: "delete",
            modelContext: modelContext
        )
    }
    
    // MARK: - Public enqueue (Events)
    
    func enqueueEventUpsert(eventId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.event.rawValue,
            entityId: eventId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    func enqueueEventDelete(eventId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.event.rawValue,
            entityId: eventId,
            opType: "delete",
            modelContext: modelContext
        )
    }
    
    // MARK: - Process hooks (called by process(op:...))
    
    /// Call this inside `process(op:...)` when entityType == .document
    func processDocument(op: KBSyncOp, modelContext: ModelContext) async throws {
        // ⚠️ Serve un tuo RemoteStore, tipo DocumentRemoteStore.
        // Per ora: stub che non fa nulla ma permette di integrare senza rompere compilazione.
        //
        // Esempio (quando avrai il remote):
        // let remote = DocumentRemoteStore()
        // switch op.opType { case "upsert": ... case "delete": ... }
        
        throw NSError(
            domain: "KidBox.Sync",
            code: -2001,
            userInfo: [NSLocalizedDescriptionKey: "processDocument not implemented yet"]
        )
    }
    
    /// Call this inside `process(op:...)` when entityType == .event
    func processEvent(op: KBSyncOp, modelContext: ModelContext) async throws {
        // ⚠️ Serve un tuo RemoteStore, tipo EventRemoteStore.
        // Per ora: stub.
        
        throw NSError(
            domain: "KidBox.Sync",
            code: -2002,
            userInfo: [NSLocalizedDescriptionKey: "processEvent not implemented yet"]
        )
    }
}
