//
//  ShoppingTripRemoteStore.swift
//  KidBox
//
//  Le spese fatte su Firestore: `families/{familyId}/shoppingTrips/{id}`.
//  Stessa forma del negozio remoto della lista spesa, da cui questi record
//  nascono.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

struct ShoppingTripRemoteDTO {
    let id: String
    let familyId: String
    let storeName: String?
    let total: Double
    let date: Date
    /// Righe dello scontrino, serializzate: viaggiano come stringa JSON, così
    /// il documento resta piatto e leggibile anche da un client che non le usa.
    let linesJson: String?
    let notes: String?
    let linkedExpenseId: String?
    let isDeleted: Bool
    let updatedAt: Date?
    let updatedBy: String?
    let createdBy: String?
}

enum ShoppingTripRemoteChange {
    case upsert(ShoppingTripRemoteDTO)
    case remove(String)
}

final class ShoppingTripRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func col(familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("shoppingTrips")
    }

    private func ref(familyId: String, tripId: String) -> DocumentReference {
        col(familyId: familyId).document(tripId)
    }

    // MARK: - Upsert

    func upsert(trip: KBShoppingTrip) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let snap = try await ref(familyId: trip.familyId, tripId: trip.id).getDocument()
        let isNew = !snap.exists

        var data: [String: Any] = [
            "storeName": trip.storeName as Any,
            "total": trip.total,
            "date": Timestamp(date: trip.date),
            "linesJson": trip.linesJson as Any,
            "notes": trip.notes as Any,
            "linkedExpenseId": trip.linkedExpenseId as Any,
            "isDeleted": false,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if isNew {
            data["createdAt"] = FieldValue.serverTimestamp()
            data["createdBy"] = trip.createdBy ?? uid
        }

        try await ref(familyId: trip.familyId, tripId: trip.id).setData(data, merge: true)
        KBLog.sync.kbInfo("[shoppingTrip] upsert OK id=\(trip.id) familyId=\(trip.familyId)")
    }

    // MARK: - Soft delete

    func softDelete(tripId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        try await ref(familyId: familyId, tripId: tripId).setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        KBLog.sync.kbInfo("[shoppingTrip] softDelete OK id=\(tripId) familyId=\(familyId)")
    }

    // MARK: - Realtime

    func listenShoppingTrips(
        familyId: String,
        onChange: @escaping ([ShoppingTripRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {

        KBLog.sync.kbInfo("[shoppingTrip] listen ATTACH familyId=\(familyId)")

        return col(familyId: familyId)
            .whereField("isDeleted", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[shoppingTrip] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else { return }

                let changes: [ShoppingTripRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let d = doc.data()

                    let dto = ShoppingTripRemoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        storeName: d["storeName"] as? String,
                        total: (d["total"] as? NSNumber)?.doubleValue ?? 0,
                        date: (d["date"] as? Timestamp)?.dateValue() ?? Date(),
                        linesJson: d["linesJson"] as? String,
                        notes: d["notes"] as? String,
                        linkedExpenseId: d["linkedExpenseId"] as? String,
                        isDeleted: d["isDeleted"] as? Bool ?? false,
                        updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
                        updatedBy: d["updatedBy"] as? String,
                        createdBy: d["createdBy"] as? String
                    )

                    switch diff.type {
                    case .added, .modified: return .upsert(dto)
                    case .removed:          return .remove(doc.documentID)
                    }
                }

                if !changes.isEmpty { onChange(changes) }
            }
    }
}
