//
//  SyncCenter+Pets.swift
//  KidBox
//
//  Created by vscocca on 11/05/26.
//

import Foundation
import SwiftData
internal import FirebaseFirestoreInternal

// MARK: - Pets + pet events realtime + outbox

extension SyncCenter {

    // MARK: - Listener lifecycle

    func startPetsRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startPetsRealtime familyId=\(familyId)")
        stopPetsRealtime()

        petListener = petRemote.listenPets(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyPetsInbound(changes: changes, familyId: familyId, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "pets", error: err)
                    }
                }
            }
        )
    }

    func stopPetsRealtime() {
        if petListener != nil {
            KBLog.sync.kbInfo("stopPetsRealtime")
        }
        petListener?.remove()
        petListener = nil
    }

    func startPetEventsRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startPetEventsRealtime familyId=\(familyId)")
        stopPetEventsRealtime()

        petEventListener = petEventRemote.listenPetEvents(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyPetEventsInbound(changes: changes, familyId: familyId, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "petEvents", error: err)
                    }
                }
            }
        )
    }

    func stopPetEventsRealtime() {
        if petEventListener != nil {
            KBLog.sync.kbInfo("stopPetEventsRealtime")
        }
        petEventListener?.remove()
        petEventListener = nil
    }

    // MARK: - Outbox helpers

    func enqueuePetUpsert(petId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueuePetUpsert familyId=\(familyId) petId=\(petId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.pet.rawValue,
            entityId: petId,
            opType: "upsert",
            modelContext: modelContext
        )
    }

    func enqueuePetDelete(petId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueuePetDelete familyId=\(familyId) petId=\(petId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.pet.rawValue,
            entityId: petId,
            opType: "delete",
            modelContext: modelContext
        )
    }

    func enqueuePetEventUpsert(eventId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueuePetEventUpsert familyId=\(familyId) eventId=\(eventId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.petEvent.rawValue,
            entityId: eventId,
            opType: "upsert",
            modelContext: modelContext
        )
    }

    func enqueuePetEventDelete(eventId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueuePetEventDelete familyId=\(familyId) eventId=\(eventId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.petEvent.rawValue,
            entityId: eventId,
            opType: "delete",
            modelContext: modelContext
        )
    }

    // MARK: - Flush handlers

    func processPet(op: KBSyncOp, modelContext: ModelContext) async throws {
        let iid = op.entityId
        let desc = FetchDescriptor<KBPet>(predicate: #Predicate { $0.id == iid })
        let item = try? modelContext.fetch(desc).first

        switch op.opType {
        case "upsert":
            guard let item else { return }
            item.syncState = .pendingUpsert
            item.lastSyncError = nil
            try? modelContext.save()

            try await petRemote.upsert(item: item)

            item.syncState = .synced
            item.lastSyncError = nil
            try modelContext.save()

        case "delete":
            try await petRemote.softDelete(petId: iid, familyId: op.familyId)

            if let item {
                KBLog.sync.kbInfo("[pet][outbound] delete OK -> HARD DELETE local id=\(item.id)")
                modelContext.delete(item)
                try? modelContext.save()
            }

        default:
            throw NSError(domain: "KidBox.Sync", code: -2400,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for pet: \(op.opType)"])
        }
    }

    func processPetEvent(op: KBSyncOp, modelContext: ModelContext) async throws {
        let iid = op.entityId
        let desc = FetchDescriptor<KBPetEvent>(predicate: #Predicate { $0.id == iid })
        let item = try? modelContext.fetch(desc).first

        switch op.opType {
        case "upsert":
            guard let item else { return }
            item.syncState = .pendingUpsert
            item.lastSyncError = nil
            try? modelContext.save()

            try await petEventRemote.upsert(item: item)

            item.syncState = .synced
            item.lastSyncError = nil
            try modelContext.save()

        case "delete":
            try await petEventRemote.softDelete(eventId: iid, familyId: op.familyId)

            if let item {
                KBLog.sync.kbInfo("[petEvent][outbound] delete OK -> HARD DELETE local id=\(item.id)")
                modelContext.delete(item)
                try? modelContext.save()
            }

        default:
            throw NSError(domain: "KidBox.Sync", code: -2401,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for petEvent: \(op.opType)"])
        }
    }

    // MARK: - Inbound apply (LWW)

    func applyPetsInbound(
        changes: [PetRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("[pet][inbound] applying changes=\(changes.count) familyId=\(familyId)")

        do {
            for change in changes {
                switch change {

                case .upsert(let dto):
                    if dto.isDeleted {
                        let pid = dto.id
                        let desc = FetchDescriptor<KBPet>(predicate: #Predicate { $0.id == pid })
                        if let existing = try modelContext.fetch(desc).first {
                            KBLog.sync.kbInfo("[pet][inbound] remote isDeleted -> DELETE local id=\(dto.id)")
                            modelContext.delete(existing)
                        }
                        continue
                    }

                    let pid = dto.id
                    let desc = FetchDescriptor<KBPet>(predicate: #Predicate { $0.id == pid })

                    if let existing = try modelContext.fetch(desc).first {
                        if existing.isDeleted || existing.syncState == .pendingDelete {
                            KBLog.sync.kbDebug("[pet][inbound] IGNORE (anti-resurrect) id=\(dto.id)")
                            continue
                        }

                        let remoteTs = dto.updatedAt ?? Date.distantPast
                        let localTs = existing.updatedAt

                        guard remoteTs >= localTs else {
                            KBLog.sync.kbDebug("[pet][inbound] IGNORE remote<local id=\(dto.id)")
                            continue
                        }

                        existing.name = dto.name
                        existing.species = dto.species
                        existing.breed = dto.breed
                        existing.birthDate = dto.birthDate
                        existing.color = dto.color
                        existing.chipCode = dto.chipCode
                        existing.notes = dto.notes
                        existing.photoURL = dto.photoURL
                        existing.isDeleted = false
                        existing.updatedAt = remoteTs
                        if let ub = dto.updatedBy, !ub.isEmpty { existing.updatedBy = ub }
                        if let cb = dto.createdBy, !cb.isEmpty { existing.createdBy = cb }
                        existing.syncState = .synced
                        existing.lastSyncError = nil

                        KBLog.sync.kbDebug("[pet][inbound] UPDATED id=\(dto.id)")

                    } else {
                        let now = dto.updatedAt ?? Date()
                        let createdAt = dto.createdAt ?? now
                        let pet = KBPet(
                            id: dto.id,
                            familyId: dto.familyId,
                            name: dto.name,
                            species: dto.species,
                            breed: dto.breed,
                            birthDate: dto.birthDate,
                            color: dto.color,
                            chipCode: dto.chipCode,
                            notes: dto.notes,
                            photoURL: dto.photoURL,
                            isDeleted: false,
                            createdAt: createdAt,
                            updatedAt: now,
                            createdBy: dto.createdBy ?? "",
                            updatedBy: dto.updatedBy ?? ""
                        )
                        pet.syncState = .synced
                        modelContext.insert(pet)
                        KBLog.sync.kbDebug("[pet][inbound] CREATED id=\(dto.id)")
                    }

                case .remove(let id):
                    let pid = id
                    let desc = FetchDescriptor<KBPet>(predicate: #Predicate { $0.id == pid })
                    if let existing = try modelContext.fetch(desc).first {
                        KBLog.sync.kbInfo("[pet][inbound] remove -> DELETE local id=\(id)")
                        modelContext.delete(existing)
                    }
                }
            }

            try modelContext.save()
            KBLog.sync.kbDebug("[pet][inbound] SAVE OK")

        } catch {
            KBLog.sync.kbError("[pet][inbound] APPLY FAIL err=\(error.localizedDescription)")
        }
    }

    func applyPetEventsInbound(
        changes: [PetEventRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("[petEvent][inbound] applying changes=\(changes.count) familyId=\(familyId)")

        do {
            for change in changes {
                switch change {

                case .upsert(let dto):
                    if dto.isDeleted {
                        let eid = dto.id
                        let desc = FetchDescriptor<KBPetEvent>(predicate: #Predicate { $0.id == eid })
                        if let existing = try modelContext.fetch(desc).first {
                            KBLog.sync.kbInfo("[petEvent][inbound] remote isDeleted -> DELETE local id=\(dto.id)")
                            modelContext.delete(existing)
                        }
                        continue
                    }

                    let eid = dto.id
                    let desc = FetchDescriptor<KBPetEvent>(predicate: #Predicate { $0.id == eid })

                    if let existing = try modelContext.fetch(desc).first {
                        if existing.isDeleted || existing.syncState == .pendingDelete {
                            KBLog.sync.kbDebug("[petEvent][inbound] IGNORE (anti-resurrect) id=\(dto.id)")
                            continue
                        }

                        let remoteTs = dto.updatedAt ?? Date.distantPast
                        let localTs = existing.updatedAt

                        guard remoteTs >= localTs else {
                            KBLog.sync.kbDebug("[petEvent][inbound] IGNORE remote<local id=\(dto.id)")
                            continue
                        }

                        existing.petId = dto.petId
                        existing.title = dto.title
                        existing.eventTypeRaw = dto.eventTypeRaw
                        existing.date = dto.date
                        existing.nextDueDate = dto.nextDueDate
                        existing.notes = dto.notes
                        existing.vetName = dto.vetName
                        existing.cost = dto.cost
                        existing.isDeleted = false
                        existing.reminderEnabled = dto.reminderEnabled
                        existing.updatedAt = remoteTs
                        if let ub = dto.updatedBy, !ub.isEmpty { existing.updatedBy = ub }
                        if let cb = dto.createdBy, !cb.isEmpty { existing.createdBy = cb }
                        existing.syncState = .synced
                        existing.lastSyncError = nil

                        KBLog.sync.kbDebug("[petEvent][inbound] UPDATED id=\(dto.id)")

                    } else {
                        let now = dto.updatedAt ?? Date()
                        let createdAt = dto.createdAt ?? now
                        let ev = KBPetEvent(
                            id: dto.id,
                            familyId: dto.familyId,
                            petId: dto.petId,
                            title: dto.title,
                            eventTypeRaw: dto.eventTypeRaw,
                            date: dto.date,
                            nextDueDate: dto.nextDueDate,
                            notes: dto.notes,
                            vetName: dto.vetName,
                            cost: dto.cost,
                            isDeleted: false,
                            createdAt: createdAt,
                            updatedAt: now,
                            createdBy: dto.createdBy ?? "",
                            updatedBy: dto.updatedBy ?? "",
                            reminderEnabled: dto.reminderEnabled,
                            reminderId: nil
                        )
                        ev.syncState = .synced
                        modelContext.insert(ev)
                        KBLog.sync.kbDebug("[petEvent][inbound] CREATED id=\(dto.id)")
                    }

                case .remove(let id):
                    let eid = id
                    let desc = FetchDescriptor<KBPetEvent>(predicate: #Predicate { $0.id == eid })
                    if let existing = try modelContext.fetch(desc).first {
                        KBLog.sync.kbInfo("[petEvent][inbound] remove -> DELETE local id=\(id)")
                        modelContext.delete(existing)
                    }
                }
            }

            try modelContext.save()
            KBLog.sync.kbDebug("[petEvent][inbound] SAVE OK")

        } catch {
            KBLog.sync.kbError("[petEvent][inbound] APPLY FAIL err=\(error.localizedDescription)")
        }
    }
}
