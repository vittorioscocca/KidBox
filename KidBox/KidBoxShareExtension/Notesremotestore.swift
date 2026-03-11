//
//  NotesRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//
//  ⚠️ Target: App + Extension
//  Non importare SwiftData qui.
//  Il metodo upsert(note: KBNote) sta in NotesRemoteStore+App.swift (solo target App).
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

// MARK: - DTOs

struct NoteDTO {
    let id: String
    let familyId: String
    
    let titleEnc: String?
    let bodyEnc: String?
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
    
    func ref(familyId: String, noteId: String) -> DocumentReference {
        db.collection("families").document(familyId).collection("notes").document(noteId)
    }
    
    private func col(familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("notes")
    }
    
    // MARK: - Upsert raw (App + Extension)
    
    /// Crea/aggiorna una nota direttamente su Firestore senza dipendenze SwiftData.
    /// Utilizzabile sia dall'app principale che dalla Share Extension.
    func upsertRaw(
        noteId: String,
        familyId: String,
        title: String,
        body: String,
        uid: String,
        displayName: String
    ) async throws {
        let titleEnc = try NoteCryptoService.encryptString(title, familyId: familyId, userId: uid)
        let bodyEnc  = try NoteCryptoService.encryptString(body,  familyId: familyId, userId: uid)
        
        let data: [String: Any] = [
            "schemaVersion": 1,
            "titleEnc": titleEnc,
            "bodyEnc": bodyEnc,
            "isDeleted": false,
            "createdBy": uid,
            "createdByName": displayName,
            "updatedBy": uid,
            "updatedByName": displayName,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        try await ref(familyId: familyId, noteId: noteId).setData(data, merge: true)
        KBLog.sync.kbInfo("[NotesRemote] upsertRaw OK id=\(noteId) familyId=\(familyId)")
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
                    let d   = doc.data()
                    
                    let dto = NoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        titleEnc: d["titleEnc"] as? String,
                        bodyEnc:  d["bodyEnc"]  as? String,
                        titlePlain: d["title"] as? String,
                        bodyPlain:  d["body"]  as? String,
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
