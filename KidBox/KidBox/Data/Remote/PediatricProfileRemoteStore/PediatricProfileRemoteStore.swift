//
//  PediatricProfileRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 09/03/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - DTO

struct RemotePediatricProfileDTO {
    let id: String           // == childId
    let familyId: String
    let childId: String
    
    let bloodGroup: String?
    let allergies: String?
    let medicalNotes: String?
    let doctorName: String?
    let doctorPhone: String?
    
    /// JSON-encoded [KBEmergencyContact]
    let emergencyContactsJSON: String?
    
    let isDeleted: Bool
    let updatedAt: Date?
    let updatedBy: String?
}

// MARK: - Realtime change type

enum PediatricProfileRemoteChange {
    case upsert(RemotePediatricProfileDTO)
    case remove(String)
}

// MARK: - Remote Store

/// Firestore remote store per la scheda medica del bambino.
///
/// Percorso: families/{familyId}/pediatricProfiles/{childId}
///
/// Pattern identico a DocumentRemoteStore:
/// - OUTBOUND: upsert, softDelete
/// - INBOUND:  listenProfile (listener realtime sul singolo childId)
final class PediatricProfileRemoteStore {
    
    private var db: Firestore { Firestore.firestore() }
    
    // MARK: - OUTBOUND
    
    /// Crea o aggiorna la scheda medica remota per un bambino.
    func upsert(dto: RemotePediatricProfileDTO) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("PediatricProfile upsert failed: not authenticated")
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbInfo("PediatricProfile upsert familyId=\(dto.familyId) childId=\(dto.childId)")
        
        let ref = db.collection("families")
            .document(dto.familyId)
            .collection("pediatricProfiles")
            .document(dto.childId)
        
        var data: [String: Any] = [
            "familyId":  dto.familyId,
            "childId":   dto.childId,
            "isDeleted": dto.isDeleted,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        // Campi opzionali: nil → FieldValue.delete() per rimuovere il campo remoto
        data["bloodGroup"]   = dto.bloodGroup   ?? FieldValue.delete()
        data["allergies"]    = dto.allergies    ?? FieldValue.delete()
        data["medicalNotes"] = dto.medicalNotes ?? FieldValue.delete()
        data["doctorName"]   = dto.doctorName   ?? FieldValue.delete()
        data["doctorPhone"]  = dto.doctorPhone  ?? FieldValue.delete()
        data["emergencyContactsJSON"] = dto.emergencyContactsJSON ?? FieldValue.delete()
        
        try await ref.setData(data, merge: true)
        
        KBLog.sync.kbInfo("PediatricProfile upsert OK familyId=\(dto.familyId) childId=\(dto.childId)")
    }
    
    /// Soft-delete della scheda medica remota.
    func softDelete(familyId: String, childId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("PediatricProfile softDelete failed: not authenticated")
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbInfo("PediatricProfile softDelete familyId=\(familyId) childId=\(childId)")
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("pediatricProfiles")
            .document(childId)
        
        try await ref.setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.sync.kbInfo("PediatricProfile softDelete OK familyId=\(familyId) childId=\(childId)")
    }
    
    // MARK: - INBOUND (Realtime)
    
    /// Listener realtime sulla scheda di un singolo bambino.
    func listenProfile(
        familyId: String,
        childId: String,
        onChange: @escaping ([PediatricProfileRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        
        KBLog.sync.kbInfo("PediatricProfile listener attach familyId=\(familyId) childId=\(childId)")
        
        return db.collection("families")
            .document(familyId)
            .collection("pediatricProfiles")
            .document(childId)
            .addSnapshotListener { snap, err in
                
                if let err {
                    KBLog.sync.kbError("PediatricProfile listener error: \(err.localizedDescription)")
                    onError(err)
                    return
                }
                
                guard let snap, snap.exists else {
                    KBLog.sync.kbDebug("PediatricProfile listener: document missing childId=\(childId)")
                    return
                }
                
                let data = snap.data() ?? [:]
                let dto = RemotePediatricProfileDTO(
                    id:                    snap.documentID,
                    familyId:              data["familyId"]  as? String ?? familyId,
                    childId:               data["childId"]   as? String ?? childId,
                    bloodGroup:            data["bloodGroup"]   as? String,
                    allergies:             data["allergies"]    as? String,
                    medicalNotes:          data["medicalNotes"] as? String,
                    doctorName:            data["doctorName"]   as? String,
                    doctorPhone:           data["doctorPhone"]  as? String,
                    emergencyContactsJSON: data["emergencyContactsJSON"] as? String,
                    isDeleted:             data["isDeleted"] as? Bool ?? false,
                    updatedAt:             (data["updatedAt"] as? Timestamp)?.dateValue(),
                    updatedBy:             data["updatedBy"] as? String
                )
                
                KBLog.sync.kbDebug("PediatricProfile listener emitting upsert childId=\(childId)")
                onChange([.upsert(dto)])
            }
    }
}
