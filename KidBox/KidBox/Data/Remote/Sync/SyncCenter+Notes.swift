//
//  SyncCenter+Notes.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import Foundation
import SwiftData
import FirebaseAuth
internal import FirebaseFirestoreInternal

// MARK: - Notes realtime + outbox integration

extension SyncCenter {
    
    // MARK: - Listener lifecycle
    
    func startNotesRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startNotesRealtime familyId=\(familyId)")
        stopNotesRealtime()
        
        notesListener = notesRemote.listenNotes(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                self.applyNotesInbound(changes: changes, familyId: familyId, modelContext: modelContext)
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "notes", error: err)
                    }
                }
            }
        )
    }
    
    func stopNotesRealtime() {
        if notesListener != nil {
            KBLog.sync.kbInfo("stopNotesRealtime")
        }
        notesListener?.remove()
        notesListener = nil
    }
    
    // MARK: - Outbox helpers
    
    func enqueueNoteUpsert(noteId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueNoteUpsert familyId=\(familyId) noteId=\(noteId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.note.rawValue,
            entityId: noteId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    func enqueueNoteDelete(noteId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueNoteDelete familyId=\(familyId) noteId=\(noteId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.note.rawValue,
            entityId: noteId,
            opType: "delete",
            modelContext: modelContext
        )
    }
    
    // MARK: - Flush handler
    
    func processNote(op: KBSyncOp, modelContext: ModelContext) async throws {
        let nid = op.entityId
        let desc = FetchDescriptor<KBNote>(predicate: #Predicate { $0.id == nid })
        let note = try? modelContext.fetch(desc).first
        
        switch op.opType {
            
        case "upsert":
            guard let note else { return }
            note.syncState = .pendingUpsert
            note.lastSyncError = nil
            try? modelContext.save()
            
            // ✅ NotesRemoteStore does encryption before sending
            try await notesRemote.upsert(note: note)
            
            note.syncState = .synced
            note.lastSyncError = nil
            try modelContext.save()
            
        case "delete":
            try await notesRemote.softDelete(noteId: nid, familyId: op.familyId)
            
            if let note {
                KBLog.sync.kbInfo("[note][outbound] delete OK -> HARD DELETE local id=\(note.id)")
                modelContext.delete(note)
                try? modelContext.save()
            }
            
        default:
            throw NSError(domain: "KidBox.Sync", code: -2310,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for note: \(op.opType)"])
        }
    }
    
    // MARK: - Inbound apply (LWW)
    
    func applyNotesInbound(
        changes: [NoteRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("[note][inbound] applying changes=\(changes.count) familyId=\(familyId)")
        
        do {
            let uid = Auth.auth().currentUser?.uid ?? ""
            
            for change in changes {
                switch change {
                    
                case .upsert(let dto):
                    if dto.isDeleted {
                        let pid = dto.id
                        let desc = FetchDescriptor<KBNote>(predicate: #Predicate { $0.id == pid })
                        if let existing = try modelContext.fetch(desc).first {
                            KBLog.sync.kbInfo("[note][inbound] remote isDeleted -> DELETE local id=\(dto.id)")
                            modelContext.delete(existing)
                        }
                        continue
                    }
                    
                    let pid = dto.id
                    let desc = FetchDescriptor<KBNote>(predicate: #Predicate { $0.id == pid })
                    
                    // ✅ decrypt (preferred), fallback to legacy plaintext
                    var decryptedTitle: String
                    let decryptedBody: String
                    
                    if !uid.isEmpty, let tEnc = dto.titleEnc, let bEnc = dto.bodyEnc {
                        do {
                            decryptedTitle = try NoteCryptoService.decryptString(tEnc, familyId: familyId, userId: uid)
                            decryptedBody  = try NoteCryptoService.decryptString(bEnc, familyId: familyId, userId: uid)
                        } catch {
                            KBLog.sync.kbError("[note][inbound] decrypt FAIL id=\(dto.id) err=\(error.localizedDescription)")
                            decryptedTitle = "⚠️ Nota non decifrabile"
                            decryptedBody = ""
                        }
                    } else {
                        decryptedTitle = dto.titlePlain ?? ""
                        decryptedBody  = dto.bodyPlain ?? ""
                    }
                    
                    if let existing = try modelContext.fetch(desc).first {
                        if existing.isDeleted || existing.syncState == .pendingDelete {
                            KBLog.sync.kbDebug("[note][inbound] IGNORE (anti-resurrect) id=\(dto.id)")
                            continue
                        }
                        
                        let remoteTs = dto.updatedAt ?? Date.distantPast
                        let localTs  = existing.updatedAt
                        
                        guard remoteTs >= localTs else {
                            KBLog.sync.kbDebug("[note][inbound] IGNORE remote<local id=\(dto.id)")
                            continue
                        }
                        
                        existing.title = decryptedTitle
                        existing.body  = decryptedBody
                        
                        existing.isDeleted = false
                        existing.updatedAt = remoteTs
                        
                        if let cb = dto.createdBy, !cb.isEmpty { existing.createdBy = cb }
                        if let cbn = dto.createdByName, !cbn.isEmpty { existing.createdByName = cbn }
                        
                        if let ub = dto.updatedBy, !ub.isEmpty { existing.updatedBy = ub }
                        if let ubn = dto.updatedByName, !ubn.isEmpty { existing.updatedByName = ubn }
                        
                        existing.syncState = .synced
                        existing.lastSyncError = nil
                        
                        KBLog.sync.kbDebug("[note][inbound] UPDATED id=\(dto.id)")
                        
                    } else {
                        let now = dto.updatedAt ?? Date()
                        let createdAt = dto.createdAt ?? now
                        
                        let note = KBNote(
                            id: dto.id,
                            familyId: dto.familyId,
                            title: decryptedTitle,
                            body: decryptedBody,
                            createdBy: dto.createdBy ?? "",
                            createdByName: dto.createdByName ?? "",
                            updatedBy: dto.updatedBy ?? "",
                            updatedByName: dto.updatedByName ?? "",
                            createdAt: createdAt,
                            updatedAt: now,
                            isDeleted: false
                        )
                        
                        note.syncState = .synced
                        note.lastSyncError = nil
                        
                        modelContext.insert(note)
                        KBLog.sync.kbDebug("[note][inbound] CREATED id=\(dto.id)")
                    }
                    
                case .remove(let id):
                    let pid = id
                    let desc = FetchDescriptor<KBNote>(predicate: #Predicate { $0.id == pid })
                    if let existing = try modelContext.fetch(desc).first {
                        KBLog.sync.kbInfo("[note][inbound] remove -> DELETE local id=\(id)")
                        modelContext.delete(existing)
                    }
                }
            }
            
            try modelContext.save()
            KBLog.sync.kbDebug("[note][inbound] SAVE OK")
            
        } catch {
            KBLog.sync.kbError("[note][inbound] APPLY FAIL err=\(error.localizedDescription)")
        }
    }
}
