//
//  VisitRemoteStore.swift
//  KidBox
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
    let linkedExamIds:          [String]
    let asNeededDrugsData:      Data?
    let therapyTypesRaw:        [String]
    let prescribedExamsData:    Data?
    let photoURLs:              [String]
    let notes:                  String?
    let nextVisitDate:          Date?
    let nextVisitReason:        String?
    /// Valore coerente con `KBVisitStatus.rawValue` (etichette italiane) dopo normalizzazione da Firestore.
    let visitStatusRaw:         String?
    let reminderOn:             Bool
    let nextVisitReminderOn:    Bool
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
            "familyId":           dto.familyId,
            "childId":            dto.childId,
            "date":               Timestamp(date: dto.date),
            "reason":             dto.reason,
            "linkedTreatmentIds": dto.linkedTreatmentIds,
            "linkedExamIds":      dto.linkedExamIds,
            "linkedTreatmentIdsJson": Self.jsonStringArray(dto.linkedTreatmentIds),
            "linkedExamIdsJson":      Self.jsonStringArray(dto.linkedExamIds),
            "therapyTypesRaw":    dto.therapyTypesRaw,
            "therapyTypesJson":   Self.jsonStringArray(dto.therapyTypesRaw),
            "photoURLs":          dto.photoURLs,
            "photoUrlsJson":      Self.jsonStringArray(dto.photoURLs),
            "reminderOn":         dto.reminderOn,
            "nextVisitReminderOn": dto.nextVisitReminderOn,
            "isDeleted":          dto.isDeleted,
            "updatedBy":          dto.updatedBy,
            "updatedAt":          Timestamp(date: dto.updatedAt ?? Date()),
        ]
        if let v = dto.doctorName              { data["doctorName"]              = v }
        if let v = dto.doctorSpecializationRaw {
            data["doctorSpecializationRaw"] = v
            data["doctorSpecialization"]    = v
        }
        if let v = dto.diagnosis               { data["diagnosis"]               = v }
        if let v = dto.recommendations         { data["recommendations"]         = v }
        if let v = dto.notes                   { data["notes"]                   = v }
        if let v = dto.nextVisitDate           { data["nextVisitDate"]           = Timestamp(date: v) }
        if let v = dto.nextVisitReason         { data["nextVisitReason"]         = v }
        if let v = dto.createdBy               { data["createdBy"]               = v }
        if let v = dto.createdAt               { data["createdAt"]               = Timestamp(date: v) }
        if let code = Self.visitStatusFirestoreCode(fromLocalRaw: dto.visitStatusRaw) {
            data["visitStatus"] = code
        }
        if let json = Self.asNeededDrugsJsonString(from: dto.asNeededDrugsData) {
            data["asNeededDrugsJson"] = json
        }
        
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
        
        let linkedTreatmentIds = decodeFirestoreStringArray(
            d, arrayKeys: ["linkedTreatmentIds"], jsonKey: "linkedTreatmentIdsJson")
        let linkedExamIds = decodeFirestoreStringArray(
            d, arrayKeys: ["linkedExamIds"], jsonKey: "linkedExamIdsJson")
        
        let therapyFromArray = stringArray(fromFirestoreArrayKey: "therapyTypesRaw", d)
        let therapyFromJson  = decodeFirestoreStringArray(d, arrayKeys: [], jsonKey: "therapyTypesJson")
        let therapyTypesRaw  = !therapyFromArray.isEmpty ? therapyFromArray : therapyFromJson
        
        let photosFromArray = stringArray(fromFirestoreArrayKey: "photoURLs", d)
        let photosFromJson  = decodeFirestoreStringArray(d, arrayKeys: [], jsonKey: "photoUrlsJson")
        let photoURLs       = !photosFromArray.isEmpty ? photosFromArray : photosFromJson
        
        let specRaw = (d["doctorSpecializationRaw"] as? String)
            ?? (d["doctorSpecialization"] as? String)
        
        let asNeededData: Data?
        if let b64 = data64("asNeededDrugsData") {
            asNeededData = b64
        } else if let s = d["asNeededDrugsJson"] as? String,
                  let jData = s.data(using: .utf8),
                  let drugs = try? JSONDecoder().decode([KBAsNeededDrug].self, from: jData) {
            asNeededData = kbEncode(drugs)
        } else {
            asNeededData = nil
        }
        
        let visitStatusRaw = visitStatusLocalRaw(fromFirestore: d["visitStatus"] as? String)
        let reminderOn = d["reminderOn"] as? Bool ?? false
        let nextVisitReminderOn = d["nextVisitReminderOn"] as? Bool ?? false
        
        return RemoteVisitDTO(
            id:                      doc.documentID,
            familyId:                familyId,
            childId:                 childId,
            date:                    date,
            doctorName:              d["doctorName"]              as? String,
            doctorSpecializationRaw: specRaw,
            travelDetailsData:       data64("travelDetailsData"),
            reason:                  d["reason"]                  as? String ?? "",
            diagnosis:               d["diagnosis"]               as? String,
            recommendations:         d["recommendations"]         as? String,
            linkedTreatmentIds:      linkedTreatmentIds,
            linkedExamIds:           linkedExamIds,
            asNeededDrugsData:       asNeededData,
            therapyTypesRaw:         therapyTypesRaw,
            prescribedExamsData:     data64("prescribedExamsData"),
            photoURLs:               photoURLs,
            notes:                   d["notes"]                   as? String,
            nextVisitDate:           (d["nextVisitDate"]          as? Timestamp)?.dateValue(),
            nextVisitReason:         d["nextVisitReason"]         as? String,
            visitStatusRaw:          visitStatusRaw,
            reminderOn:              reminderOn,
            nextVisitReminderOn:     nextVisitReminderOn,
            isDeleted:               d["isDeleted"]               as? Bool ?? false,
            createdBy:               d["createdBy"]               as? String,
            updatedBy:               d["updatedBy"]               as? String ?? "remote",
            createdAt:               (d["createdAt"]              as? Timestamp)?.dateValue(),
            updatedAt:               (d["updatedAt"]              as? Timestamp)?.dateValue()
        )
    }
    
    // MARK: - Firestore helpers (parità Android: campi `*Json` + `visitStatus` codificato)
    
    private static func jsonStringArray(_ ids: [String]) -> String {
        guard JSONSerialization.isValidJSONObject(ids),
              let data = try? JSONSerialization.data(withJSONObject: ids),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }
    
    private static func decodeFirestoreStringArray(
        _ d: [String: Any],
        arrayKeys: [String],
        jsonKey: String
    ) -> [String] {
        for key in arrayKeys {
            if let s = d[key] as? [String], !s.isEmpty { return s }
            if let a = d[key] as? [Any] {
                let mapped = a.compactMap { $0 as? String }
                if !mapped.isEmpty { return mapped }
            }
        }
        guard let s = d[jsonKey] as? String,
              let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let strs = obj as? [String] { return strs }
        if let anys = obj as? [Any] { return anys.compactMap { $0 as? String } }
        return []
    }
    
    private static func stringArray(fromFirestoreArrayKey key: String, _ d: [String: Any]) -> [String] {
        if let s = d[key] as? [String] { return s }
        if let a = d[key] as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }
    
    /// Firestore (Android) usa codici inglesi; in locale usiamo `KBVisitStatus.rawValue` in italiano.
    private static func visitStatusLocalRaw(fromFirestore value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        switch v.lowercased() {
        case "pending":           return KBVisitStatus.pending.rawValue
        case "booked":            return KBVisitStatus.booked.rawValue
        case "completed":         return KBVisitStatus.completed.rawValue
        case "result_available":  return KBVisitStatus.resultAvailable.rawValue
        default:
            if KBVisitStatus(rawValue: v) != nil { return v }
            return nil
        }
    }
    
    private static func visitStatusFirestoreCode(fromLocalRaw local: String?) -> String? {
        guard let local, let s = KBVisitStatus(rawValue: local) else { return nil }
        switch s {
        case .pending:           return "pending"
        case .booked:            return "booked"
        case .completed:         return "completed"
        case .resultAvailable:   return "result_available"
        }
    }
    
    private static func asNeededDrugsJsonString(from data: Data?) -> String? {
        guard let data,
              let list = kbDecode([KBAsNeededDrug].self, from: data),
              !list.isEmpty,
              let json = try? JSONEncoder().encode(list),
              let encoded = String(data: json, encoding: .utf8)
        else { return nil }
        return encoded
    }
}
