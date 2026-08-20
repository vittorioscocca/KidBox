//
//  SyncCenter+LoyaltyCards.swift
//  KidBox
//
//  Created by vscocca on 20/08/26.
//

import Foundation
import SwiftData
internal import FirebaseFirestoreInternal

// MARK: - Loyalty cards realtime + outbox integration

extension SyncCenter {

    // MARK: - Listener lifecycle

    func startLoyaltyCardsRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startLoyaltyCardsRealtime familyId=\(familyId)")
        stopLoyaltyCardsRealtime()

        loyaltyCardListener = loyaltyCardRemote.listenLoyaltyCards(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                self.applyLoyaltyCardInbound(changes: changes, familyId: familyId, modelContext: modelContext)
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "loyaltyCards", error: err)
                    }
                }
            }
        )
    }

    func stopLoyaltyCardsRealtime() {
        if loyaltyCardListener != nil {
            KBLog.sync.kbInfo("stopLoyaltyCardsRealtime")
        }
        loyaltyCardListener?.remove()
        loyaltyCardListener = nil
    }

    // MARK: - Outbox helpers

    func enqueueLoyaltyCardUpsert(cardId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueLoyaltyCardUpsert familyId=\(familyId) cardId=\(cardId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.loyaltyCard.rawValue,
            entityId: cardId,
            opType: "upsert",
            modelContext: modelContext
        )
    }

    func enqueueLoyaltyCardDelete(cardId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueLoyaltyCardDelete familyId=\(familyId) cardId=\(cardId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.loyaltyCard.rawValue,
            entityId: cardId,
            opType: "delete",
            modelContext: modelContext
        )
    }

    // MARK: - Flush handler

    func processLoyaltyCard(op: KBSyncOp, modelContext: ModelContext) async throws {
        let cid = op.entityId
        let desc = FetchDescriptor<KBLoyaltyCard>(predicate: #Predicate { $0.id == cid })
        let card = try? modelContext.fetch(desc).first

        switch op.opType {

        case "upsert":
            guard let card else { return }
            card.syncState = .pendingUpsert
            card.lastSyncError = nil
            try? modelContext.save()

            try await loyaltyCardRemote.upsert(card: card)

            card.syncState = .synced
            card.lastSyncError = nil
            try modelContext.save()

        case "delete":
            try await loyaltyCardRemote.softDelete(cardId: cid, familyId: op.familyId)

            // Cleanup best-effort delle foto fronte/retro su Storage, come per
            // il PDF dei biglietti: se fallisce non blocca la cancellazione.
            if let card {
                for side in LoyaltyCardPhotoSide.allCases {
                    let path = side == .front ? card.frontPhotoStoragePath : card.backPhotoStoragePath
                    guard let path, !path.isEmpty else { continue }
                    do {
                        try await loyaltyCardPhotoStore.delete(
                            familyId: op.familyId, cardId: cid, side: side, storagePath: path)
                    } catch {
                        KBLog.sync.kbError("[loyaltyCards][outbound] photo cleanup failed (ignored) cardId=\(cid) side=\(side.rawValue) err=\(error.localizedDescription)")
                    }
                }
            }

            if let card {
                KBLog.sync.kbInfo("[loyaltyCards][outbound] delete OK -> HARD DELETE local id=\(card.id)")
                modelContext.delete(card)
                try? modelContext.save()
            }

        default:
            throw NSError(domain: "KidBox.Sync", code: -2420,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for loyaltyCard: \(op.opType)"])
        }
    }

    // MARK: - Inbound apply (LWW)

    func applyLoyaltyCardInbound(
        changes: [LoyaltyCardRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("[loyaltyCards][inbound] applying changes=\(changes.count) familyId=\(familyId)")

        do {
            for change in changes {
                switch change {

                case .upsert(let dto):
                    if dto.isDeleted {
                        let pid = dto.id
                        let desc = FetchDescriptor<KBLoyaltyCard>(predicate: #Predicate { $0.id == pid })
                        if let existing = try modelContext.fetch(desc).first {
                            KBLog.sync.kbInfo("[loyaltyCards][inbound] remote isDeleted -> DELETE local id=\(dto.id)")
                            modelContext.delete(existing)
                        }
                        continue
                    }

                    let pid = dto.id
                    let desc = FetchDescriptor<KBLoyaltyCard>(predicate: #Predicate { $0.id == pid })

                    if let existing = try modelContext.fetch(desc).first {
                        if existing.isDeleted || existing.syncState == .pendingDelete {
                            KBLog.sync.kbDebug("[loyaltyCards][inbound] IGNORE (anti-resurrect) id=\(dto.id)")
                            continue
                        }

                        let remoteTs = dto.updatedAt ?? .distantPast
                        let localTs  = existing.updatedAt
                        let localIsEmpty = existing.cardNumber.isEmpty && existing.brandName.isEmpty

                        guard remoteTs >= localTs || localIsEmpty else {
                            KBLog.sync.kbDebug("[loyaltyCards][inbound] IGNORE remote<local id=\(dto.id)")
                            continue
                        }

                        existing.brandId = dto.brandId
                        existing.brandName = dto.brandName
                        existing.cardNumber = dto.cardNumber
                        existing.barcodeFormat = dto.barcodeFormat
                        existing.note = dto.note
                        existing.primaryColorHex = dto.primaryColorHex
                        existing.secondaryColorHex = dto.secondaryColorHex
                        existing.logoURL = dto.logoURL
                        existing.frontPhotoStorageURL = dto.frontPhotoStorageURL
                        existing.frontPhotoStoragePath = dto.frontPhotoStoragePath
                        existing.backPhotoStorageURL = dto.backPhotoStorageURL
                        existing.backPhotoStoragePath = dto.backPhotoStoragePath

                        existing.visibilityScope = KBLoyaltyCard.normalizedVisibilityScopeForLoyaltyCard(dto.visibilityScope)
                        existing.visibilityMemberIds = dto.visibilityMemberIds ?? []

                        existing.isDeleted = false
                        existing.updatedAt = remoteTs

                        if let cb = dto.createdBy, !cb.isEmpty   { existing.createdBy = cb }
                        if let cbn = dto.createdByName, !cbn.isEmpty { existing.createdByName = cbn }
                        if let ub = dto.updatedBy, !ub.isEmpty   { existing.updatedBy = ub }
                        if let ubn = dto.updatedByName, !ubn.isEmpty { existing.updatedByName = ubn }

                        existing.syncState = .synced
                        existing.lastSyncError = nil

                        KBLog.sync.kbDebug("[loyaltyCards][inbound] UPDATED id=\(dto.id)")

                    } else {
                        let now = dto.updatedAt ?? Date()
                        let createdAt = dto.createdAt ?? now

                        let card = KBLoyaltyCard(
                            id: dto.id,
                            familyId: dto.familyId,
                            brandId: dto.brandId,
                            brandName: dto.brandName,
                            cardNumber: dto.cardNumber,
                            barcodeFormat: dto.barcodeFormat,
                            note: dto.note,
                            primaryColorHex: dto.primaryColorHex,
                            secondaryColorHex: dto.secondaryColorHex,
                            logoURL: dto.logoURL,
                            visibilityScope: KBLoyaltyCard.normalizedVisibilityScopeForLoyaltyCard(dto.visibilityScope),
                            visibilityMemberIds: dto.visibilityMemberIds ?? [],
                            createdBy: dto.createdBy ?? "",
                            createdByName: dto.createdByName ?? "",
                            updatedBy: dto.updatedBy ?? "",
                            updatedByName: dto.updatedByName ?? "",
                            createdAt: createdAt,
                            updatedAt: now,
                            isDeleted: false
                        )
                        card.frontPhotoStorageURL = dto.frontPhotoStorageURL
                        card.frontPhotoStoragePath = dto.frontPhotoStoragePath
                        card.backPhotoStorageURL = dto.backPhotoStorageURL
                        card.backPhotoStoragePath = dto.backPhotoStoragePath
                        card.syncState = .synced

                        modelContext.insert(card)

                        KBLog.sync.kbDebug("[loyaltyCards][inbound] CREATED id=\(dto.id)")
                    }

                case .remove(let id):
                    let pid = id
                    let desc = FetchDescriptor<KBLoyaltyCard>(predicate: #Predicate { $0.id == pid })
                    if let existing = try modelContext.fetch(desc).first {
                        KBLog.sync.kbInfo("[loyaltyCards][inbound] remove -> DELETE local id=\(id)")
                        modelContext.delete(existing)
                    }
                }
            }

            try modelContext.save()
            KBLog.sync.kbDebug("[loyaltyCards][inbound] SAVE OK")

        } catch {
            KBLog.sync.kbError("[loyaltyCards][inbound] APPLY FAIL err=\(error.localizedDescription)")
        }
    }

    // MARK: - One-shot fetch

    func fetchLoyaltyCardsOnce(familyId: String, modelContext: ModelContext) async {
        do {
            let dtos = try await loyaltyCardRemote.fetchAllOnce(familyId: familyId)
            applyLoyaltyCardInbound(
                changes: dtos.map { .upsert($0) },
                familyId: familyId,
                modelContext: modelContext
            )
        } catch {
            KBLog.sync.kbError("[loyaltyCards] fetchAllOnce failed: \(error.localizedDescription)")
        }
    }
}
