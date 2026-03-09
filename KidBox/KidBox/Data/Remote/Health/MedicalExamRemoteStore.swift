//
//  MedicalExamRemoteStore.swift
//  KidBox
//

import Foundation
import FirebaseFirestore

// MARK: - MedicalExamRemoteStore

final class MedicalExamRemoteStore {
    
    private let db = Firestore.firestore()
    
    // MARK: - Collection ref
    
    private func col(familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("medicalExams")
    }
    
    // MARK: - Upsert
    
    func upsert(dto: KBMedicalExamDTO) async throws {
        var data: [String: Any] = [
            "id":        dto.id,
            "familyId":  dto.familyId,
            "childId":   dto.childId,
            "name":      dto.name,
            "isUrgent":  dto.isUrgent,
            "statusRaw": dto.statusRaw,
            "isDeleted": dto.isDeleted,
            "createdAt": Timestamp(date: dto.createdAt),
            "updatedAt": Timestamp(date: dto.updatedAt),
            "updatedBy": dto.updatedBy,
            "createdBy": dto.createdBy
        ]
        
        data["deadline"]           = dto.deadline.map { Timestamp(date: $0) } ?? FieldValue.delete()
        data["preparation"]        = dto.preparation        ?? FieldValue.delete()
        data["notes"]              = dto.notes              ?? FieldValue.delete()
        data["location"]           = dto.location           ?? FieldValue.delete()  // ← NUOVO
        data["resultText"]         = dto.resultText         ?? FieldValue.delete()
        data["resultDate"]         = dto.resultDate.map { Timestamp(date: $0) } ?? FieldValue.delete()
        data["prescribingVisitId"] = dto.prescribingVisitId ?? FieldValue.delete()
        
        try await col(familyId: dto.familyId)
            .document(dto.id)
            .setData(data, merge: true)
    }
    
    // MARK: - Soft delete
    
    func softDelete(familyId: String, examId: String) async throws {
        try await col(familyId: familyId)
            .document(examId)
            .updateData([
                "isDeleted": true,
                "updatedAt": Timestamp(date: Date())
            ])
    }
    
    // MARK: - Realtime listener
    
    func listen(
        familyId: String,
        childId:  String,
        onChange: @escaping ([KBMedicalExamDTO]) -> Void,
        onError:  @escaping (Error) -> Void
    ) -> ListenerRegistration {
        col(familyId: familyId)
            .whereField("childId", isEqualTo: childId)
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                let dtos = snapshot?.documents.compactMap {
                    MedicalExamRemoteStore.parseDTO(doc: $0)
                } ?? []
                onChange(dtos)
            }
    }
    
    // MARK: - Parse
    
    static func parseDTO(doc: QueryDocumentSnapshot) -> KBMedicalExamDTO? {
        let d = doc.data()
        guard
            let id       = d["id"]       as? String,
            let familyId = d["familyId"] as? String,
            let childId  = d["childId"]  as? String,
            let name     = d["name"]     as? String
        else { return nil }
        
        func ts(_ key: String) -> Date? {
            (d[key] as? Timestamp)?.dateValue()
        }
        
        return KBMedicalExamDTO(
            id:                 id,
            familyId:           familyId,
            childId:            childId,
            name:               name,
            isUrgent:           d["isUrgent"]          as? Bool   ?? false,
            deadline:           ts("deadline"),
            preparation:        d["preparation"]        as? String,
            notes:              d["notes"]              as? String,
            location:           d["location"]           as? String,  // ← NUOVO
            statusRaw:          d["statusRaw"]          as? String ?? KBExamStatus.pending.rawValue,
            resultText:         d["resultText"]         as? String,
            resultDate:         ts("resultDate"),
            prescribingVisitId: d["prescribingVisitId"] as? String,
            isDeleted:          d["isDeleted"]          as? Bool   ?? false,
            createdAt:          ts("createdAt") ?? Date(),
            updatedAt:          ts("updatedAt") ?? Date(),
            updatedBy:          d["updatedBy"]          as? String ?? "",
            createdBy:          d["createdBy"]          as? String ?? ""
        )
    }
}
