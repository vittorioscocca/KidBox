//
//  PaymentCardRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 03/10/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - DTO

/// Snapshot di un documento `paymentCards`. I campi `*Enc` arrivano e
/// ripartono così come sono: il client li cifra in `PaymentCardPlain.seal`
/// e li decifra solo per mostrarli.
struct PaymentCardDTO {
    let id: String
    let familyId: String

    let labelEnc: String?
    let cardNumberEnc: String?
    let holderNameEnc: String?
    let ibanEnc: String?
    let expiryEnc: String?
    let notesEnc: String?
    let pinEnc: String?

    let colorHex: String

    let frontPhotoStorageURL: String?
    let frontPhotoStoragePath: String?
    let backPhotoStorageURL: String?
    let backPhotoStoragePath: String?

    let isDeleted: Bool

    let createdAt: Date?
    let updatedAt: Date?

    let createdBy: String?
    let createdByName: String?
    let updatedBy: String?
    let updatedByName: String?

    let visibilityScope: String?
    let visibilityMemberIds: [String]?
}

enum PaymentCardRemoteChange {
    case upsert(PaymentCardDTO)
    case remove(String)
}

// MARK: - Store

/// Path Firestore: `families/{familyId}/paymentCards/{cardId}`.
///
/// Coperto dalla regola generica delle sottocollezioni di famiglia (lettura e
/// scrittura ai membri): nessuna regola dedicata. Nessuna Cloud Function lo
/// legge — niente push all'aggiunta, a differenza di biglietti e carte
/// fedeltà: la carta è di default privata.
final class PaymentCardRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func ref(familyId: String, cardId: String) -> DocumentReference {
        col(familyId: familyId).document(cardId)
    }

    private func col(familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("paymentCards")
    }

    // MARK: - Upsert

    func upsert(card: KBPaymentCard) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let snap = try await ref(familyId: card.familyId, cardId: card.id).getDocument()
        let isNew = !snap.exists

        var data: [String: Any] = [
            "schemaVersion": 1,

            "labelEnc":      card.labelEnc as Any,
            "cardNumberEnc": card.cardNumberEnc as Any,
            "holderNameEnc": card.holderNameEnc as Any,
            "ibanEnc":       card.ibanEnc as Any,
            "expiryEnc":     card.expiryEnc as Any,
            "notesEnc":      card.notesEnc as Any,
            "pinEnc":        card.pinEnc as Any,

            "colorHex": card.colorHex,

            "frontPhotoStorageURL":  card.frontPhotoStorageURL as Any,
            "frontPhotoStoragePath": card.frontPhotoStoragePath as Any,
            "backPhotoStorageURL":   card.backPhotoStorageURL as Any,
            "backPhotoStoragePath":  card.backPhotoStoragePath as Any,

            "visibilityScope":     KBPaymentCard.normalizedVisibilityScope(card.visibilityScope),
            "visibilityMemberIds": card.visibilityMemberIds ?? [],

            "isDeleted":     false,
            "updatedBy":     uid,
            "updatedByName": card.updatedByName,
            "updatedAt":     FieldValue.serverTimestamp()
        ]

        if isNew {
            data["createdAt"]     = FieldValue.serverTimestamp()
            data["createdBy"]     = card.createdBy.isEmpty ? uid : card.createdBy
            data["createdByName"] = card.createdByName
        }

        try await ref(familyId: card.familyId, cardId: card.id).setData(data, merge: true)
        KBLog.sync.kbInfo("[PaymentCardRemote] upsert OK id=\(card.id) familyId=\(card.familyId)")
    }

    // MARK: - Soft delete

    /// Il tombstone svuota anche i campi cifrati: un documento cancellato non
    /// deve continuare a portarsi dietro il numero, nemmeno cifrato.
    func softDelete(cardId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        try await ref(familyId: familyId, cardId: cardId).setData([
            "isDeleted": true,
            "labelEnc": FieldValue.delete(),
            "cardNumberEnc": FieldValue.delete(),
            "holderNameEnc": FieldValue.delete(),
            "ibanEnc": FieldValue.delete(),
            "expiryEnc": FieldValue.delete(),
            "notesEnc": FieldValue.delete(),
            "pinEnc": FieldValue.delete(),
            "frontPhotoStorageURL": FieldValue.delete(),
            "frontPhotoStoragePath": FieldValue.delete(),
            "backPhotoStorageURL": FieldValue.delete(),
            "backPhotoStoragePath": FieldValue.delete(),
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        KBLog.sync.kbInfo("[PaymentCardRemote] softDelete OK id=\(cardId) familyId=\(familyId)")
    }

    // MARK: - Realtime listener

    func listenPaymentCards(
        familyId: String,
        onChange: @escaping ([PaymentCardRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        KBLog.sync.kbInfo("[PaymentCardRemote] listen ATTACH familyId=\(familyId)")

        return col(familyId: familyId)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[PaymentCardRemote] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else { return }

                let changes: [PaymentCardRemoteChange] = snap.documentChanges.map { diff in
                    switch diff.type {
                    case .added, .modified: return .upsert(Self.dto(diff.document, familyId: familyId))
                    case .removed:          return .remove(diff.document.documentID)
                    }
                }

                if !changes.isEmpty { onChange(changes) }
            }
    }

    // MARK: - One-shot fetch

    func fetchAllOnce(familyId: String) async throws -> [PaymentCardDTO] {
        let snap = try await col(familyId: familyId)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()
        return snap.documents.map { Self.dto($0, familyId: familyId) }
    }

    // MARK: - Mapping

    private static func dto(_ doc: DocumentSnapshot, familyId: String) -> PaymentCardDTO {
        let d = doc.data() ?? [:]
        func str(_ key: String) -> String? {
            guard let s = d[key] as? String, !s.isEmpty else { return nil }
            return s
        }
        return PaymentCardDTO(
            id: doc.documentID,
            familyId: familyId,
            labelEnc: str("labelEnc"),
            cardNumberEnc: str("cardNumberEnc"),
            holderNameEnc: str("holderNameEnc"),
            ibanEnc: str("ibanEnc"),
            expiryEnc: str("expiryEnc"),
            notesEnc: str("notesEnc"),
            pinEnc: str("pinEnc"),
            colorHex: str("colorHex") ?? PaymentCardPalette.defaultHex,
            frontPhotoStorageURL: str("frontPhotoStorageURL"),
            frontPhotoStoragePath: str("frontPhotoStoragePath"),
            backPhotoStorageURL: str("backPhotoStorageURL"),
            backPhotoStoragePath: str("backPhotoStoragePath"),
            isDeleted: d["isDeleted"] as? Bool ?? false,
            createdAt: (d["createdAt"] as? Timestamp)?.dateValue(),
            updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
            createdBy: str("createdBy"),
            createdByName: str("createdByName"),
            updatedBy: str("updatedBy"),
            updatedByName: str("updatedByName"),
            visibilityScope: str("visibilityScope"),
            visibilityMemberIds: (d["visibilityMemberIds"] as? [Any])?.compactMap { $0 as? String }
        )
    }
}
