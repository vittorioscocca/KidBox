//
//  SyncCenter+ShoppingTrips.swift
//  KidBox
//
//  Realtime e outbox delle spese fatte, sulla falsariga della lista spesa da
//  cui nascono.
//

import Foundation
import SwiftData
import FirebaseAuth
internal import FirebaseFirestoreInternal

extension SyncCenter {

    private var shoppingTripRemote: ShoppingTripRemoteStore { ShoppingTripRemoteStore() }

    // MARK: - Listener

    func startShoppingTripsRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startShoppingTripsRealtime familyId=\(familyId)")
        stopShoppingTripsRealtime()

        shoppingTripListener = shoppingTripRemote.listenShoppingTrips(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                self.applyShoppingTripInbound(changes: changes, familyId: familyId, modelContext: modelContext)
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "shoppingTrips", error: err)
                    }
                }
            }
        )
    }

    func stopShoppingTripsRealtime() {
        shoppingTripListener?.remove()
        shoppingTripListener = nil
    }

    // MARK: - Outbox

    func enqueueShoppingTripUpsert(tripId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.shoppingTrip.rawValue,
            entityId: tripId,
            opType: "upsert",
            modelContext: modelContext
        )
    }

    func enqueueShoppingTripDelete(tripId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.shoppingTrip.rawValue,
            entityId: tripId,
            opType: "delete",
            modelContext: modelContext
        )
    }

    func processShoppingTrip(op: KBSyncOp, modelContext: ModelContext) async throws {
        let tid = op.entityId
        let desc = FetchDescriptor<KBShoppingTrip>(predicate: #Predicate { $0.id == tid })
        let trip = try? modelContext.fetch(desc).first

        switch op.opType {
        case "upsert":
            guard let trip else { return }
            trip.syncState = .pendingUpsert
            trip.lastSyncError = nil
            try? modelContext.save()

            try await shoppingTripRemote.upsert(trip: trip)

            trip.syncState = .synced
            trip.lastSyncError = nil
            try modelContext.save()

        case "delete":
            try await shoppingTripRemote.softDelete(tripId: tid, familyId: op.familyId)
            if let trip {
                modelContext.delete(trip)
                try? modelContext.save()
            }

        default:
            throw NSError(domain: "KidBox.Sync", code: -2400,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for shoppingTrip: \(op.opType)"])
        }
    }

    // MARK: - Inbound (LWW)

    func applyShoppingTripInbound(
        changes: [ShoppingTripRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("[shoppingTrip][inbound] applying changes=\(changes.count) familyId=\(familyId)")

        do {
            for change in changes {
                switch change {
                case .upsert(let dto):
                    let tid = dto.id
                    let desc = FetchDescriptor<KBShoppingTrip>(predicate: #Predicate { $0.id == tid })
                    let existing = try modelContext.fetch(desc).first

                    if dto.isDeleted {
                        if let existing { modelContext.delete(existing) }
                        continue
                    }

                    if let existing {
                        // Anti-resurrect: quello che sta uscendo di scena resta fuori.
                        if existing.isDeleted || existing.syncState == .pendingDelete { continue }
                        guard (dto.updatedAt ?? .distantPast) >= existing.updatedAt else { continue }

                        existing.storeName       = dto.storeName
                        existing.total           = dto.total
                        existing.date            = dto.date
                        existing.linesJson       = dto.linesJson
                        existing.notes           = dto.notes
                        existing.linkedExpenseId = dto.linkedExpenseId
                        existing.updatedAt       = dto.updatedAt ?? Date()
                        existing.updatedBy       = dto.updatedBy
                        existing.syncState       = .synced
                    } else {
                        let trip = KBShoppingTrip(
                            id: dto.id,
                            familyId: dto.familyId,
                            storeName: dto.storeName,
                            total: dto.total,
                            date: dto.date,
                            notes: dto.notes,
                            linkedExpenseId: dto.linkedExpenseId,
                            createdAt: dto.updatedAt ?? Date(),
                            updatedAt: dto.updatedAt ?? Date(),
                            updatedBy: dto.updatedBy,
                            createdBy: dto.createdBy
                        )
                        trip.linesJson = dto.linesJson
                        trip.syncState = .synced
                        modelContext.insert(trip)
                    }

                case .remove(let id):
                    let desc = FetchDescriptor<KBShoppingTrip>(predicate: #Predicate { $0.id == id })
                    if let existing = try modelContext.fetch(desc).first {
                        modelContext.delete(existing)
                    }
                }
            }

            try modelContext.save()
            KBLog.sync.kbDebug("[shoppingTrip][inbound] SAVE OK")
        } catch {
            KBLog.sync.kbError("[shoppingTrip][inbound] FAILED err=\(error.localizedDescription)")
        }
    }
}
