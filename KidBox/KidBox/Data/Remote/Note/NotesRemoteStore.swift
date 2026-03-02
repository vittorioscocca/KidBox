//
//  NotesRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

// MARK: - DTOs

struct NoteDTO {
    let id: String
    let familyId: String
    
    /// Encrypted fields (base64 combined). Preferred.
    let titleEnc: String?
    let bodyEnc: String?
    
    /// Legacy plaintext fields (migration fallback).
    let titlePlain: String?
    let bodyPlain: String?
    
    let isDeleted: Bool
    
    let createdAt: Date?
    let updatedAt: Date?
    
    let createdBy: String?
    let createdByName: String?
    
    let updatedBy: String?
    let updatedByName: String?
}

enum NoteRemoteChange {
    case upsert(NoteDTO)
    case remove(String)
}

// MARK: - Remote store

final class NotesRemoteStore {
    
    private var db: Firestore { Firestore.firestore() }
    
    // Percorso Firestore: families/{familyId}/notes/{noteId}
    private func ref(familyId: String, noteId: String) -> DocumentReference {
        db.collection("families")
            .document(familyId)
            .collection("notes")
            .document(noteId)
    }
    
    private func col(familyId: String) -> CollectionReference {
        db.collection("families")
            .document(familyId)
            .collection("notes")
    }
    
    // MARK: - Upsert
    
    func upsert(note: KBNote) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let snap = try await ref(familyId: note.familyId, noteId: note.id).getDocument()
        let isNew = !snap.exists
        
        // ✅ Encrypt before sending to Firestore (same family key used for encrypted documents)
        let titleEnc = try NoteCryptoService.encryptString(note.title, familyId: note.familyId, userId: uid)
        let bodyEnc  = try NoteCryptoService.encryptString(note.body,  familyId: note.familyId, userId: uid)
        
        var data: [String: Any] = [
            "schemaVersion": 1,
            "titleEnc": titleEnc,
            "bodyEnc": bodyEnc,
            
            // hard remove legacy plaintext fields (if any)
            "title": FieldValue.delete(),
            "body": FieldValue.delete(),
            
            "isDeleted": false,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        if isNew {
            data["createdAt"] = FieldValue.serverTimestamp()
        }
        
        if isNew {
            data["createdBy"] = note.createdBy.isEmpty ? uid : note.createdBy
            data["createdByName"] = note.createdByName as Any
        }
        
        data["updatedByName"] = note.updatedByName as Any
        
        try await ref(familyId: note.familyId, noteId: note.id).setData(data, merge: true)
        KBLog.sync.kbInfo("[NotesRemote] upsert OK id=\(note.id) familyId=\(note.familyId)")
    }
    
    // MARK: - Soft delete
    
    func softDelete(noteId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        try await ref(familyId: familyId, noteId: noteId).setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.sync.kbInfo("[NotesRemote] softDelete OK id=\(noteId) familyId=\(familyId)")
    }
    
    // MARK: - Realtime listener
    
    func listenNotes(
        familyId: String,
        onChange: @escaping ([NoteRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        
        KBLog.sync.kbInfo("[NotesRemote] listenNotes ATTACH familyId=\(familyId)")
        
        return col(familyId: familyId)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[NotesRemote] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else { return }
                
                KBLog.sync.kbDebug("[NotesRemote] snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count) fromCache=\(snap.metadata.isFromCache)")
                
                let changes: [NoteRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let d = doc.data()
                    
                    // Prefer encrypted fields; fallback to legacy plaintext (migration).
                    let titleEnc = d["titleEnc"] as? String
                    let bodyEnc  = d["bodyEnc"]  as? String
                    
                    let titlePlain = d["title"] as? String
                    let bodyPlain  = d["body"]  as? String
                    
                    let dto = NoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        titleEnc: titleEnc,
                        bodyEnc: bodyEnc,
                        titlePlain: titlePlain,
                        bodyPlain: bodyPlain,
                        isDeleted: d["isDeleted"] as? Bool ?? false,
                        createdAt: (d["createdAt"] as? Timestamp)?.dateValue(),
                        updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
                        createdBy: d["createdBy"] as? String,
                        createdByName: d["createdByName"] as? String,
                        updatedBy: d["updatedBy"] as? String,
                        updatedByName: d["updatedByName"] as? String
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
