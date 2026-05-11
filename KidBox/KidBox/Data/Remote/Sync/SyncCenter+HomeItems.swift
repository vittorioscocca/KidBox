//
//  SyncCenter+HomeItems.swift
//  KidBox
//
//  Created by vscocca on 11/05/26.
//

import Foundation
import SwiftData
internal import FirebaseFirestoreInternal

// MARK: - Home items realtime + outbox

extension SyncCenter {

    func startHomeItemsRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startHomeItemsRealtime familyId=\(familyId)")
        stopHomeItemsRealtime()

        homeItemListener = homeItemRemote.listenHomeItems(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyHomeItemsInbound(changes: changes, familyId: familyId, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "homeItems", error: err)
                    }
                }
            }
        )
    }

    func stopHomeItemsRealtime() {
        if homeItemListener != nil {
            KBLog.sync.kbInfo("stopHomeItemsRealtime")
        }
        homeItemListener?.remove()
        homeItemListener = nil
    }

    func enqueueHomeItemUpsert(itemId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueHomeItemUpsert familyId=\(familyId) itemId=\(itemId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.homeItem.rawValue,
            entityId: itemId,
            opType: "upsert",
            modelContext: modelContext
        )
    }

    func enqueueHomeItemDelete(itemId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueHomeItemDelete familyId=\(familyId) itemId=\(itemId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.homeItem.rawValue,
            entityId: itemId,
            opType: "delete",
            modelContext: modelContext
        )
    }

    func processHomeItem(op: KBSyncOp, modelContext: ModelContext) async throws {
        let iid = op.entityId
        let desc = FetchDescriptor<KBHomeItem>(predicate: #Predicate { $0.id == iid })
        let item = try? modelContext.fetch(desc).first

        switch op.opType {
        case "upsert":
            guard let item else { return }
            item.syncState = .pendingUpsert
            item.lastSyncError = nil
            try? modelContext.save()

            try await homeItemRemote.upsert(item: item)

            item.syncState = .synced
            item.lastSyncError = nil
            try modelContext.save()

        case "delete":
            try await homeItemRemote.softDelete(itemId: iid, familyId: op.familyId)

            if let item {
                KBLog.sync.kbInfo("[homeItem][outbound] delete OK -> HARD DELETE local id=\(item.id)")
                modelContext.delete(item)
                try? modelContext.save()
            }

        default:
            throw NSError(domain: "KidBox.Sync", code: -2410,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for homeItem: \(op.opType)"])
        }
    }

    func applyHomeItemsInbound(
        changes: [HomeItemRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("[homeItem][inbound] applying changes=\(changes.count) familyId=\(familyId)")

        do {
            for change in changes {
                switch change {

                case .upsert(let dto):
                    if dto.isDeleted {
                        let iid = dto.id
                        let desc = FetchDescriptor<KBHomeItem>(predicate: #Predicate { $0.id == iid })
                        if let existing = try modelContext.fetch(desc).first {
                            KBLog.sync.kbInfo("[homeItem][inbound] remote isDeleted -> DELETE local id=\(dto.id)")
                            modelContext.delete(existing)
                        }
                        continue
                    }

                    let iid = dto.id
                    let desc = FetchDescriptor<KBHomeItem>(predicate: #Predicate { $0.id == iid })

                    if let existing = try modelContext.fetch(desc).first {
                        if existing.isDeleted || existing.syncState == .pendingDelete {
                            KBLog.sync.kbDebug("[homeItem][inbound] IGNORE (anti-resurrect) id=\(dto.id)")
                            continue
                        }

                        let remoteTs = dto.updatedAt ?? Date.distantPast
                        let localTs = existing.updatedAt

                        guard remoteTs >= localTs else {
                            KBLog.sync.kbDebug("[homeItem][inbound] IGNORE remote<local id=\(dto.id)")
                            continue
                        }

                        existing.name = dto.name
                        existing.categoryRaw = dto.categoryRaw
                        existing.brand = dto.brand
                        existing.model = dto.model
                        existing.serialNumber = dto.serialNumber
                        existing.purchaseDate = dto.purchaseDate
                        existing.warrantyExpiryDate = dto.warrantyExpiryDate
                        existing.nextServiceDate = dto.nextServiceDate
                        existing.servicePeriodMonths = dto.servicePeriodMonths
                        existing.notes = dto.notes
                        existing.isDeleted = false
                        existing.reminderEnabled = dto.reminderEnabled
                        existing.updatedAt = remoteTs
                        if let ub = dto.updatedBy, !ub.isEmpty { existing.updatedBy = ub }
                        if let cb = dto.createdBy, !cb.isEmpty { existing.createdBy = cb }
                        existing.syncState = .synced
                        existing.lastSyncError = nil

                        KBLog.sync.kbDebug("[homeItem][inbound] UPDATED id=\(dto.id)")

                    } else {
                        let now = dto.updatedAt ?? Date()
                        let createdAt = dto.createdAt ?? now
                        let row = KBHomeItem(
                            id: dto.id,
                            familyId: dto.familyId,
                            name: dto.name,
                            categoryRaw: dto.categoryRaw,
                            brand: dto.brand,
                            model: dto.model,
                            serialNumber: dto.serialNumber,
                            purchaseDate: dto.purchaseDate,
                            warrantyExpiryDate: dto.warrantyExpiryDate,
                            nextServiceDate: dto.nextServiceDate,
                            servicePeriodMonths: dto.servicePeriodMonths,
                            notes: dto.notes,
                            isDeleted: false,
                            createdAt: createdAt,
                            updatedAt: now,
                            createdBy: dto.createdBy ?? "",
                            updatedBy: dto.updatedBy ?? "",
                            reminderEnabled: dto.reminderEnabled,
                            reminderId: nil
                        )
                        row.syncState = .synced
                        modelContext.insert(row)
                        KBLog.sync.kbDebug("[homeItem][inbound] CREATED id=\(dto.id)")
                    }

                case .remove(let id):
                    let iid = id
                    let desc = FetchDescriptor<KBHomeItem>(predicate: #Predicate { $0.id == iid })
                    if let existing = try modelContext.fetch(desc).first {
                        KBLog.sync.kbInfo("[homeItem][inbound] remove -> DELETE local id=\(id)")
                        modelContext.delete(existing)
                    }
                }
            }

            try modelContext.save()
            KBLog.sync.kbDebug("[homeItem][inbound] SAVE OK")

        } catch {
            KBLog.sync.kbError("[homeItem][inbound] APPLY FAIL err=\(error.localizedDescription)")
        }
    }
}
