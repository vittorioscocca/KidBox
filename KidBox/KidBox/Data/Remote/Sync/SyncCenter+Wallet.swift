//
//  SyncCenter+Wallet.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import Foundation
import SwiftData
import FirebaseAuth
internal import FirebaseFirestoreInternal

// MARK: - Wallet realtime + outbox integration

extension SyncCenter {

    // MARK: - Listener lifecycle

    func startWalletRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startWalletRealtime familyId=\(familyId)")
        stopWalletRealtime()

        walletListener = walletRemote.listenWalletTickets(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                self.applyWalletInbound(changes: changes, familyId: familyId, modelContext: modelContext)
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "wallet", error: err)
                    }
                }
            }
        )
    }

    func stopWalletRealtime() {
        if walletListener != nil {
            KBLog.sync.kbInfo("stopWalletRealtime")
        }
        walletListener?.remove()
        walletListener = nil
    }

    // MARK: - Outbox helpers

    func enqueueWalletTicketUpsert(ticketId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueWalletTicketUpsert familyId=\(familyId) ticketId=\(ticketId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.walletTicket.rawValue,
            entityId: ticketId,
            opType: "upsert",
            modelContext: modelContext
        )
    }

    func enqueueWalletTicketDelete(ticketId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueWalletTicketDelete familyId=\(familyId) ticketId=\(ticketId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.walletTicket.rawValue,
            entityId: ticketId,
            opType: "delete",
            modelContext: modelContext
        )
    }

    // MARK: - Flush handler

    func processWalletTicket(op: KBSyncOp, modelContext: ModelContext) async throws {
        let tid = op.entityId
        let desc = FetchDescriptor<KBWalletTicket>(predicate: #Predicate { $0.id == tid })
        let ticket = try? modelContext.fetch(desc).first

        switch op.opType {

        case "upsert":
            guard let ticket else { return }
            ticket.syncState = .pendingUpsert
            ticket.lastSyncError = nil
            try? modelContext.save()

            try await walletRemote.upsert(ticket: ticket)

            ticket.syncState = .synced
            ticket.lastSyncError = nil
            try modelContext.save()

        case "delete":
            try await walletRemote.softDelete(ticketId: tid, familyId: op.familyId)

            // best-effort cleanup PDF su Storage (se presente)
            if let ticket, ticket.pdfStorageURL != nil {
                do {
                    try await walletPDFStore.delete(familyId: op.familyId, ticketId: tid)
                } catch {
                    KBLog.sync.kbError("[wallet][outbound] PDF cleanup failed (ignored) ticketId=\(tid) err=\(error.localizedDescription)")
                }
            }

            // Cancella i promemoria locali del ticket
            await WalletReminderService.shared.cancelReminders(ticketId: tid)

            if let ticket {
                KBLog.sync.kbInfo("[wallet][outbound] delete OK -> HARD DELETE local id=\(ticket.id)")
                modelContext.delete(ticket)
                try? modelContext.save()
            }

        default:
            throw NSError(domain: "KidBox.Sync", code: -2410,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for walletTicket: \(op.opType)"])
        }
    }

    // MARK: - Inbound apply (LWW)

    func applyWalletInbound(
        changes: [WalletRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("[wallet][inbound] applying changes=\(changes.count) familyId=\(familyId)")

        do {
            let uid = Auth.auth().currentUser?.uid ?? ""

            for change in changes {
                switch change {

                case .upsert(let dto):
                    if dto.isDeleted {
                        let pid = dto.id
                        let desc = FetchDescriptor<KBWalletTicket>(predicate: #Predicate { $0.id == pid })
                        if let existing = try modelContext.fetch(desc).first {
                            KBLog.sync.kbInfo("[wallet][inbound] remote isDeleted -> DELETE local id=\(dto.id)")
                            modelContext.delete(existing)
                            Task { await WalletReminderService.shared.cancelReminders(ticketId: dto.id) }
                        }
                        continue
                    }

                    // Decifra i campi sensibili (graceful fallback su errore: marker visibile)
                    var title: String
                    var location: String?
                    var seat: String?
                    var bookingCode: String?
                    var arrivalLocation: String?
                    var holderName: String?
                    var notes: String?
                    var barcodeText: String?
                    let fileName: String?

                    if !uid.isEmpty {
                        do {
                            title       = try WalletCryptoService.decryptString(dto.titleEnc ?? "", familyId: familyId, userId: uid)
                            location    = try WalletCryptoService.decryptOptional(dto.locationEnc, familyId: familyId, userId: uid)
                            seat        = try WalletCryptoService.decryptOptional(dto.seatEnc, familyId: familyId, userId: uid)
                            bookingCode = try WalletCryptoService.decryptOptional(dto.bookingCodeEnc, familyId: familyId, userId: uid)
                            arrivalLocation = try WalletCryptoService.decryptOptional(dto.arrivalLocationEnc, familyId: familyId, userId: uid)
                            holderName  = try WalletCryptoService.decryptOptional(dto.holderNameEnc, familyId: familyId, userId: uid)
                            notes       = try WalletCryptoService.decryptOptional(dto.notesEnc, familyId: familyId, userId: uid)
                            barcodeText = try WalletCryptoService.decryptOptional(dto.barcodeTextEnc, familyId: familyId, userId: uid)
                            fileName    = try WalletCryptoService.decryptOptional(dto.fileNameEnc, familyId: familyId, userId: uid)
                        } catch {
                            KBLog.sync.kbError("[wallet][inbound] decrypt FAIL id=\(dto.id) err=\(error.localizedDescription)")
                            title = "⚠️ Biglietto non decifrabile"
                            location = nil; seat = nil; bookingCode = nil; notes = nil
                            arrivalLocation = nil; holderName = nil
                            barcodeText = nil; fileName = nil
                        }
                    } else {
                        title = "⚠️ Biglietto non decifrabile"
                        location = nil; seat = nil; bookingCode = nil; notes = nil
                        arrivalLocation = nil; holderName = nil
                        barcodeText = nil; fileName = nil
                    }

                    let pid = dto.id
                    let desc = FetchDescriptor<KBWalletTicket>(predicate: #Predicate { $0.id == pid })

                    if let existing = try modelContext.fetch(desc).first {
                        if existing.isDeleted || existing.syncState == .pendingDelete {
                            KBLog.sync.kbDebug("[wallet][inbound] IGNORE (anti-resurrect) id=\(dto.id)")
                            continue
                        }

                        let remoteTs = dto.updatedAt ?? .distantPast
                        let localTs  = existing.updatedAt
                        let localIsEmpty = existing.title.isEmpty && existing.pdfStorageURL == nil

                        guard remoteTs >= localTs || localIsEmpty else {
                            KBLog.sync.kbDebug("[wallet][inbound] IGNORE remote<local id=\(dto.id)")
                            continue
                        }

                        existing.title = title
                        existing.location = location
                        existing.seat = seat
                        existing.bookingCode = bookingCode
                        existing.arrivalLocation = arrivalLocation
                        existing.holderName = holderName
                        existing.notes = notes
                        existing.extractedBarcodeText = barcodeText
                        existing.pdfFileName = fileName

                        if let kindRaw = dto.kindRaw, !kindRaw.isEmpty {
                            existing.kindRaw = kindRaw
                        }
                        existing.emitter = dto.emitter
                        existing.eventDate = dto.eventDate
                        existing.eventEndDate = dto.eventEndDate
                        existing.pdfStorageURL = dto.pdfStorageURL
                        existing.pdfStorageBytes = max(0, dto.pdfStorageBytes)
                        existing.addToAppleWalletURL = dto.addToAppleWalletURL
                        existing.extractedBarcodeFormat = dto.barcodeFormat

                        existing.visibilityScope = KBWalletTicket.normalizedVisibilityScopeForWallet(dto.visibilityScope)
                        existing.visibilityMemberIds = dto.visibilityMemberIds ?? []

                        existing.isDeleted = false
                        existing.updatedAt = remoteTs

                        if let cb = dto.createdBy, !cb.isEmpty   { existing.createdBy = cb }
                        if let cbn = dto.createdByName, !cbn.isEmpty { existing.createdByName = cbn }
                        if let ub = dto.updatedBy, !ub.isEmpty   { existing.updatedBy = ub }
                        if let ubn = dto.updatedByName, !ubn.isEmpty { existing.updatedByName = ubn }

                        existing.syncState = .synced
                        existing.lastSyncError = nil

                        // Re-schedula i promemoria locali se la data è cambiata
                        let snapshotForReminder = existing
                        Task { await WalletReminderService.shared.scheduleReminders(for: snapshotForReminder) }

                        KBLog.sync.kbDebug("[wallet][inbound] UPDATED id=\(dto.id)")

                    } else {
                        let now = dto.updatedAt ?? Date()
                        let createdAt = dto.createdAt ?? now
                        let kind = KBWalletTicketKind(rawValue: dto.kindRaw ?? "") ?? .other

                        let ticket = KBWalletTicket(
                            id: dto.id,
                            familyId: dto.familyId,
                            title: title,
                            kind: kind,
                            eventDate: dto.eventDate,
                            eventEndDate: dto.eventEndDate,
                            location: location,
                            seat: seat,
                            bookingCode: bookingCode,
                            arrivalLocation: arrivalLocation,
                            holderName: holderName,
                            notes: notes,
                            emitter: dto.emitter,
                            visibilityScope: KBWalletTicket.normalizedVisibilityScopeForWallet(dto.visibilityScope),
                            visibilityMemberIds: dto.visibilityMemberIds ?? [],
                            pdfStorageURL: dto.pdfStorageURL,
                            pdfFileName: fileName,
                            pdfStorageBytes: dto.pdfStorageBytes,
                            pdfThumbnailData: nil,  // generato lazy alla prima apertura del viewer
                            addToAppleWalletURL: dto.addToAppleWalletURL,
                            extractedBarcodeText: barcodeText,
                            extractedBarcodeFormat: dto.barcodeFormat,
                            createdBy: dto.createdBy ?? "",
                            createdByName: dto.createdByName ?? "",
                            updatedBy: dto.updatedBy ?? "",
                            updatedByName: dto.updatedByName ?? "",
                            createdAt: createdAt,
                            updatedAt: now,
                            isDeleted: false
                        )
                        ticket.syncState = .synced

                        modelContext.insert(ticket)

                        let snapshotForReminder = ticket
                        Task { await WalletReminderService.shared.scheduleReminders(for: snapshotForReminder) }

                        KBLog.sync.kbDebug("[wallet][inbound] CREATED id=\(dto.id)")
                    }

                case .remove(let id):
                    let pid = id
                    let desc = FetchDescriptor<KBWalletTicket>(predicate: #Predicate { $0.id == pid })
                    if let existing = try modelContext.fetch(desc).first {
                        KBLog.sync.kbInfo("[wallet][inbound] remove -> DELETE local id=\(id)")
                        modelContext.delete(existing)
                        Task { await WalletReminderService.shared.cancelReminders(ticketId: id) }
                    }
                }
            }

            try modelContext.save()
            KBLog.sync.kbDebug("[wallet][inbound] SAVE OK")

        } catch {
            KBLog.sync.kbError("[wallet][inbound] APPLY FAIL err=\(error.localizedDescription)")
        }
    }

    // MARK: - One-shot fetch (per deep link da push)

    func fetchWalletTicketsOnce(familyId: String, modelContext: ModelContext) async {
        do {
            let dtos = try await walletRemote.fetchAllOnce(familyId: familyId)
            applyWalletInbound(
                changes: dtos.map { .upsert($0) },
                familyId: familyId,
                modelContext: modelContext
            )
        } catch {
            KBLog.sync.kbError("[wallet] fetchAllOnce failed: \(error.localizedDescription)")
        }
    }
}
