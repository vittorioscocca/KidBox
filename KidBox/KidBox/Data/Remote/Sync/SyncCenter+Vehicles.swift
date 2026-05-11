//
//  SyncCenter+Vehicles.swift
//  KidBox
//
//  Created by vscocca on 11/05/26.
//

import Foundation
import SwiftData
internal import FirebaseFirestoreInternal

// MARK: - Vehicles + vehicle events realtime + outbox

extension SyncCenter {

    func startVehiclesRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startVehiclesRealtime familyId=\(familyId)")
        stopVehiclesRealtime()

        vehicleListener = vehicleRemote.listenVehicles(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    await self.applyVehiclesInbound(changes: changes, familyId: familyId, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "vehicles", error: err)
                    }
                }
            }
        )
    }

    func stopVehiclesRealtime() {
        if vehicleListener != nil {
            KBLog.sync.kbInfo("stopVehiclesRealtime")
        }
        vehicleListener?.remove()
        vehicleListener = nil
    }

    func startVehicleEventsRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startVehicleEventsRealtime familyId=\(familyId)")
        stopVehicleEventsRealtime()

        vehicleEventListener = vehicleEventRemote.listenVehicleEvents(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyVehicleEventsInbound(changes: changes, familyId: familyId, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "vehicleEvents", error: err)
                    }
                }
            }
        )
    }

    func stopVehicleEventsRealtime() {
        if vehicleEventListener != nil {
            KBLog.sync.kbInfo("stopVehicleEventsRealtime")
        }
        vehicleEventListener?.remove()
        vehicleEventListener = nil
    }

    func enqueueVehicleUpsert(vehicleId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueVehicleUpsert familyId=\(familyId) vehicleId=\(vehicleId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.vehicle.rawValue,
            entityId: vehicleId,
            opType: "upsert",
            modelContext: modelContext
        )
    }

    func enqueueVehicleDelete(vehicleId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueVehicleDelete familyId=\(familyId) vehicleId=\(vehicleId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.vehicle.rawValue,
            entityId: vehicleId,
            opType: "delete",
            modelContext: modelContext
        )
    }

    func enqueueVehicleEventUpsert(eventId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueVehicleEventUpsert familyId=\(familyId) eventId=\(eventId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.vehicleEvent.rawValue,
            entityId: eventId,
            opType: "upsert",
            modelContext: modelContext
        )
    }

    func enqueueVehicleEventDelete(eventId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueVehicleEventDelete familyId=\(familyId) eventId=\(eventId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.vehicleEvent.rawValue,
            entityId: eventId,
            opType: "delete",
            modelContext: modelContext
        )
    }

    func processVehicle(op: KBSyncOp, modelContext: ModelContext) async throws {
        let iid = op.entityId
        let desc = FetchDescriptor<KBVehicle>(predicate: #Predicate { $0.id == iid })
        let item = try? modelContext.fetch(desc).first

        switch op.opType {
        case "upsert":
            guard let item else { return }
            item.syncState = .pendingUpsert
            item.lastSyncError = nil
            try? modelContext.save()

            try await vehicleRemote.upsert(item: item)

            item.syncState = .synced
            item.lastSyncError = nil
            try modelContext.save()

        case "delete":
            try await vehicleRemote.softDelete(vehicleId: iid, familyId: op.familyId)

            if let item {
                KBLog.sync.kbInfo("[vehicle][outbound] delete OK -> HARD DELETE local id=\(item.id)")
                await VehicleReminderService.shared.cancelAll(vehicleId: item.id)
                modelContext.delete(item)
                try? modelContext.save()
            }

        default:
            throw NSError(domain: "KidBox.Sync", code: -2420,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for vehicle: \(op.opType)"])
        }
    }

    func processVehicleEvent(op: KBSyncOp, modelContext: ModelContext) async throws {
        let iid = op.entityId
        let desc = FetchDescriptor<KBVehicleEvent>(predicate: #Predicate { $0.id == iid })
        let item = try? modelContext.fetch(desc).first

        switch op.opType {
        case "upsert":
            guard let item else { return }
            item.syncState = .pendingUpsert
            item.lastSyncError = nil
            try? modelContext.save()

            try await vehicleEventRemote.upsert(item: item)

            item.syncState = .synced
            item.lastSyncError = nil
            try modelContext.save()

        case "delete":
            try await vehicleEventRemote.softDelete(eventId: iid, familyId: op.familyId)

            if let item {
                KBLog.sync.kbInfo("[vehicleEvent][outbound] delete OK -> HARD DELETE local id=\(item.id)")
                modelContext.delete(item)
                try? modelContext.save()
            }

        default:
            throw NSError(domain: "KidBox.Sync", code: -2421,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for vehicleEvent: \(op.opType)"])
        }
    }

    func applyVehiclesInbound(
        changes: [VehicleRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) async {
        KBLog.sync.kbDebug("[vehicle][inbound] applying changes=\(changes.count) familyId=\(familyId)")

        do {
            for change in changes {
                switch change {

                case .upsert(let dto):
                    if dto.isDeleted {
                        let vid = dto.id
                        await VehicleReminderService.shared.cancelAll(vehicleId: vid)
                        let desc = FetchDescriptor<KBVehicle>(predicate: #Predicate { $0.id == vid })
                        if let existing = try modelContext.fetch(desc).first {
                            KBLog.sync.kbInfo("[vehicle][inbound] remote isDeleted -> DELETE local id=\(dto.id)")
                            modelContext.delete(existing)
                        }
                        continue
                    }

                    let vid = dto.id
                    let desc = FetchDescriptor<KBVehicle>(predicate: #Predicate { $0.id == vid })

                    if let existing = try modelContext.fetch(desc).first {
                        if existing.isDeleted || existing.syncState == .pendingDelete {
                            KBLog.sync.kbDebug("[vehicle][inbound] IGNORE (anti-resurrect) id=\(dto.id)")
                            continue
                        }

                        let remoteTs = dto.updatedAt ?? Date.distantPast
                        let localTs = existing.updatedAt

                        guard remoteTs >= localTs else {
                            KBLog.sync.kbDebug("[vehicle][inbound] IGNORE remote<local id=\(dto.id)")
                            continue
                        }

                        existing.name = dto.name
                        existing.licensePlate = dto.licensePlate
                        existing.brand = dto.brand
                        existing.model = dto.model
                        existing.year = dto.year
                        existing.fuelTypeRaw = dto.fuelTypeRaw
                        existing.color = dto.color
                        existing.vin = dto.vin
                        existing.insuranceExpiryDate = dto.insuranceExpiryDate
                        existing.revisionExpiryDate = dto.revisionExpiryDate
                        existing.taxExpiryDate = dto.taxExpiryDate
                        existing.lastServiceDate = dto.lastServiceDate
                        existing.nextServiceDate = dto.nextServiceDate
                        existing.currentKm = dto.currentKm
                        existing.notes = dto.notes
                        existing.photoURL = dto.photoURL
                        existing.isDeleted = false
                        existing.reminderEnabled = dto.reminderEnabled
                        existing.updatedAt = remoteTs
                        if let ub = dto.updatedBy, !ub.isEmpty { existing.updatedBy = ub }
                        if let cb = dto.createdBy, !cb.isEmpty { existing.createdBy = cb }
                        existing.syncState = .synced
                        existing.lastSyncError = nil

                        KBLog.sync.kbDebug("[vehicle][inbound] UPDATED id=\(dto.id)")
                        await VehicleReminderService.shared.scheduleReminders(for: existing)

                    } else {
                        let now = dto.updatedAt ?? Date()
                        let createdAt = dto.createdAt ?? now
                        let row = KBVehicle(
                            id: dto.id,
                            familyId: dto.familyId,
                            name: dto.name,
                            licensePlate: dto.licensePlate,
                            brand: dto.brand,
                            model: dto.model,
                            year: dto.year,
                            fuelTypeRaw: dto.fuelTypeRaw,
                            color: dto.color,
                            vin: dto.vin,
                            insuranceExpiryDate: dto.insuranceExpiryDate,
                            revisionExpiryDate: dto.revisionExpiryDate,
                            taxExpiryDate: dto.taxExpiryDate,
                            lastServiceDate: dto.lastServiceDate,
                            nextServiceDate: dto.nextServiceDate,
                            currentKm: dto.currentKm,
                            notes: dto.notes,
                            photoURL: dto.photoURL,
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
                        KBLog.sync.kbDebug("[vehicle][inbound] CREATED id=\(dto.id)")
                        await VehicleReminderService.shared.scheduleReminders(for: row)
                    }

                case .remove(let id):
                    let vid = id
                    await VehicleReminderService.shared.cancelAll(vehicleId: vid)
                    let desc = FetchDescriptor<KBVehicle>(predicate: #Predicate { $0.id == vid })
                    if let existing = try modelContext.fetch(desc).first {
                        KBLog.sync.kbInfo("[vehicle][inbound] remove -> DELETE local id=\(id)")
                        modelContext.delete(existing)
                    }
                }
            }

            try modelContext.save()
            KBLog.sync.kbDebug("[vehicle][inbound] SAVE OK")

        } catch {
            KBLog.sync.kbError("[vehicle][inbound] APPLY FAIL err=\(error.localizedDescription)")
        }
    }

    func applyVehicleEventsInbound(
        changes: [VehicleEventRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("[vehicleEvent][inbound] applying changes=\(changes.count) familyId=\(familyId)")

        do {
            for change in changes {
                switch change {

                case .upsert(let dto):
                    if dto.isDeleted {
                        let eid = dto.id
                        let desc = FetchDescriptor<KBVehicleEvent>(predicate: #Predicate { $0.id == eid })
                        if let existing = try modelContext.fetch(desc).first {
                            KBLog.sync.kbInfo("[vehicleEvent][inbound] remote isDeleted -> DELETE local id=\(dto.id)")
                            modelContext.delete(existing)
                        }
                        continue
                    }

                    let eid = dto.id
                    let desc = FetchDescriptor<KBVehicleEvent>(predicate: #Predicate { $0.id == eid })

                    if let existing = try modelContext.fetch(desc).first {
                        if existing.isDeleted || existing.syncState == .pendingDelete {
                            KBLog.sync.kbDebug("[vehicleEvent][inbound] IGNORE (anti-resurrect) id=\(dto.id)")
                            continue
                        }

                        let remoteTs = dto.updatedAt ?? Date.distantPast
                        let localTs = existing.updatedAt

                        guard remoteTs >= localTs else {
                            KBLog.sync.kbDebug("[vehicleEvent][inbound] IGNORE remote<local id=\(dto.id)")
                            continue
                        }

                        existing.vehicleId = dto.vehicleId
                        existing.title = dto.title
                        existing.eventTypeRaw = dto.eventTypeRaw
                        existing.date = dto.date
                        existing.km = dto.km
                        existing.cost = dto.cost
                        existing.garageName = dto.garageName
                        existing.notes = dto.notes
                        existing.isDeleted = false
                        existing.updatedAt = remoteTs
                        if let ub = dto.updatedBy, !ub.isEmpty { existing.updatedBy = ub }
                        if let cb = dto.createdBy, !cb.isEmpty { existing.createdBy = cb }
                        existing.syncState = .synced
                        existing.lastSyncError = nil

                        KBLog.sync.kbDebug("[vehicleEvent][inbound] UPDATED id=\(dto.id)")

                    } else {
                        let now = dto.updatedAt ?? Date()
                        let createdAt = dto.createdAt ?? now
                        let row = KBVehicleEvent(
                            id: dto.id,
                            familyId: dto.familyId,
                            vehicleId: dto.vehicleId,
                            title: dto.title,
                            eventTypeRaw: dto.eventTypeRaw,
                            date: dto.date,
                            km: dto.km,
                            cost: dto.cost,
                            garageName: dto.garageName,
                            notes: dto.notes,
                            isDeleted: false,
                            createdAt: createdAt,
                            updatedAt: now,
                            createdBy: dto.createdBy ?? "",
                            updatedBy: dto.updatedBy ?? ""
                        )
                        row.syncState = .synced
                        modelContext.insert(row)
                        KBLog.sync.kbDebug("[vehicleEvent][inbound] CREATED id=\(dto.id)")
                    }

                case .remove(let id):
                    let eid = id
                    let desc = FetchDescriptor<KBVehicleEvent>(predicate: #Predicate { $0.id == eid })
                    if let existing = try modelContext.fetch(desc).first {
                        KBLog.sync.kbInfo("[vehicleEvent][inbound] remove -> DELETE local id=\(id)")
                        modelContext.delete(existing)
                    }
                }
            }

            try modelContext.save()
            KBLog.sync.kbDebug("[vehicleEvent][inbound] SAVE OK")

        } catch {
            KBLog.sync.kbError("[vehicleEvent][inbound] APPLY FAIL err=\(error.localizedDescription)")
        }
    }
}
