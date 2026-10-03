//
//  SyncCenter+PaymentCards.swift
//  KidBox
//
//  Created by vscocca on 03/10/26.
//

import Foundation
import SwiftData
internal import FirebaseFirestoreInternal

// MARK: - Carte di pagamento: realtime + outbox

/// Stesso schema delle carte fedeltà (LWW su `updatedAt`, tombstone
/// `isDeleted`), con una differenza: i campi cifrati passano da Firestore a
/// SwiftData senza essere decifrati. La decifratura avviene solo a schermo
/// (`PaymentCardPlain`).
extension SyncCenter {

    func startPaymentCardsRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startPaymentCardsRealtime familyId=\(familyId)")
        stopPaymentCardsRealtime()

        paymentCardListener = paymentCardRemote.listenPaymentCards(
            familyId: familyId,
            onChange: { [weak self] changes in
                self?.applyPaymentCardInbound(changes: changes, modelContext: modelContext)
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "paymentCards", error: err)
                    }
                }
            }
        )
    }

    func stopPaymentCardsRealtime() {
        paymentCardListener?.remove()
        paymentCardListener = nil
    }

    // MARK: - Outbox

    func enqueuePaymentCardUpsert(cardId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.paymentCard.rawValue,
            entityId: cardId,
            opType: "upsert",
            modelContext: modelContext
        )
    }

    func enqueuePaymentCardDelete(cardId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.paymentCard.rawValue,
            entityId: cardId,
            opType: "delete",
            modelContext: modelContext
        )
    }

    func processPaymentCard(op: KBSyncOp, modelContext: ModelContext) async throws {
        let cid = op.entityId
        let desc = FetchDescriptor<KBPaymentCard>(predicate: #Predicate { $0.id == cid })
        let card = try? modelContext.fetch(desc).first

        switch op.opType {
        case "upsert":
            guard let card else { return }
            card.syncState = .pendingUpsert
            card.lastSyncError = nil
            try? modelContext.save()

            try await paymentCardRemote.upsert(card: card)

            card.syncState = .synced
            card.lastSyncError = nil
            try modelContext.save()

        case "delete":
            try await paymentCardRemote.softDelete(cardId: cid, familyId: op.familyId)

            // Foto: cleanup best-effort, non blocca la cancellazione.
            if let card {
                for path in [card.frontPhotoStoragePath, card.backPhotoStoragePath].compactMap({ $0 }) where !path.isEmpty {
                    do {
                        try await paymentCardPhotoStore.delete(storagePath: path)
                    } catch {
                        KBLog.sync.kbError("[paymentCards][outbound] photo cleanup failed (ignored) cardId=\(cid) err=\(error.localizedDescription)")
                    }
                }
                modelContext.delete(card)
                try? modelContext.save()
            }

        default:
            throw NSError(domain: "KidBox.Sync", code: -2430,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for paymentCard: \(op.opType)"])
        }
    }

    // MARK: - Inbound (LWW)

    func applyPaymentCardInbound(changes: [PaymentCardRemoteChange], modelContext: ModelContext) {
        do {
            for change in changes {
                switch change {
                case .upsert(let dto):
                    let pid = dto.id
                    let desc = FetchDescriptor<KBPaymentCard>(predicate: #Predicate { $0.id == pid })
                    let existing = try modelContext.fetch(desc).first

                    if dto.isDeleted {
                        if let existing { modelContext.delete(existing) }
                        continue
                    }

                    let remoteTs = dto.updatedAt ?? .distantPast
                    let card: KBPaymentCard
                    if let existing {
                        if existing.isDeleted || existing.syncState == .pendingDelete { continue }
                        let localIsEmpty = existing.cardNumberEnc == nil && existing.labelEnc == nil
                        guard remoteTs >= existing.updatedAt || localIsEmpty else { continue }
                        card = existing
                    } else {
                        card = KBPaymentCard(
                            id: dto.id,
                            familyId: dto.familyId,
                            createdBy: dto.createdBy ?? "",
                            createdByName: dto.createdByName ?? "",
                            updatedBy: dto.updatedBy ?? "",
                            updatedByName: dto.updatedByName ?? "",
                            createdAt: dto.createdAt ?? dto.updatedAt ?? .now,
                            updatedAt: dto.updatedAt ?? .now
                        )
                        modelContext.insert(card)
                    }

                    card.labelEnc = dto.labelEnc
                    card.cardNumberEnc = dto.cardNumberEnc
                    card.holderNameEnc = dto.holderNameEnc
                    card.ibanEnc = dto.ibanEnc
                    card.expiryEnc = dto.expiryEnc
                    card.notesEnc = dto.notesEnc
                    card.pinEnc = dto.pinEnc
                    card.colorHex = dto.colorHex
                    card.frontPhotoStorageURL = dto.frontPhotoStorageURL
                    card.frontPhotoStoragePath = dto.frontPhotoStoragePath
                    card.backPhotoStorageURL = dto.backPhotoStorageURL
                    card.backPhotoStoragePath = dto.backPhotoStoragePath
                    card.visibilityScope = KBPaymentCard.normalizedVisibilityScope(dto.visibilityScope)
                    card.visibilityMemberIds = dto.visibilityMemberIds ?? []
                    card.isDeleted = false
                    if dto.updatedAt != nil { card.updatedAt = remoteTs }
                    if let cb = dto.createdBy, !cb.isEmpty { card.createdBy = cb }
                    if let cbn = dto.createdByName, !cbn.isEmpty { card.createdByName = cbn }
                    if let ub = dto.updatedBy, !ub.isEmpty { card.updatedBy = ub }
                    if let ubn = dto.updatedByName, !ubn.isEmpty { card.updatedByName = ubn }
                    card.syncState = .synced
                    card.lastSyncError = nil

                case .remove(let id):
                    let pid = id
                    let desc = FetchDescriptor<KBPaymentCard>(predicate: #Predicate { $0.id == pid })
                    if let existing = try modelContext.fetch(desc).first {
                        modelContext.delete(existing)
                    }
                }
            }
            try modelContext.save()
        } catch {
            KBLog.sync.kbError("[paymentCards][inbound] APPLY FAIL err=\(error.localizedDescription)")
        }
    }
}
