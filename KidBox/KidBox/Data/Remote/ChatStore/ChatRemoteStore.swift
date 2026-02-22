//
//  ChatRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import OSLog

// MARK: - DTO

struct RemoteChatMessageDTO {
    let id: String
    let familyId: String
    let senderId: String
    let senderName: String
    let typeRaw: String
    let text: String?
    let mediaStoragePath: String?
    let mediaURL: String?
    let mediaDurationSeconds: Int?
    let mediaThumbnailURL: String?
    let reactionsJSON: String?
    let createdAt: Date?
    let isDeleted: Bool
}

// MARK: - Change type

enum ChatRemoteChange {
    case upsert(RemoteChatMessageDTO)
    case remove(String)
}

// MARK: - Store

/// Firestore remote store per i messaggi della chat familiare.
///
/// Struttura: `families/{familyId}/chatMessages/{messageId}`
///
/// Responsabilità:
/// - OUTBOUND: upsert messaggio, soft delete, aggiornamento reazioni
/// - INBOUND: listener realtime con paginazione (ultimi N messaggi)
final class ChatRemoteStore {
    
    private var db: Firestore { Firestore.firestore() }
    
    // MARK: - OUTBOUND
    
    /// Crea o aggiorna un messaggio remoto su Firestore.
    func upsert(dto: RemoteChatMessageDTO) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbInfo("ChatRemote upsert msgId=\(dto.id) familyId=\(dto.familyId)")
        
        let ref = db.collection("families")
            .document(dto.familyId)
            .collection("chatMessages")
            .document(dto.id)
        
        var data: [String: Any] = [
            "familyId":   dto.familyId,
            "senderId":   dto.senderId,
            "senderName": dto.senderName,
            "type":       dto.typeRaw,
            "isDeleted":  dto.isDeleted,
            "updatedBy":  uid,
            "createdAt":  FieldValue.serverTimestamp()
        ]
        
        if let text = dto.text                         { data["text"] = text }
        if let path = dto.mediaStoragePath             { data["mediaStoragePath"] = path }
        if let url  = dto.mediaURL                     { data["mediaURL"] = url }
        if let dur  = dto.mediaDurationSeconds         { data["mediaDurationSeconds"] = dur }
        if let thu  = dto.mediaThumbnailURL            { data["mediaThumbnailURL"] = thu }
        if let r    = dto.reactionsJSON                { data["reactionsJSON"] = r }
        
        // Preserva createdAt se il documento esiste già
        let snap = try await ref.getDocument()
        if snap.exists { data.removeValue(forKey: "createdAt") }
        
        try await ref.setData(data, merge: true)
        KBLog.sync.kbInfo("ChatRemote upsert OK msgId=\(dto.id)")
    }
    
    /// Aggiorna solo le reazioni di un messaggio (merge parziale).
    func updateReactions(familyId: String, messageId: String, reactionsJSON: String?) async throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("chatMessages")
            .document(messageId)
        
        let data: [String: Any] = [
            "reactionsJSON": reactionsJSON ?? NSNull(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        try await ref.setData(data, merge: true)
        KBLog.sync.kbDebug("ChatRemote reactions updated msgId=\(messageId)")
    }
    
    /// Soft delete: marca il messaggio come eliminato.
    func softDelete(familyId: String, messageId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("chatMessages")
            .document(messageId)
        
        try await ref.setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.sync.kbInfo("ChatRemote softDelete OK msgId=\(messageId)")
    }
    
    // MARK: - INBOUND (Realtime)
    
    /// Avvia un listener realtime sugli ultimi `limit` messaggi della famiglia.
    ///
    /// - Parameters:
    ///   - familyId: ID della famiglia.
    ///   - limit: Numero massimo di messaggi da ricevere (default 100).
    ///   - onChange: Callback con le modifiche ricevute.
    ///   - onError: Callback in caso di errore.
    /// - Returns: `ListenerRegistration` da rimuovere quando la view scompare.
    func listenMessages(
        familyId: String,
        limit: Int = 100,
        onChange: @escaping ([ChatRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        
        KBLog.sync.kbInfo("ChatRemote listener attach familyId=\(familyId) limit=\(limit)")
        
        return db.collection("families")
            .document(familyId)
            .collection("chatMessages")
            .order(by: "createdAt", descending: false)
            .limit(toLast: limit)
            .addSnapshotListener { snap, err in
                if let err {
                    KBLog.sync.kbError("ChatRemote listener error: \(err.localizedDescription)")
                    onError(err); return
                }
                guard let snap else { return }
                
                let changes: [ChatRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc  = diff.document
                    let data = doc.data()
                    
                    switch diff.type {
                    case .removed:
                        return .remove(doc.documentID)
                        
                    case .added, .modified:
                        let dto = RemoteChatMessageDTO(
                            id:                   doc.documentID,
                            familyId:             familyId,
                            senderId:             data["senderId"]   as? String ?? "",
                            senderName:           data["senderName"] as? String ?? "",
                            typeRaw:              data["type"]       as? String ?? "text",
                            text:                 data["text"]       as? String,
                            mediaStoragePath:     data["mediaStoragePath"]     as? String,
                            mediaURL:             data["mediaURL"]             as? String,
                            mediaDurationSeconds: data["mediaDurationSeconds"] as? Int,
                            mediaThumbnailURL:    data["mediaThumbnailURL"]    as? String,
                            reactionsJSON:        data["reactionsJSON"]        as? String,
                            createdAt:            (data["createdAt"] as? Timestamp)?.dateValue(),
                            isDeleted:            data["isDeleted"] as? Bool ?? false
                        )
                        return .upsert(dto)
                    }
                }
                
                if !changes.isEmpty {
                    KBLog.sync.kbDebug("ChatRemote listener changes=\(changes.count)")
                    onChange(changes)
                }
            }
    }
}
