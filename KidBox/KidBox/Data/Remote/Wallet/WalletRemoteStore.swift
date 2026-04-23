//
//  WalletRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

// MARK: - DTO

/// Snapshot di un documento `walletTickets` su Firestore — campi sensibili
/// arrivano cifrati base64, decifrati lato client da `WalletCryptoService`.
struct WalletTicketDTO {
    let id: String
    let familyId: String

    // Encrypted fields (preferred)
    let titleEnc: String?
    let locationEnc: String?
    let seatEnc: String?
    let bookingCodeEnc: String?
    let notesEnc: String?
    let barcodeTextEnc: String?
    let fileNameEnc: String?

    // Plaintext metadata (server-readable)
    let kindRaw: String?
    let emitter: String?
    let eventDate: Date?
    let eventEndDate: Date?
    let pdfStorageURL: String?
    let pdfStorageBytes: Int64
    let addToAppleWalletURL: String?
    let barcodeFormat: String?

    let isDeleted: Bool

    let createdAt: Date?
    let updatedAt: Date?

    let createdBy: String?
    let createdByName: String?
    let updatedBy: String?
    let updatedByName: String?
}

enum WalletRemoteChange {
    case upsert(WalletTicketDTO)
    case remove(String)
}

// MARK: - Store

/// Remote store per i biglietti del Wallet.
///
/// Path Firestore: `families/{familyId}/walletTickets/{ticketId}`
///
/// Pattern speculare a `NotesRemoteStore`:
/// - upsert con `setData(merge: true)`
/// - soft-delete via `isDeleted: true` (la hard-delete locale + cleanup
///   PDF su Storage è gestita da `SyncCenter+Wallet`)
/// - listener realtime con `addSnapshotListener(includeMetadataChanges: true)`
final class WalletRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func int64Value(_ any: Any?) -> Int64 {
        if let n = any as? NSNumber { return n.int64Value }
        if let v = any as? Int64 { return v }
        if let v = any as? Int { return Int64(v) }
        if let v = any as? Double { return Int64(v) }
        return 0
    }

    // MARK: - References

    private func ref(familyId: String, ticketId: String) -> DocumentReference {
        db.collection("families")
            .document(familyId)
            .collection("walletTickets")
            .document(ticketId)
    }

    private func col(familyId: String) -> CollectionReference {
        db.collection("families")
            .document(familyId)
            .collection("walletTickets")
    }

    // MARK: - Upsert

    func upsert(ticket: KBWalletTicket) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let snap = try await ref(familyId: ticket.familyId, ticketId: ticket.id).getDocument()
        let isNew = !snap.exists

        let titleEnc        = try WalletCryptoService.encryptString(ticket.title, familyId: ticket.familyId, userId: uid)
        let locationEnc     = try WalletCryptoService.encryptOptional(ticket.location, familyId: ticket.familyId, userId: uid)
        let seatEnc         = try WalletCryptoService.encryptOptional(ticket.seat, familyId: ticket.familyId, userId: uid)
        let bookingCodeEnc  = try WalletCryptoService.encryptOptional(ticket.bookingCode, familyId: ticket.familyId, userId: uid)
        let notesEnc        = try WalletCryptoService.encryptOptional(ticket.notes, familyId: ticket.familyId, userId: uid)
        let barcodeTextEnc  = try WalletCryptoService.encryptOptional(ticket.extractedBarcodeText, familyId: ticket.familyId, userId: uid)
        let fileNameEnc     = try WalletCryptoService.encryptOptional(ticket.pdfFileName, familyId: ticket.familyId, userId: uid)

        var data: [String: Any] = [
            "schemaVersion": 1,

            // Encrypted (sensitive)
            "titleEnc":        titleEnc,
            "locationEnc":     locationEnc as Any,
            "seatEnc":         seatEnc as Any,
            "bookingCodeEnc":  bookingCodeEnc as Any,
            "notesEnc":        notesEnc as Any,
            "barcodeTextEnc":  barcodeTextEnc as Any,
            "fileNameEnc":     fileNameEnc as Any,

            // Plaintext (server-readable for CF / queries / security)
            "kind":                ticket.kindRaw,
            "emitter":             ticket.emitter as Any,
            "eventDate":           ticket.eventDate.map { Timestamp(date: $0) } as Any,
            "eventEndDate":        ticket.eventEndDate.map { Timestamp(date: $0) } as Any,
            "pdfStorageURL":       ticket.pdfStorageURL as Any,
            "pdfStorageBytes":     ticket.pdfStorageBytes ?? 0,
            "addToAppleWalletURL": ticket.addToAppleWalletURL as Any,
            "barcodeFormat":       ticket.extractedBarcodeFormat as Any,

            "isDeleted":     false,
            "updatedBy":     uid,
            "updatedByName": ticket.updatedByName,
            "updatedAt":     FieldValue.serverTimestamp()
        ]

        if isNew {
            data["createdAt"]     = FieldValue.serverTimestamp()
            data["createdBy"]     = ticket.createdBy.isEmpty ? uid : ticket.createdBy
            data["createdByName"] = ticket.createdByName
        }

        try await ref(familyId: ticket.familyId, ticketId: ticket.id).setData(data, merge: true)
        KBLog.sync.kbInfo("[WalletRemote] upsert OK id=\(ticket.id) familyId=\(ticket.familyId) kind=\(ticket.kindRaw)")
    }

    // MARK: - Soft delete

    func softDelete(ticketId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        try await ref(familyId: familyId, ticketId: ticketId).setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        KBLog.sync.kbInfo("[WalletRemote] softDelete OK id=\(ticketId) familyId=\(familyId)")
    }

    // MARK: - Realtime listener

    func listenWalletTickets(
        familyId: String,
        onChange: @escaping ([WalletRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        KBLog.sync.kbInfo("[WalletRemote] listen ATTACH familyId=\(familyId)")

        return col(familyId: familyId)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[WalletRemote] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else { return }

                KBLog.sync.kbDebug("[WalletRemote] snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count) fromCache=\(snap.metadata.isFromCache)")

                let changes: [WalletRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let d = doc.data()

                    let dto = WalletTicketDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        titleEnc:           d["titleEnc"]        as? String,
                        locationEnc:        d["locationEnc"]     as? String,
                        seatEnc:            d["seatEnc"]         as? String,
                        bookingCodeEnc:     d["bookingCodeEnc"]  as? String,
                        notesEnc:           d["notesEnc"]        as? String,
                        barcodeTextEnc:     d["barcodeTextEnc"]  as? String,
                        fileNameEnc:        d["fileNameEnc"]     as? String,
                        kindRaw:            d["kind"]            as? String,
                        emitter:            d["emitter"]         as? String,
                        eventDate:          (d["eventDate"]      as? Timestamp)?.dateValue(),
                        eventEndDate:       (d["eventEndDate"]   as? Timestamp)?.dateValue(),
                        pdfStorageURL:      d["pdfStorageURL"]   as? String,
                        pdfStorageBytes:    self.int64Value(d["pdfStorageBytes"]),
                        addToAppleWalletURL: d["addToAppleWalletURL"] as? String,
                        barcodeFormat:      d["barcodeFormat"]   as? String,
                        isDeleted:          d["isDeleted"]       as? Bool ?? false,
                        createdAt:          (d["createdAt"]      as? Timestamp)?.dateValue(),
                        updatedAt:          (d["updatedAt"]      as? Timestamp)?.dateValue(),
                        createdBy:          d["createdBy"]       as? String,
                        createdByName:      d["createdByName"]   as? String,
                        updatedBy:          d["updatedBy"]       as? String,
                        updatedByName:      d["updatedByName"]   as? String
                    )

                    switch diff.type {
                    case .added, .modified: return .upsert(dto)
                    case .removed:          return .remove(doc.documentID)
                    }
                }

                if !changes.isEmpty { onChange(changes) }
            }
    }

    // MARK: - One-shot fetch (per push deep link)

    /// Fetch one-shot (no listener) di tutti i biglietti non eliminati della famiglia.
    /// Usata da `AppCoordinator.openWalletTicketFromPush` quando l'utente apre la
    /// notifica e il listener non è ancora attivo.
    func fetchAllOnce(familyId: String) async throws -> [WalletTicketDTO] {
        let snap = try await col(familyId: familyId)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()

        return snap.documents.map { doc in
            let d = doc.data()
            return WalletTicketDTO(
                id: doc.documentID,
                familyId: familyId,
                titleEnc:           d["titleEnc"]        as? String,
                locationEnc:        d["locationEnc"]     as? String,
                seatEnc:            d["seatEnc"]         as? String,
                bookingCodeEnc:     d["bookingCodeEnc"]  as? String,
                notesEnc:           d["notesEnc"]        as? String,
                barcodeTextEnc:     d["barcodeTextEnc"]  as? String,
                fileNameEnc:        d["fileNameEnc"]     as? String,
                kindRaw:            d["kind"]            as? String,
                emitter:            d["emitter"]         as? String,
                eventDate:          (d["eventDate"]      as? Timestamp)?.dateValue(),
                eventEndDate:       (d["eventEndDate"]   as? Timestamp)?.dateValue(),
                pdfStorageURL:      d["pdfStorageURL"]   as? String,
                pdfStorageBytes:    int64Value(d["pdfStorageBytes"]),
                addToAppleWalletURL: d["addToAppleWalletURL"] as? String,
                barcodeFormat:      d["barcodeFormat"]   as? String,
                isDeleted:          d["isDeleted"]       as? Bool ?? false,
                createdAt:          (d["createdAt"]      as? Timestamp)?.dateValue(),
                updatedAt:          (d["updatedAt"]      as? Timestamp)?.dateValue(),
                createdBy:          d["createdBy"]       as? String,
                createdByName:      d["createdByName"]   as? String,
                updatedBy:          d["updatedBy"]       as? String,
                updatedByName:      d["updatedByName"]   as? String
            )
        }
    }
}
