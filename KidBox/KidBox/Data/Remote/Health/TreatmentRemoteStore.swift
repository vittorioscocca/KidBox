//
//  TreatmentRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 04/03/26.
//

import Foundation
import FirebaseFirestore

// MARK: - DTOs

struct RemoteTreatmentDTO {
    let id:              String
    let familyId:        String
    let childId:         String
    let drugName:        String
    let activeIngredient: String?
    let dosageValue:     Double
    let dosageUnit:      String
    let isLongTerm:      Bool
    let durationDays:    Int
    let startDate:       Date
    let endDate:         Date?
    let dailyFrequency:  Int
    let scheduleTimes:   [String]
    let isActive:        Bool
    let isDeleted:       Bool
    let notes:           String?
    let reminderEnabled: Bool
    let createdBy:       String?
    let updatedBy:       String
    let createdAt:       Date?
    let updatedAt:       Date?
}

struct RemoteDoseLogDTO {
    let id:            String
    let familyId:      String
    let childId:       String
    let treatmentId:   String
    let dayNumber:     Int
    let slotIndex:     Int
    let scheduledTime: String
    let takenAt:       Date?
    let taken:         Bool
    let isDeleted:     Bool
    let updatedBy:     String?
    let createdAt:     Date?
    let updatedAt:     Date?
}

// MARK: - Remote changes

enum TreatmentRemoteChange {
    case upsert(RemoteTreatmentDTO)
    case remove(String)
}

enum DoseLogRemoteChange {
    case upsert(RemoteDoseLogDTO)
    case remove(String)
}

// MARK: - Store

final class TreatmentRemoteStore {
    
    private let db = Firestore.firestore()
    
    // MARK: - Treatments
    
    func listenAllTreatments(
        familyId: String,
        onChange: @escaping ([TreatmentRemoteChange]) -> Void,
        onError:  @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection("families")
            .document(familyId)
            .collection("treatments")
            .addSnapshotListener { snap, err in
                if let err { onError(err); return }
                guard let snap else { return }
                let changes: [TreatmentRemoteChange] = snap.documentChanges.compactMap { diff in
                    if diff.type == .removed { return .remove(diff.document.documentID) }
                    guard let dto = Self.decodeTreatment(diff.document, familyId: familyId) else { return nil }
                    return .upsert(dto)
                }
                if !changes.isEmpty { onChange(changes) }
            }
    }
    
    func upsertTreatment(_ dto: RemoteTreatmentDTO) async throws {
        var data: [String: Any] = [
            "familyId":         dto.familyId,
            "childId":          dto.childId,
            "drugName":         dto.drugName,
            "dosageValue":      dto.dosageValue,
            "dosageUnit":       dto.dosageUnit,
            "isLongTerm":       dto.isLongTerm,
            "durationDays":     dto.durationDays,
            "startDate":        Timestamp(date: dto.startDate),
            "dailyFrequency":   dto.dailyFrequency,
            "scheduleTimes":    dto.scheduleTimes,
            "isActive":         dto.isActive,
            "isDeleted":        dto.isDeleted,
            "reminderEnabled":  dto.reminderEnabled,
            "updatedBy":        dto.updatedBy,
            "updatedAt":        FieldValue.serverTimestamp(),
        ]
        if let ai = dto.activeIngredient { data["activeIngredient"] = ai }
        if let ed = dto.endDate          { data["endDate"] = Timestamp(date: ed) }
        if let n  = dto.notes            { data["notes"] = n }
        if let cb = dto.createdBy        { data["createdBy"] = cb }
        if let ca = dto.createdAt        { data["createdAt"] = Timestamp(date: ca) }
        
        try await db.collection("families")
            .document(dto.familyId)
            .collection("treatments")
            .document(dto.id)
            .setData(data, merge: true)
    }
    
