//
//  LoyaltyCardRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 20/08/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

// MARK: - DTO

/// Snapshot di un documento `loyaltyCards` su Firestore. A differenza di
/// `WalletTicketDTO`, tutti i campi sono in chiaro: nessuna cifratura (stesso
/// trattamento del campo `emitter` sui ticket).
struct LoyaltyCardDTO {
    let id: String
    let familyId: String

    let brandId: String?
    let brandName: String
    let cardNumber: String
    let barcodeFormat: String
    let note: String?
    let primaryColorHex: String
    let secondaryColorHex: String
    /// URL del logo del brand (in chiaro, come gli altri campi).
    let logoURL: String?

    /// Riferimenti alle foto fronte/retro della tessera fisica. Sono solo
    /// puntatori: il contenuto su Storage è cifrato (`LoyaltyCardPhotoStore`).
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

enum LoyaltyCardRemoteChange {
    case upsert(LoyaltyCardDTO)
    case remove(String)
}

// MARK: - Store

/// Remote store per le carte fedeltà del Wallet.
///
/// Path Firestore: `families/{familyId}/loyaltyCards/{cardId}`
///
/// Pattern speculare a `WalletRemoteStore`, ma senza cifratura né gestione
/// PDF/Storage (le carte fedeltà sono solo testo).
final class LoyaltyCardRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func stringArray(_ any: Any?) -> [String] {
        if let a = any as? [String] { return a }
        if let a = any as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }

    // MARK: - References

    private func ref(familyId: String, cardId: String) -> DocumentReference {
        db.collection("families")
            .document(familyId)
            .collection("loyaltyCards")
            .document(cardId)
    }

    private func col(familyId: String) -> CollectionReference {
        db.collection("families")
            .document(familyId)
            .collection("loyaltyCards")
    }

    // MARK: - Upsert

    func upsert(card: KBLoyaltyCard) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let snap = try await ref(familyId: card.familyId, cardId: card.id).getDocument()
        let isNew = !snap.exists

        var data: [String: Any] = [
            "schemaVersion": 1,

            "brandId":           card.brandId as Any,
            "brandName":         card.brandName,
            "cardNumber":        card.cardNumber,
            "barcodeFormat":     card.barcodeFormat,
            "note":              card.note as Any,
            "primaryColorHex":   card.primaryColorHex,
            "secondaryColorHex": card.secondaryColorHex,
            "logoURL":           card.logoURL as Any,

            "frontPhotoStorageURL":  card.frontPhotoStorageURL as Any,
            "frontPhotoStoragePath": card.frontPhotoStoragePath as Any,
            "backPhotoStorageURL":   card.backPhotoStorageURL as Any,
            "backPhotoStoragePath":  card.backPhotoStoragePath as Any,

            "visibilityScope":     KBLoyaltyCard.normalizedVisibilityScopeForLoyaltyCard(card.visibilityScope),
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
        KBLog.sync.kbInfo("[LoyaltyCardRemote] upsert OK id=\(card.id) familyId=\(card.familyId)")
    }

    // MARK: - Soft delete

    func softDelete(cardId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        try await ref(familyId: familyId, cardId: cardId).setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        KBLog.sync.kbInfo("[LoyaltyCardRemote] softDelete OK id=\(cardId) familyId=\(familyId)")
    }

    // MARK: - Realtime listener

    func listenLoyaltyCards(
        familyId: String,
        onChange: @escaping ([LoyaltyCardRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        KBLog.sync.kbInfo("[LoyaltyCardRemote] listen ATTACH familyId=\(familyId)")

        return col(familyId: familyId)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[LoyaltyCardRemote] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else { return }

                KBLog.sync.kbDebug("[LoyaltyCardRemote] snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count) fromCache=\(snap.metadata.isFromCache)")

                let changes: [LoyaltyCardRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let d = doc.data()

                    let dto = LoyaltyCardDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        brandId:            d["brandId"]            as? String,
                        brandName:          d["brandName"]          as? String ?? "",
                        cardNumber:         d["cardNumber"]         as? String ?? "",
                        barcodeFormat:      d["barcodeFormat"]      as? String ?? "code128",
                        note:               d["note"]               as? String,
                        primaryColorHex:    d["primaryColorHex"]    as? String ?? "#5856D6",
                        secondaryColorHex:  d["secondaryColorHex"]  as? String ?? "#3634A3",
                        logoURL:            d["logoURL"]            as? String,
                        frontPhotoStorageURL:  d["frontPhotoStorageURL"]  as? String,
                        frontPhotoStoragePath: d["frontPhotoStoragePath"] as? String,
                        backPhotoStorageURL:   d["backPhotoStorageURL"]   as? String,
                        backPhotoStoragePath:  d["backPhotoStoragePath"]  as? String,
                        isDeleted:          d["isDeleted"]          as? Bool ?? false,
                        createdAt:          (d["createdAt"]         as? Timestamp)?.dateValue(),
                        updatedAt:          (d["updatedAt"]         as? Timestamp)?.dateValue(),
                        createdBy:          d["createdBy"]          as? String,
                        createdByName:      d["createdByName"]      as? String,
                        updatedBy:          d["updatedBy"]          as? String,
                        updatedByName:      d["updatedByName"]      as? String,
                        visibilityScope:      d["visibilityScope"] as? String,
                        visibilityMemberIds:  d["visibilityMemberIds"] == nil
                            ? nil
                            : self.stringArray(d["visibilityMemberIds"])
                    )

                    switch diff.type {
                    case .added, .modified: return .upsert(dto)
                    case .removed:          return .remove(doc.documentID)
                    }
                }

                if !changes.isEmpty { onChange(changes) }
            }
    }

    // MARK: - One-shot fetch

    func fetchAllOnce(familyId: String) async throws -> [LoyaltyCardDTO] {
        let snap = try await col(familyId: familyId)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()

        return snap.documents.map { doc in
            let d = doc.data()
            return LoyaltyCardDTO(
                id: doc.documentID,
                familyId: familyId,
                brandId:            d["brandId"]            as? String,
                brandName:          d["brandName"]          as? String ?? "",
                cardNumber:         d["cardNumber"]         as? String ?? "",
                barcodeFormat:      d["barcodeFormat"]      as? String ?? "code128",
                note:               d["note"]               as? String,
                primaryColorHex:    d["primaryColorHex"]    as? String ?? "#5856D6",
                secondaryColorHex:  d["secondaryColorHex"]  as? String ?? "#3634A3",
                logoURL:            d["logoURL"]            as? String,
                frontPhotoStorageURL:  d["frontPhotoStorageURL"]  as? String,
                frontPhotoStoragePath: d["frontPhotoStoragePath"] as? String,
                backPhotoStorageURL:   d["backPhotoStorageURL"]   as? String,
                backPhotoStoragePath:  d["backPhotoStoragePath"]  as? String,
                isDeleted:          d["isDeleted"]          as? Bool ?? false,
                createdAt:          (d["createdAt"]         as? Timestamp)?.dateValue(),
                updatedAt:          (d["updatedAt"]         as? Timestamp)?.dateValue(),
                createdBy:          d["createdBy"]          as? String,
                createdByName:      d["createdByName"]      as? String,
                updatedBy:          d["updatedBy"]          as? String,
                updatedByName:      d["updatedByName"]      as? String,
                visibilityScope:      d["visibilityScope"] as? String,
                visibilityMemberIds:  d["visibilityMemberIds"] == nil
                    ? nil
                    : stringArray(d["visibilityMemberIds"])
            )
        }
    }
}
