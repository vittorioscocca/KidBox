//
//  HousePaymentRemoteStore.swift
//  KidBox
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct HousePaymentRemoteDTO {
    let id: String
    let familyId: String
    let name: String
    let typeRaw: String
    let subtypeRaw: String?
    let importo: Double?
    let giornoDiScadenzaMensile: Int?
    let dataScadenza: Date?
    let dataScadenzaContratto: Date?
    let fornitore: String?
    let note: String?
    let reminderOn: Bool
    let isDeleted: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let createdBy: String?
    let updatedBy: String?
}

enum HousePaymentRemoteChange {
    case upsert(HousePaymentRemoteDTO)
    case remove(String)
}

final class HousePaymentRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func ref(familyId: String, paymentId: String) -> DocumentReference {
        db.collection("families")
            .document(familyId)
            .collection("housePayments")
            .document(paymentId)
    }

    private func col(familyId: String) -> CollectionReference {
        db.collection("families")
            .document(familyId)
            .collection("housePayments")
    }

    func upsert(item: KBHousePayment) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let snap = try await ref(familyId: item.familyId, paymentId: item.id).getDocument()
        let isNew = !snap.exists

        var data: [String: Any] = [
            "name": item.name,
            "typeRaw": item.typeRaw,
            "isDeleted": false,
            "reminderOn": item.reminderOn,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if isNew { data["createdAt"] = FieldValue.serverTimestamp() }

        data["subtypeRaw"] = item.subtypeRaw as Any
        data["importo"] = item.importo as Any
        data["giornoDiScadenzaMensile"] = item.giornoDiScadenzaMensile as Any
        data["dataScadenza"] = item.dataScadenza.map { Timestamp(date: $0) } as Any
        data["dataScadenzaContratto"] = item.dataScadenzaContratto.map { Timestamp(date: $0) } as Any
        data["fornitore"] = item.fornitore as Any
        data["note"] = item.note as Any

        if isNew { data["createdBy"] = item.createdBy.isEmpty ? uid : item.createdBy }

        try await ref(familyId: item.familyId, paymentId: item.id).setData(data, merge: true)
        KBLog.sync.kbInfo("[HousePaymentRemote] upsert OK id=\(item.id) familyId=\(item.familyId)")
    }

    func softDelete(paymentId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        try await ref(familyId: familyId, paymentId: paymentId).setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        KBLog.sync.kbInfo("[HousePaymentRemote] softDelete OK id=\(paymentId) familyId=\(familyId)")
    }

    func listenHousePayments(
        familyId: String,
        onChange: @escaping ([HousePaymentRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {

        KBLog.sync.kbInfo("[HousePaymentRemote] listenHousePayments ATTACH familyId=\(familyId)")

        return col(familyId: familyId)
            .whereField("isDeleted", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[HousePaymentRemote] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else { return }

                let changes: [HousePaymentRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let d = doc.data()

                    guard let name = d["name"] as? String, !name.isEmpty else { return nil }

                    let typeRaw = (d["typeRaw"] as? String) ?? KidBoxHousePaymentType.altro.rawValue

                    let giorno: Int? = {
                        if let i = d["giornoDiScadenzaMensile"] as? Int { return i }
                        if let n = d["giornoDiScadenzaMensile"] as? NSNumber { return n.intValue }
                        return nil
                    }()

                    let importo: Double? = {
                        if let x = d["importo"] as? Double { return x }
                        if let n = d["importo"] as? NSNumber { return n.doubleValue }
                        return nil
                    }()

                    let dto = HousePaymentRemoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        name: name,
                        typeRaw: typeRaw,
                        subtypeRaw: d["subtypeRaw"] as? String,
                        importo: importo,
                        giornoDiScadenzaMensile: giorno,
                        dataScadenza: (d["dataScadenza"] as? Timestamp)?.dateValue(),
                        dataScadenzaContratto: (d["dataScadenzaContratto"] as? Timestamp)?.dateValue(),
                        fornitore: d["fornitore"] as? String,
                        note: d["note"] as? String,
                        reminderOn: d["reminderOn"] as? Bool ?? true,
                        isDeleted: d["isDeleted"] as? Bool ?? false,
                        createdAt: (d["createdAt"] as? Timestamp)?.dateValue(),
                        updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
                        createdBy: d["createdBy"] as? String,
                        updatedBy: d["updatedBy"] as? String
                    )

                    switch diff.type {
                    case .added, .modified: return .upsert(dto)
                    case .removed: return .remove(doc.documentID)
                    }
                }

                if !changes.isEmpty { onChange(changes) }
            }
    }
}
