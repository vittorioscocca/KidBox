//
//  KBWalletTicket.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import Foundation
import SwiftData

/// Biglietto custodito nel "Wallet" di KidBox.
///
/// Pattern speculare a `KBNote`:
/// - sync via `SyncCenter+Wallet` con LWW su `updatedAt`
/// - `isDeleted` come tombstone soft-delete remoto
/// - campi sensibili (titolo/luogo/posto/PNR/note) cifrati lato `WalletRemoteStore`
///   prima dell'upload su Firestore
/// - PDF cifrato e caricato su Firebase Storage da `WalletPDFStore`,
///   l'URL pubblico è salvato in `pdfStorageURL`
@Model
final class KBWalletTicket {
    @Attribute(.unique) var id: String

    var familyId: String

    // MARK: - Content
    var title: String

    /// Categoria del biglietto. Persisted come raw String per resilienza alle
    /// migrazioni dell'enum (stesso pattern di `KBSyncState`).
    var kindRaw: String

    var eventDate: Date?
    var eventEndDate: Date?

    var location: String?
    var seat: String?
    var bookingCode: String?
    var notes: String?

    /// Nome dell'emittente/vettore riconosciuto dal parser (es. "Trenitalia",
    /// "Ryanair", "Moby", "FlixBus"). Usato da `WalletEmitterIcon` per scegliere
    /// un'icona più specifica sulla card. Campo a bassa sensibilità → sincronizzato
    /// in chiaro su Firestore in modo che tutti i membri vedano la stessa icona
    /// senza dover scaricare e riparsare il PDF.
    var emitter: String?

    // MARK: - PDF
    /// URL pubblico Firebase Storage del PDF cifrato (AES-GCM combined).
    var pdfStorageURL: String?

    /// Nome originale del file PDF caricato (per UI / share).
    var pdfFileName: String?

    /// Dimensione del blob cifrato salvato su Firebase Storage (in byte).
    /// Opzionale per retrocompatibilità: i ticket pre-esistenti alla migrazione
    /// non hanno questo campo. Il codice usa `0` quando `nil`.
    var pdfStorageBytes: Int64?

    /// Anteprima ~200x280 della prima pagina del PDF (JPEG ~50KB).
    /// Generata client-side da `WalletPDFParser` per evitare di scaricare
    /// il PDF intero solo per popolare la card della home.
    @Attribute(.externalStorage) var pdfThumbnailData: Data?

    // MARK: - Apple Wallet integration
    /// Link "Add to Apple Wallet" estratto dal PDF (se presente).
    /// Aperto direttamente da `WalletTicketDetailView` con `PKAddPassesViewController`
    /// se il content-type è `application/vnd.apple.pkpass`, altrimenti via Safari.
    var addToAppleWalletURL: String?

    /// Testo del primo barcode/QR/Aztec/PDF417 trovato dal `WalletPDFParser`.
    /// Mostrato a tutto schermo nella detail view per il transito al tornello
    /// senza dover scrollare il PDF.
    var extractedBarcodeText: String?

    /// Tipo di simbologia del barcode (qr, aztec, pdf417, code128, ...).
    var extractedBarcodeFormat: String?

    // MARK: - Authorship
    var createdBy: String
    var createdByName: String
    var updatedBy: String
    var updatedByName: String

    // MARK: - Timestamps
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Sync
    var isDeleted: Bool
    var syncStateRaw: Int
    var lastSyncError: String?

    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    var kind: KBWalletTicketKind {
        get { KBWalletTicketKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        title: String = "",
        kind: KBWalletTicketKind = .other,
        eventDate: Date? = nil,
        eventEndDate: Date? = nil,
        location: String? = nil,
        seat: String? = nil,
        bookingCode: String? = nil,
        notes: String? = nil,
        emitter: String? = nil,
        pdfStorageURL: String? = nil,
        pdfFileName: String? = nil,
        pdfStorageBytes: Int64? = nil,
        pdfThumbnailData: Data? = nil,
        addToAppleWalletURL: String? = nil,
        extractedBarcodeText: String? = nil,
        extractedBarcodeFormat: String? = nil,
        createdBy: String,
        createdByName: String,
        updatedBy: String,
        updatedByName: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.title = title
        self.kindRaw = kind.rawValue
        self.eventDate = eventDate
        self.eventEndDate = eventEndDate
        self.location = location
        self.seat = seat
        self.bookingCode = bookingCode
        self.notes = notes
        self.emitter = emitter
        self.pdfStorageURL = pdfStorageURL
        self.pdfFileName = pdfFileName
        if let pdfStorageBytes {
            self.pdfStorageBytes = max(0, pdfStorageBytes)
        } else {
            self.pdfStorageBytes = nil
        }
        self.pdfThumbnailData = pdfThumbnailData
        self.addToAppleWalletURL = addToAppleWalletURL
        self.extractedBarcodeText = extractedBarcodeText
        self.extractedBarcodeFormat = extractedBarcodeFormat
        self.createdBy = createdBy
        self.createdByName = createdByName
        self.updatedBy = updatedBy
        self.updatedByName = updatedByName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.syncStateRaw = KBSyncState.synced.rawValue
    }
}
