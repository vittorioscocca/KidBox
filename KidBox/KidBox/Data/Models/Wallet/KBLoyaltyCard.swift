//
//  KBLoyaltyCard.swift
//  KidBox
//
//  Created by vscocca on 20/08/26.
//

import Foundation
import SwiftData

/// Carta fedeltà custodita nel "Wallet" di KidBox (sezione "Carte").
///
/// Pattern speculare a `KBWalletTicket`:
/// - sync via `SyncCenter+LoyaltyCards` con LWW su `updatedAt`
/// - `isDeleted` come tombstone soft-delete remoto
///
/// Differenze rispetto ai Biglietti:
/// - **visibilità di default `"family"`** (condivisa con tutta la famiglia),
///   non `"private"`/onlyCreator — richiesta esplicita dell'utente: le carte
///   fedeltà sono pensate per essere usate da qualsiasi membro della famiglia.
/// - **niente cifratura** del numero carta / nome brand: stesso trattamento
///   di `emitter` sui ticket, campo a bassa sensibilità (equivalente a una
///   tessera fisica in un portafoglio condiviso).
/// - **niente PDF/reminder**: solo testo (numero carta) + eventuali foto
///   fronte/retro opzionali (fallback, non flusso principale).
@Model
final class KBLoyaltyCard {
    @Attribute(.unique) var id: String

    var familyId: String

    // MARK: - Content

    /// Id del brand nel catalogo (`LoyaltyCardCatalog`), `nil` se "carta non in elenco".
    var brandId: String?

    /// Nome del negozio/brand mostrato sulla card. Sempre valorizzato (anche
    /// per le carte "non in elenco", dove è inserito a mano dall'utente).
    var brandName: String

    /// Numero/codice della carta fedeltà, in chiaro (non cifrato).
    var cardNumber: String

    /// Raw value del formato barcode (es. "ean13", "code128", "qr").
    var barcodeFormat: String

    /// Nota libera opzionale (es. "usare al bancone gioielleria").
    var note: String?

    /// Colore primario in esadecimale (es. "#E30613"). Per brand da catalogo
    /// rispecchia `LoyaltyCardBrand.primaryColorHex`; per carte "non in
    /// elenco" è scelto dall'utente nel form.
    var primaryColorHex: String

    /// Colore secondario in esadecimale, usato per il gradient della card.
    var secondaryColorHex: String

    /// URL del logo del brand, copiato da `LoyaltyCardBrand.logoURL` al momento
    /// della creazione della carta: così la card continua a mostrare il logo
    /// giusto anche se in futuro il catalogo bundle cambia o rimuove il brand.
    /// Opzionale — come gli altri campi opzionali di questo modello, permette
    /// la migrazione SwiftData automatica sulle carte già salvate (che restano
    /// col solo wordmark testuale finché non vengono ricreate).
    var logoURL: String?

    // MARK: - Foto fronte/retro della tessera fisica (opzionali)
    //
    // Acquisite con lo scanner VisionKit (`WalletDocumentScannerView`) e
    // caricate **cifrate** su Firebase Storage sotto
    // `families/{familyId}/loyaltyCards/{cardId}/…` (vedi `LoyaltyCardPhotoStore`).
    // A differenza del numero carta — che resta in chiaro per scelta — la foto
    // della tessera può mostrare il nome dell'intestatario, quindi passa da
    // `DocumentCryptoService` come i documenti d'identità del Wallet.
    //
    // Tutte opzionali come gli altri campi aggiunti dopo il rilascio: permette
    // la migrazione SwiftData automatica sulle carte già salvate, che restano
    // semplicemente senza foto finché l'utente non le acquisisce.

    /// URL di download della foto del FRONTE (blob cifrato su Storage).
    var frontPhotoStorageURL: String?
    /// Path Storage della foto del fronte — identificatore stabile usato per
    /// scaricare e per il cleanup in cancellazione (l'URL può scadere/ruotare).
    var frontPhotoStoragePath: String?

    /// URL di download della foto del RETRO (blob cifrato su Storage).
    var backPhotoStorageURL: String?
    /// Path Storage della foto del retro. Vedi `frontPhotoStoragePath`.
    var backPhotoStoragePath: String?

    /// `"family"` | `"members"` | `"private"`. Default `"family"` (condivisa
    /// con tutta la famiglia — a differenza dei Biglietti).
    var visibilityScope: String?
    /// Popolato solo se lo scope effettivo è `"members"`.
    var visibilityMemberIds: [String]?

    // MARK: - Authorship
    var createdBy: String = ""
    var createdByName: String = ""
    var updatedBy: String = ""
    var updatedByName: String = ""

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

    init(
        id: String = UUID().uuidString,
        familyId: String,
        brandId: String? = nil,
        brandName: String = "",
        cardNumber: String = "",
        barcodeFormat: String = "code128",
        note: String? = nil,
        primaryColorHex: String = "#5856D6",
        secondaryColorHex: String = "#3634A3",
        logoURL: String? = nil,
        visibilityScope: String = KBVisibilityScope.family,
        visibilityMemberIds: [String] = [],
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
        self.brandId = brandId
        self.brandName = brandName
        self.cardNumber = cardNumber
        self.barcodeFormat = barcodeFormat
        self.note = note
        self.primaryColorHex = primaryColorHex
        self.secondaryColorHex = secondaryColorHex
        self.logoURL = logoURL
        self.visibilityScope = Self.normalizedVisibilityScopeForLoyaltyCard(visibilityScope)
        self.visibilityMemberIds = visibilityMemberIds
        self.createdBy = createdBy
        self.createdByName = createdByName
        self.updatedBy = updatedBy
        self.updatedByName = updatedByName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.syncStateRaw = KBSyncState.synced.rawValue
    }

    /// Scope effettivo: `nil`/vuoto/sconosciuto → `family` (default carte fedeltà,
    /// a differenza dei ticket che di default sono `private`).
    static func normalizedVisibilityScopeForLoyaltyCard(_ raw: String?) -> String {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return KBVisibilityScope.family }
        switch t {
        case KBVisibilityScope.family, KBVisibilityScope.members, KBVisibilityScope.onlyCreator:
            return t
        default:
            return KBVisibilityScope.family
        }
    }

    func isVisible(to currentUid: String?) -> Bool {
        let scope = Self.normalizedVisibilityScopeForLoyaltyCard(visibilityScope)
        return KBVisibilityScope.isVisible(
            scope: scope,
            memberIds: visibilityMemberIds ?? [],
            createdBy: createdBy.isEmpty ? nil : createdBy,
            currentUid: currentUid
        )
    }
}
