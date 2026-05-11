//
//  SyncCenter+HousePayments.swift
//  KidBox
//

import Foundation
import SwiftData
internal import FirebaseFirestoreInternal

extension SyncCenter {

    func startHousePaymentsRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startHousePaymentsRealtime familyId=\(familyId)")
        stopHousePaymentsRealtime()

        housePaymentListener = housePaymentRemote.listenHousePayments(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyHousePaymentsInbound(changes: changes, familyId: familyId, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "housePayments", error: err)
                    }
                }
            }
        )
    }

    func stopHousePaymentsRealtime() {
        if housePaymentListener != nil {
            KBLog.sync.kbInfo("stopHousePaymentsRealtime")
        }
        housePaymentListener?.remove()
        housePaymentListener = nil
    }

    func enqueueHousePaymentUpsert(paymentId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueHousePaymentUpsert familyId=\(familyId) paymentId=\(paymentId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.housePayment.rawValue,
            entityId: paymentId,
            opType: "upsert",
            modelContext: modelContext
        )
    }

    func enqueueHousePaymentDelete(paymentId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueHousePaymentDelete familyId=\(familyId) paymentId=\(paymentId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.housePayment.rawValue,
            entityId: paymentId,
            opType: "delete",
            modelContext: modelContext
        )
    }

    func processHousePayment(op: KBSyncOp, modelContext: ModelContext) async throws {
        let pid = op.entityId
        let desc = FetchDescriptor<KBHousePayment>(predicate: #Predicate { $0.id == pid })
        let item = try? modelContext.fetch(desc).first

        switch op.opType {
        case "upsert":
            guard let item else { return }
            item.syncState = .pendingUpsert
            item.lastSyncError = nil
            try? modelContext.save()

            try await housePaymentRemote.upsert(item: item)

            item.syncState = .synced
            item.lastSyncError = nil
            try modelContext.save()
            await HousePaymentReminderService.shared.scheduleNext(for: item)

        case "delete":
            try await housePaymentRemote.softDelete(paymentId: pid, familyId: op.familyId)

            if let item {
                KBLog.sync.kbInfo("[housePayment][outbound] delete OK -> HARD DELETE local id=\(item.id)")
                await HousePaymentReminderService.shared.cancelAll(paymentId: item.id)
                modelContext.delete(item)
                try? modelContext.save()
            }

        default:
            throw NSError(domain: "KidBox.Sync", code: -2411,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for housePayment: \(op.opType)"])
        }
    }

    func applyHousePaymentsInbound(
        changes: [HousePaymentRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("[housePayment][inbound] applying changes=\(changes.count) familyId=\(familyId)")

        do {
            for change in changes {
                switch change {

                case .upsert(let dto):
                    if dto.isDeleted {
                        let pid = dto.id
                        let desc = FetchDescriptor<KBHousePayment>(predicate: #Predicate { $0.id == pid })
                        if let existing = try modelContext.fetch(desc).first {
                            KBLog.sync.kbInfo("[housePayment][inbound] remote isDeleted -> DELETE local id=\(dto.id)")
                            Task { await HousePaymentReminderService.shared.cancelAll(paymentId: existing.id) }
                            modelContext.delete(existing)
                        }
                        continue
                    }

                    let pid = dto.id
                    let desc = FetchDescriptor<KBHousePayment>(predicate: #Predicate { $0.id == pid })

                    if let existing = try modelContext.fetch(desc).first {
                        if existing.isDeleted || existing.syncState == .pendingDelete {
                            KBLog.sync.kbDebug("[housePayment][inbound] IGNORE (anti-resurrect) id=\(dto.id)")
                            continue
                        }


                        let remoteTs = dto.updatedAt ?? Date.distantPast
                        let localTs = existing.updatedAt

                        guard remoteTs >= localTs else {
                            KBLog.sync.kbDebug("[housePayment][inbound] IGNORE remote<local id=\(dto.id)")
                            continue
                        }

                        existing.name = dto.name
                        existing.typeRaw = dto.typeRaw
                        existing.subtypeRaw = dto.subtypeRaw
                        existing.importo = dto.importo
                        existing.giornoDiScadenzaMensile = dto.giornoDiScadenzaMensile
                        existing.dataScadenza = dto.dataScadenza
                        existing.dataScadenzaContratto = dto.dataScadenzaContratto
                        existing.fornitore = dto.fornitore
                        existing.note = dto.note
                        existing.reminderOn = dto.reminderOn
                        existing.isDeleted = false
                        existing.updatedAt = remoteTs
                        if let ub = dto.updatedBy, !ub.isEmpty { existing.updatedBy = ub }
                        if let cb = dto.createdBy, !cb.isEmpty { existing.createdBy = cb }
                        existing.syncState = .synced
                        existing.lastSyncError = nil

                        KBLog.sync.kbDebug("[housePayment][inbound] UPDATED id=\(dto.id)")
                        Task { await HousePaymentReminderService.shared.scheduleNext(for: existing) }

                    } else {
                        let now = dto.updatedAt ?? Date()
                        let createdAt = dto.createdAt ?? now
                        let row = KBHousePayment(
                            id: dto.id,
                            familyId: dto.familyId,
                            name: dto.name,
                            typeRaw: dto.typeRaw,
                            subtypeRaw: dto.subtypeRaw,
                            importo: dto.importo,
                            giornoDiScadenzaMensile: dto.giornoDiScadenzaMensile,
                            dataScadenza: dto.dataScadenza,
                            dataScadenzaContratto: dto.dataScadenzaContratto,
                            fornitore: dto.fornitore,
                            note: dto.note,
                            reminderOn: dto.reminderOn,
                            isDeleted: false,
                            createdAt: createdAt,
                            updatedAt: now,
                            createdBy: dto.createdBy ?? "",
                            updatedBy: dto.updatedBy ?? ""
                        )
                        row.syncState = .synced
                        modelContext.insert(row)
                        KBLog.sync.kbDebug("[housePayment][inbound] CREATED id=\(dto.id)")
                        Task { await HousePaymentReminderService.shared.scheduleNext(for: row) }
                    }

                case .remove(let id):
                    let pid = id
                    let desc = FetchDescriptor<KBHousePayment>(predicate: #Predicate { $0.id == pid })
                    if let existing = try modelContext.fetch(desc).first {
                        KBLog.sync.kbInfo("[housePayment][inbound] remove -> DELETE local id=\(id)")
                        Task { await HousePaymentReminderService.shared.cancelAll(paymentId: existing.id) }
                        modelContext.delete(existing)
                    }
                }
            }

            try modelContext.save()
            KBLog.sync.kbDebug("[housePayment][inbound] SAVE OK")

        } catch {
            KBLog.sync.kbError("[housePayment][inbound] APPLY FAIL err=\(error.localizedDescription)")
        }
    }
}
