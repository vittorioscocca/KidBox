//
//  KBPaymentCard.swift
//  KidBox
//
//  Created by vscocca on 03/10/26.
//

import Foundation
import SwiftData

/// Carta di pagamento (credito, debito, prepagata) custodita nel Wallet,
/// sezione «Pagamento». Inserimento solo manuale: nessuna lettura AI, e la
/// carta non entra nella memoria dell'assistente (`AgentMemoryBook`).
///
/// Tutto ciò che scrive l'utente è **cifrato** con la chiave di famiglia
/// (`WalletCryptoService`) e resta cifrato anche qui in SwiftData: i campi
/// `*Enc` contengono lo stesso base64(AES.GCM combined) che sta su
/// Firestore, e si decifrano solo al momento di mostrarli
/// (`PaymentCardPlain`). Così il numero non è mai in chiaro su disco.
///
/// In chiaro restano solo colore, puntatori alle foto (il blob su Storage è
/// cifrato), visibilità e metadati di sync. Il PIN c'è, su richiesta
/// esplicita dell'utente (03/10/2026), ed è il campo più protetto: mai sulla
/// carta disegnata, visibile e copiabile solo dopo Face ID. Il CVV invece no.
///
/// Visibilità di default `"private"` (solo chi la inserisce), a differenza
/// delle carte fedeltà: è una carta di pagamento.
@Model
final class KBPaymentCard {
    @Attribute(.unique) var id: String

    var familyId: String

    // MARK: - Contenuto cifrato (base64 di AES.GCM combined)

    /// Nome della carta scelto dall'utente (es. «Visa di Marco»). Opzionale.
    var labelEnc: String?
    /// Numero della carta, solo cifre.
    var cardNumberEnc: String?
    /// Intestatario come stampato sulla carta.
    var holderNameEnc: String?
    /// IBAN del conto collegato, senza spazi.
    var ibanEnc: String?
    /// Scadenza nel formato `MM/AA`.
    var expiryEnc: String?
    /// Nota libera.
    var notesEnc: String?
    /// PIN della carta, solo cifre.
    var pinEnc: String?

    // MARK: - In chiaro

    /// Colore della carta in esadecimale (es. `"#1C1C1E"`).
    var colorHex: String

    /// Foto fronte/retro: puntatori al blob CIFRATO su Storage
    /// (`PaymentCardPhotoStore`), stessi nomi delle carte fedeltà.
    var frontPhotoStorageURL: String?
    var frontPhotoStoragePath: String?
    var backPhotoStorageURL: String?
    var backPhotoStoragePath: String?

    /// `"family"` | `"members"` | `"private"`. Default `"private"`.
    var visibilityScope: String?
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
        colorHex: String = PaymentCardPalette.defaultHex,
        visibilityScope: String = KBVisibilityScope.onlyCreator,
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
        self.colorHex = colorHex
        self.visibilityScope = Self.normalizedVisibilityScope(visibilityScope)
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

    /// Scope effettivo: `nil`/vuoto/sconosciuto → `private`.
    static func normalizedVisibilityScope(_ raw: String?) -> String {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch t {
        case KBVisibilityScope.family, KBVisibilityScope.members, KBVisibilityScope.onlyCreator:
            return t
        default:
            return KBVisibilityScope.onlyCreator
        }
    }

    func isVisible(to currentUid: String?) -> Bool {
        KBVisibilityScope.isVisible(
            scope: Self.normalizedVisibilityScope(visibilityScope),
            memberIds: visibilityMemberIds ?? [],
            createdBy: createdBy.isEmpty ? nil : createdBy,
            currentUid: currentUid
        )
    }
}

/// Il wipe locale (uscita dalla famiglia, logout) la cancella insieme al resto.
extension KBPaymentCard: HasFamilyId {}

// MARK: - Vista in chiaro

/// I campi di una `KBPaymentCard` decifrati, solo in memoria e solo per il
/// tempo di una schermata. `isUnreadable` = la chiave di famiglia non c'è o
/// il blob non si apre: la UI lo dice invece di mostrare campi vuoti.
struct PaymentCardPlain {
    var label: String = ""
    var cardNumber: String = ""
    var holderName: String = ""
    var iban: String = ""
    var expiry: String = ""
    var notes: String = ""
    var pin: String = ""
    var isUnreadable = false

    init() {}

    init(card: KBPaymentCard, userId: String?) {
        guard let uid = userId, !uid.isEmpty else {
            isUnreadable = true
            return
        }
        let fid = card.familyId
        func open(_ b64: String?) throws -> String {
            try WalletCryptoService.decryptOptional(b64, familyId: fid, userId: uid) ?? ""
        }
        do {
            label = try open(card.labelEnc)
            cardNumber = try open(card.cardNumberEnc)
            holderName = try open(card.holderNameEnc)
            iban = try open(card.ibanEnc)
            expiry = try open(card.expiryEnc)
            notes = try open(card.notesEnc)
            pin = try open(card.pinEnc)
        } catch {
            self = PaymentCardPlain()
            isUnreadable = true
        }
    }

    var network: PaymentCardNetwork { PaymentCardNetwork.detect(cardNumber) }

    var last4: String { String(cardNumber.suffix(4)) }

    /// Titolo della carta: il nome scelto, altrimenti circuito + ultime cifre.
    var displayTitle: String {
        if !label.isEmpty { return label }
        if cardNumber.count >= 4 { return "\(network.displayName) •••• \(last4)" }
        return network.displayName
    }

    /// Titolo sulla carta disegnata: il circuito sta già a destra, quindi
    /// senza nome non si ripete (resta «Carta» solo se il circuito è ignoto).
    var tileTitle: String {
        if !label.isEmpty { return label }
        return network == .other ? network.displayName : ""
    }

    /// Cifra i campi su `card`. Una stringa vuota diventa `nil`.
    func seal(into card: KBPaymentCard, userId: String) throws {
        let fid = card.familyId
        func close(_ s: String) throws -> String? {
            try WalletCryptoService.encryptOptional(s, familyId: fid, userId: userId)
        }
        card.labelEnc = try close(label)
        card.cardNumberEnc = try close(cardNumber)
        card.holderNameEnc = try close(holderName)
        card.ibanEnc = try close(iban)
        card.expiryEnc = try close(expiry)
        card.notesEnc = try close(notes)
        card.pinEnc = try close(pin)
    }
}
