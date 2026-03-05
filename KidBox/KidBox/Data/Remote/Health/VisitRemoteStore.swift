//
//  VisitRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 05/03/26.
//


import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - DTO

struct RemoteVisitDTO {
    let id:                     String
    let familyId:               String
    let childId:                String
    let date:                   Date
    let doctorName:             String?
    let doctorSpecializationRaw:String?
    let travelDetailsData:      Data?
    let reason:                 String
    let diagnosis:              String?
    let recommendations:        String?
    let linkedTreatmentIds:     [String]
    let asNeededDrugsData:      Data?
    let therapyTypesRaw:        [String]
    let prescribedExamsData:    Data?
    let photoURLs:              [String]
    let notes:                  String?
    let nextVisitDate:          Date?
    let nextVisitReason:        String?
    let isDeleted:              Bool
    let createdBy:              String?
    let updatedBy:              String
    let createdAt:              Date?
    let updatedAt:              Date?
}

// MARK: - Remote changes

enum VisitRemoteChange {
    case upsert(RemoteVisitDTO)
    case remove(String)
}

// MARK: - Store

final class VisitRemoteStore {
    
    private let db = Firestore.firestore()
    
    // MARK: - Listen
    
    func listenAllVisits(
        familyId: String,
        onChange: @escaping ([VisitRemoteChange]) -> Void,
        onError:  @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection("families")
            .document(familyId)
            .collection("medicalVisits")
            .addSnapshotListener { snap, err in
                if let err { onError(err); return }
                guard let snap else { return }
                let changes: [VisitRemoteChange] = snap.documentChanges.compactMap { diff in
                    if diff.type == .removed { return .remove(diff.document.documentID) }
                    guard let dto = Self.decode(diff.document, familyId: familyId) else { return nil }
                    return .upsert(dto)
                }
                if !changes.isEmpty { onChange(changes) }
            }
    }
    
    // MARK: - Upsert
    
    func upsertVisit(_ dto: RemoteVisitDTO) async throws {
        var data: [String: Any] = [
            "familyId":          dto.familyId,
            "childId":           dto.childId,
            "date":              Timestamp(date: dto.date),
            "reason":            dto.reason,
            "linkedTreatmentIds": dto.linkedTreatmentIds,
            "therapyTypesRaw":   dto.therapyTypesRaw,
            "photoURLs":         dto.photoURLs,
            "isDeleted":         dto.isDeleted,
            "updatedBy":         dto.updatedBy,
            "updatedAt":         Timestamp(date: dto.updatedAt ?? Date()),
        ]
        if let v = dto.doctorName              { data["doctorName"]              = v }
        if let v = dto.doctorSpecializationRaw { data["doctorSpecializationRaw"] = v }
        if let v = dto.diagnosis               { data["diagnosis"]               = v }
        if let v = dto.recommendations         { data["recommendations"]         = v }
        if let v = dto.notes                   { data["notes"]                   = v }
        if let v = dto.nextVisitDate           { data["nextVisitDate"]           = Timestamp(date: v) }
        if let v = dto.nextVisitReason         { data["nextVisitReason"]         = v }
        if let v = dto.createdBy               { data["createdBy"]               = v }
        if let v = dto.createdAt               { data["createdAt"]               = Timestamp(date: v) }
        
        // Blob fields: Base64 encode for Firestore (Data non è un tipo nativo Firestore)
        if let v = dto.travelDetailsData    { data["travelDetailsData"]    = v.base64EncodedString() }
        if let v = dto.asNeededDrugsData    { data["asNeededDrugsData"]    = v.base64EncodedString() }
        if let v = dto.prescribedExamsData  { data["prescribedExamsData"]  = v.base64EncodedString() }
        
        try await db.collection("families")
            .document(dto.familyId)
            .collection("medicalVisits")
            .document(dto.id)
            .setData(data, merge: true)
    }
    
    // MARK: - Soft delete
    
    func deleteVisit(familyId: String, visitId: String) async throws {
        let uid = Auth.auth().currentUser?.uid ?? "remote"
        try await db.collection("families")
            .document(familyId)
            .collection("medicalVisits")
            .document(visitId)
            .updateData([
                "isDeleted": true,
                "updatedBy": uid,
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }
    
    // MARK: - Decode
    
    private static func decode(_ doc: QueryDocumentSnapshot, familyId: String) -> RemoteVisitDTO? {
        let d = doc.data()
        guard
            let childId = d["childId"] as? String,
            let date    = (d["date"] as? Timestamp)?.dateValue()
        else { return nil }
        
        func data64(_ key: String) -> Data? {
            guard let s = d[key] as? String else { return nil }
            return Data(base64Encoded: s)
        }
        
        return RemoteVisitDTO(
            id:                      doc.documentID,
            familyId:                familyId,
            childId:                 childId,
            date:                    date,
            doctorName:              d["doctorName"]              as? String,
            doctorSpecializationRaw: d["doctorSpecializationRaw"] as? String,
            travelDetailsData:       data64("travelDetailsData"),
            reason:                  d["reason"]                  as? String ?? "",
            diagnosis:               d["diagnosis"]               as? String,
            recommendations:         d["recommendations"]         as? String,
            linkedTreatmentIds:      d["linkedTreatmentIds"]      as? [String] ?? [],
            asNeededDrugsData:       data64("asNeededDrugsData"),
            therapyTypesRaw:         d["therapyTypesRaw"]         as? [String] ?? [],
            prescribedExamsData:     data64("prescribedExamsData"),
            photoURLs:               d["photoURLs"]               as? [String] ?? [],
            notes:                   d["notes"]                   as? String,
            nextVisitDate:           (d["nextVisitDate"]          as? Timestamp)?.dateValue(),
            nextVisitReason:         d["nextVisitReason"]         as? String,
            isDeleted:               d["isDeleted"]               as? Bool ?? false,
            createdBy:               d["createdBy"]               as? String,
            updatedBy:               d["updatedBy"]               as? String ?? "remote",
            createdAt:               (d["createdAt"]              as? Timestamp)?.dateValue(),
            updatedAt:               (d["updatedAt"]              as? Timestamp)?.dateValue()
        )
    }
}
