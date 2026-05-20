//
//  ClinicalExtractedValuesRemoteStore.swift
//  KidBox
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Sottocollezione `extractedValues` su `families/{familyId}/documents/{docId}`.
enum ClinicalExtractedValuesRemoteStore {

    static func replaceForDocument(
        familyId: String,
        documentId: String,
        values: [ExtractedMedicalValue]
    ) async {
        guard let uid = Auth.auth().currentUser?.uid, !familyId.isEmpty, !documentId.isEmpty else { return }
        let docValues = values.filter { $0.sourceId == "doc:\(documentId)" }
        guard !docValues.isEmpty else { return }
        let db = Firestore.firestore()
        let col = db.collection("families").document(familyId)
            .collection("documents").document(documentId)
            .collection("extractedValues")

        do {
            let existing = try await col.getDocuments()
            for d in existing.documents {
                try await d.reference.delete()
            }
            for v in docValues {
                let ref = col.document()
                try await ref.setData([
                    "kind": v.kind.rawValue,
                    "parameterName": v.parameterName,
                    "numericValue": v.numericValue as Any,
                    "textValue": v.textValue as Any,
                    "unit": v.unit as Any,
                    "systolic": v.systolic as Any,
                    "diastolic": v.diastolic as Any,
                    "lesionType": v.lesionType as Any,
                    "dimensionMm": v.dimensionMm as Any,
                    "measuredAt": Timestamp(date: v.date),
                    "sourceLabel": v.sourceLabel,
                    "updatedBy": uid,
                    "updatedAt": FieldValue.serverTimestamp(),
                ], merge: false)
            }
            KBLog.sync.kbInfo("extractedValues saved docId=\(documentId) count=\(docValues.count)")
        } catch {
            KBLog.sync.kbError("extractedValues save failed docId=\(documentId): \(error.localizedDescription)")
        }
    }
}
