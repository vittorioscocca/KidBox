//
//  VaccineRemoteStore.swift
//  KidBox
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - DTO

struct RemoteVaccineDTO {
    let id: String
    let familyId: String
    let childId: String
    
    let vaccineTypeRaw: String
    let statusRaw: String
    let commercialName: String?
    let doseNumber: Int
    let totalDoses: Int
    let administeredDate: Date?
    let scheduledDate: Date?
    let lotNumber: String?
    let administeredBy: String?
    let administrationSiteRaw: String?
    let notes: String?
    
    let isDeleted: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let updatedBy: String?
    let createdBy: String?
}

// MARK: - Realtime change type

enum VaccineRemoteChange {
    case upsert(RemoteVaccineDTO)
    case remove(String)
}

// MARK: - Remote Store

/// Firestore remote store per i vaccini del bambino.
///
/// Percorso: families/{familyId}/vaccines/{vaccineId}
///
/// Pattern identico a DocumentRemoteStore:
/// - OUTBOUND: upsert, softDelete
/// - INBOUND:  listenVaccines (listener realtime per familyId + childId)
final class VaccineRemoteStore {
    
    private var db: Firestore { Firestore.firestore() }
    
    // MARK: - OUTBOUND
    
    func upsert(dto: RemoteVaccineDTO) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("Vaccine upsert failed: not authenticated")
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbInfo("Vaccine upsert familyId=\(dto.familyId) vaccineId=\(dto.id)")
        
        let ref = db.collection("families")
            .document(dto.familyId)
            .collection("vaccines")
            .document(dto.id)
        
        var data: [String: Any] = [
            "familyId":       dto.familyId,
            "childId":        dto.childId,
            "vaccineTypeRaw": dto.vaccineTypeRaw,
            "statusRaw":      dto.statusRaw,
            "doseNumber":     dto.doseNumber,
            "totalDoses":     dto.totalDoses,
            "isDeleted":      dto.isDeleted,
            "updatedBy":      uid,
            "updatedAt":      FieldValue.serverTimestamp(),
            "createdAt":      FieldValue.serverTimestamp()
        ]
        
        data["commercialName"]        = dto.commercialName        ?? FieldValue.delete()
        data["lotNumber"]             = dto.lotNumber             ?? FieldValue.delete()
        data["administeredBy"]        = dto.administeredBy        ?? FieldValue.delete()
        data["administrationSiteRaw"] = dto.administrationSiteRaw ?? FieldValue.delete()
        data["notes"]                 = dto.notes                 ?? FieldValue.delete()
        data["createdBy"]             = dto.createdBy             ?? FieldValue.delete()
        
        if let d = dto.administeredDate {
            data["administeredDate"] = Timestamp(date: d)
        } else {
            data["administeredDate"] = FieldValue.delete()
        }
        
        if let d = dto.scheduledDate {
            data["scheduledDate"] = Timestamp(date: d)
        } else {
            data["scheduledDate"] = FieldValue.delete()
        }
        
        try await ref.setData(data, merge: true)
        
        KBLog.sync.kbInfo("Vaccine upsert OK familyId=\(dto.familyId) vaccineId=\(dto.id)")
    }
    
    func softDelete(familyId: String, vaccineId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("Vaccine softDelete failed: not authenticated")
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbInfo("Vaccine softDelete familyId=\(familyId) vaccineId=\(vaccineId)")
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("vaccines")
            .document(vaccineId)
        
        try await ref.setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.sync.kbInfo("Vaccine softDelete OK familyId=\(familyId) vaccineId=\(vaccineId)")
    }
    
    // MARK: - INBOUND (Realtime)
    
    func listenVaccines(
        familyId: String,
        childId: String,
        onChange: @escaping ([VaccineRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        
        KBLog.sync.kbInfo("Vaccine listener attach familyId=\(familyId) childId=\(childId)")
        
        return db.collection("families")
            .document(familyId)
            .collection("vaccines")
            .whereField("childId", isEqualTo: childId)
            .whereField("isDeleted", isEqualTo: false)
            .addSnapshotListener { snap, err in
                
                if let err {
                    KBLog.sync.kbError("Vaccine listener error: \(err.localizedDescription)")
                    onError(err)
                    return
                }
                
                guard let snap else {
                    KBLog.sync.kbDebug("Vaccine listener snapshot nil")
                    return
                }
                
                KBLog.sync.kbDebug("Vaccine snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count)")
                
                let changes: [VaccineRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc  = diff.document
                    let data = doc.data()
                    
                    let dto = RemoteVaccineDTO(
                        id:                    doc.documentID,
                        familyId:              data["familyId"]       as? String ?? familyId,
                        childId:               data["childId"]        as? String ?? childId,
                        vaccineTypeRaw:        data["vaccineTypeRaw"] as? String ?? "altro",
                        statusRaw:             data["statusRaw"]      as? String ?? "administered",
                        commercialName:        data["commercialName"]        as? String,
                        doseNumber:            data["doseNumber"]            as? Int ?? 1,
                        totalDoses:            data["totalDoses"]            as? Int ?? 1,
                        administeredDate:      (data["administeredDate"]     as? Timestamp)?.dateValue(),
                        scheduledDate:         (data["scheduledDate"]        as? Timestamp)?.dateValue(),
                        lotNumber:             data["lotNumber"]             as? String,
                        administeredBy:        data["administeredBy"]        as? String,
                        administrationSiteRaw: data["administrationSiteRaw"] as? String,
                        notes:                 data["notes"]                 as? String,
                        isDeleted:             data["isDeleted"]             as? Bool ?? false,
                        createdAt:             (data["createdAt"]            as? Timestamp)?.dateValue(),
                        updatedAt:             (data["updatedAt"]            as? Timestamp)?.dateValue(),
                        updatedBy:             data["updatedBy"]             as? String,
                        createdBy:             data["createdBy"]             as? String
                    )
                    
                    switch diff.type {
                    case .added, .modified: return .upsert(dto)
                    case .removed:          return .remove(doc.documentID)
                    }
                }
                
                if !changes.isEmpty {
                    onChange(changes)
                }
            }
    }
}
