//
//  SyncCenter+Grocery.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import Foundation
import SwiftData
import FirebaseAuth
internal import FirebaseFirestoreInternal

// MARK: - Grocery realtime + outbox integration

extension SyncCenter {
    
    private var groceryRemote: GroceryRemoteStore { GroceryRemoteStore() }
    
    // MARK: - Listener lifecycle
    
    func startGroceryRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startGroceryRealtime familyId=\(familyId)")
        stopGroceryRealtime()
        
        groceryListener = groceryRemote.listenGroceries(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                self.applyGroceryInbound(changes: changes, familyId: familyId, modelContext: modelContext)
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "groceries", error: err)
                    }
                }
            }
        )
    }
    
    func stopGroceryRealtime() {
        if groceryListener != nil {
            KBLog.sync.kbInfo("stopGroceryRealtime")
        }
        groceryListener?.remove()
        groceryListener = nil
    }
    
    // MARK: - Outbox helpers
    
    func enqueueGroceryUpsert(itemId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueGroceryUpsert familyId=\(familyId) itemId=\(itemId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.grocery.rawValue,
            entityId: itemId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    func enqueueGroceryDelete(itemId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueGroceryDelete familyId=\(familyId) itemId=\(itemId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.grocery.rawValue,
            entityId: itemId,
            opType: "delete",
            modelContext: modelContext
        )
    }
    
    // MARK: - Flush handler
    // Chiamato da process(op:) in SyncCenter quando entityType == "grocery"
    
    func processGrocery(op: KBSyncOp, modelContext: ModelContext) async throws {
        let iid = op.entityId
        let desc = FetchDescriptor<KBGroceryItem>(predicate: #Predicate { $0.id == iid })
        let item = try? modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let item else { return }
            item.syncState = .pendingUpsert
            item.lastSyncError = nil
            try? modelContext.save()
            
            try await groceryRemote.upsert(item: item)
            
            item.syncState = .synced
            item.lastSyncError = nil
            try modelContext.save()
            
        case "delete":
            try await groceryRemote.softDelete(itemId: iid, familyId: op.familyId)
            
            if let item {
                KBLog.sync.kbInfo("[grocery][outbound] delete OK -> HARD DELETE local id=\(item.id)")
                modelContext.delete(item)
                try? modelContext.save()
            }
            
        default:
            throw NSError(domain: "KidBox.Sync", code: -2300,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for grocery: \(op.opType)"])
        }
    }
    
    // MARK: - Inbound apply (LWW)
    
    func applyGroceryInbound(
        changes: [GroceryRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("[grocery][inbound] applying changes=\(changes.count) familyId=\(familyId)")
        
        do {
            for change in changes {
                switch change {
                    
                case .upsert(let dto):
                    // Soft-delete remoto
                    if dto.isDeleted {
                        let pid = dto.id
                        let desc = FetchDescriptor<KBGroceryItem>(predicate: #Predicate { $0.id == pid })
                        if let existing = try modelContext.fetch(desc).first {
                            KBLog.sync.kbInfo("[grocery][inbound] remote isDeleted -> DELETE local id=\(dto.id)")
                            modelContext.delete(existing)
                        }
                        continue
                    }
                    
                    let pid = dto.id
                    let desc = FetchDescriptor<KBGroceryItem>(predicate: #Predicate { $0.id == pid })
                    
                    if let existing = try modelContext.fetch(desc).first {
                        // Anti-resurrect
                        if existing.isDeleted || existing.syncState == .pendingDelete {
                            KBLog.sync.kbDebug("[grocery][inbound] IGNORE (anti-resurrect) id=\(dto.id)")
                            continue
                        }
                        
                        let remoteTs = dto.updatedAt ?? Date.distantPast
                        let localTs  = existing.updatedAt
                        
                        guard remoteTs >= localTs else {
                            KBLog.sync.kbDebug("[grocery][inbound] IGNORE remote<local id=\(dto.id)")
                            continue
                        }
                        
                        existing.name        = dto.name
                        existing.category    = dto.category
                        existing.notes       = dto.notes
                        existing.isPurchased = dto.isPurchased
                        existing.isDeleted   = false
                        existing.purchasedAt = dto.purchasedAt
                        existing.purchasedBy = dto.purchasedBy
                        existing.updatedAt   = remoteTs
                        if let ub = dto.updatedBy, !ub.isEmpty { existing.updatedBy = ub }
                        existing.syncState   = .synced
                        existing.lastSyncError = nil
                        
                        KBLog.sync.kbDebug("[grocery][inbound] UPDATED id=\(dto.id)")
                        
                    } else {
                        // Crea nuovo
                        let now = dto.updatedAt ?? Date()
                        let item = KBGroceryItem(
                            id: dto.id,
                            familyId: dto.familyId,
                            name: dto.name,
                            category: dto.category,
                            notes: dto.notes,
                            isPurchased: dto.isPurchased,
                            purchasedAt: dto.purchasedAt,
                            purchasedBy: dto.purchasedBy,
                            isDeleted: false,
                            createdAt: now,
                            updatedAt: now,
                            updatedBy: dto.updatedBy,
                            createdBy: dto.createdBy
                        )
                        item.syncState = .synced
                        modelContext.insert(item)
                        KBLog.sync.kbDebug("[grocery][inbound] CREATED id=\(dto.id)")
                    }
                    
                case .remove(let id):
                    let pid = id
                    let desc = FetchDescriptor<KBGroceryItem>(predicate: #Predicate { $0.id == pid })
                    if let existing = try modelContext.fetch(desc).first {
                        KBLog.sync.kbInfo("[grocery][inbound] remove -> DELETE local id=\(id)")
                        modelContext.delete(existing)
                    }
                }
            }
            
            try modelContext.save()
            KBLog.sync.kbDebug("[grocery][inbound] SAVE OK")
            
        } catch {
            KBLog.sync.kbError("[grocery][inbound] APPLY FAIL err=\(error.localizedDescription)")
        }
    }
}