    func deleteTreatment(familyId: String, treatmentId: String) async throws {
        try await db.collection("families")
            .document(familyId)
            .collection("treatments")
            .document(treatmentId)
            .updateData([
                "isDeleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }
    
    // MARK: - DoseLogs
    
    func listenDoseLogs(
        familyId:    String,
        childId:     String,
        treatmentId: String,
        onChange:    @escaping ([DoseLogRemoteChange]) -> Void,
        onError:     @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection("families")
            .document(familyId)
            .collection("doseLogs")
            .whereField("childId",     isEqualTo: childId)
            .whereField("treatmentId", isEqualTo: treatmentId)
            .addSnapshotListener { snap, err in
                if let err { onError(err); return }
                guard let snap else { return }
                let changes: [DoseLogRemoteChange] = snap.documentChanges.compactMap { diff in
                    if diff.type == .removed { return .remove(diff.document.documentID) }
                    guard let dto = Self.decodeDoseLog(diff.document, familyId: familyId) else { return nil }
                    return .upsert(dto)
                }
                if !changes.isEmpty { onChange(changes) }
            }
    }
    
    /// Listener per tutti i doseLogs di una famiglia/figlio (usato per sync globale)
    func listenAllDoseLogs(
        familyId: String,
        onChange: @escaping ([DoseLogRemoteChange]) -> Void,
        onError:  @escaping (Error) -> Void
    ) -> ListenerRegistration {
        db.collection("families")
            .document(familyId)
            .collection("doseLogs")
            .addSnapshotListener { snap, err in
                if let err { onError(err); return }
                guard let snap else { return }
                let changes: [DoseLogRemoteChange] = snap.documentChanges.compactMap { diff in
                    if diff.type == .removed { return .remove(diff.document.documentID) }
                    guard let dto = Self.decodeDoseLog(diff.document, familyId: familyId) else { return nil }
                    return .upsert(dto)
                }
                if !changes.isEmpty { onChange(changes) }
            }
    }
    
    func upsertDoseLog(_ dto: RemoteDoseLogDTO) async throws {
        var data: [String: Any] = [
            "familyId":      dto.familyId,
            "childId":       dto.childId,
            "treatmentId":   dto.treatmentId,
            "dayNumber":     dto.dayNumber,
            "slotIndex":     dto.slotIndex,
            "scheduledTime": dto.scheduledTime,
            "taken":         dto.taken,
            "isDeleted":     dto.isDeleted,
            "updatedAt":     FieldValue.serverTimestamp(),
        ]
        if let ta = dto.takenAt   { data["takenAt"]   = Timestamp(date: ta) }
        if let ub = dto.updatedBy { data["updatedBy"] = ub }
        if let ca = dto.createdAt { data["createdAt"] = Timestamp(date: ca) }
        
        try await db.collection("families")
            .document(dto.familyId)
            .collection("doseLogs")
            .document(dto.id)
            .setData(data, merge: true)
    }
    
    func deleteDoseLog(familyId: String, logId: String) async throws {
        try await db.collection("families")
            .document(familyId)
            .collection("doseLogs")
            .document(logId)
            .updateData([
                "isDeleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }
    
    // MARK: - Decode helpers
    
    private static func decodeTreatment(_ doc: QueryDocumentSnapshot, familyId: String) -> RemoteTreatmentDTO? {
        let data = doc.data()
        guard
            let childId   = data["childId"]   as? String,
            let drugName  = data["drugName"]   as? String,
            let updatedBy = data["updatedBy"]  as? String,
            let startDate = (data["startDate"] as? Timestamp)?.dateValue()
        else { return nil }
        
        return RemoteTreatmentDTO(
            id:               doc.documentID,
            familyId:         familyId,
            childId:          childId,
            drugName:         drugName,
            activeIngredient: data["activeIngredient"] as? String,
            dosageValue:      data["dosageValue"]  as? Double ?? 0,
            dosageUnit:       data["dosageUnit"]   as? String ?? "ml",
            isLongTerm:       data["isLongTerm"]   as? Bool   ?? false,
            durationDays:     data["durationDays"] as? Int    ?? 1,
            startDate:        startDate,
            endDate:          (data["endDate"]     as? Timestamp)?.dateValue(),
            dailyFrequency:   data["dailyFrequency"] as? Int  ?? 1,
            scheduleTimes:    data["scheduleTimes"] as? [String] ?? [],
            isActive:         data["isActive"]     as? Bool   ?? true,
            isDeleted:        data["isDeleted"]    as? Bool   ?? false,
            notes:            data["notes"]        as? String,
            reminderEnabled:  data["reminderEnabled"] as? Bool ?? false,
            createdBy:        data["createdBy"]    as? String,
            updatedBy:        updatedBy,
            createdAt:        (data["createdAt"]   as? Timestamp)?.dateValue(),
            updatedAt:        (data["updatedAt"]   as? Timestamp)?.dateValue()
        )
    }
    
    private static func decodeDoseLog(_ doc: QueryDocumentSnapshot, familyId: String) -> RemoteDoseLogDTO? {
        let data = doc.data()
        guard
            let childId       = data["childId"]       as? String,
            let treatmentId   = data["treatmentId"]   as? String,
            let dayNumber     = data["dayNumber"]      as? Int,
            let slotIndex     = data["slotIndex"]      as? Int,
            let scheduledTime = data["scheduledTime"]  as? String
        else { return nil }
        
        return RemoteDoseLogDTO(
            id:            doc.documentID,
            familyId:      familyId,
            childId:       childId,
            treatmentId:   treatmentId,
            dayNumber:     dayNumber,
            slotIndex:     slotIndex,
            scheduledTime: scheduledTime,
            takenAt:       (data["takenAt"]   as? Timestamp)?.dateValue(),
            taken:         data["taken"]       as? Bool   ?? false,
            isDeleted:     data["isDeleted"]   as? Bool   ?? false,
            updatedBy:     data["updatedBy"]   as? String,
            createdAt:     (data["createdAt"]  as? Timestamp)?.dateValue(),
            updatedAt:     (data["updatedAt"]  as? Timestamp)?.dateValue()
        )
    }
}
