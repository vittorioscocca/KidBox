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
    let readByJSON: String?
    let createdAt: Date?
    let isDeleted: Bool
    
    /// Decodifica readByJSON → array di UID
    var readBy: [String] {
        guard let json = readByJSON,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }
}

// MARK: - Change type

enum ChatRemoteChange {
    case upsert(RemoteChatMessageDTO)
    case remove(String)
}

// MARK: - Store

final class ChatRemoteStore {
    
    private var db: Firestore { Firestore.firestore() }
    
    // MARK: - OUTBOUND
    
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
        // NOTA: readBy NON viene scritto qui — è gestito esclusivamente
        // da markAsRead() tramite FieldValue.arrayUnion, per evitare sovrascritture.
        
        let snap = try await ref.getDocument()
        if snap.exists { data.removeValue(forKey: "createdAt") }
        
        try await ref.setData(data, merge: true)
        KBLog.sync.kbInfo("ChatRemote upsert OK msgId=\(dto.id)")
    }
    
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
    }
    
    /// ✅ Segna i messaggi come letti dall'utente corrente.
    /// Usa arrayUnion per aggiungere l'UID senza sovrascrivere gli altri.
    func markAsRead(familyId: String, messageIds: [String], uid: String) async throws {
        guard !messageIds.isEmpty else { return }
        
        // Firestore batch: max 500 operazioni per batch
        let batches = messageIds.chunked(into: 450)
        
        for chunk in batches {
            let batch = db.batch()
            for msgId in chunk {
                let ref = db.collection("families")
                    .document(familyId)
                    .collection("chatMessages")
                    .document(msgId)
                // arrayUnion è idempotente: aggiunge uid solo se non c'è già
                batch.updateData(["readBy": FieldValue.arrayUnion([uid])], forDocument: ref)
            }
            try await batch.commit()
        }
        KBLog.sync.kbDebug("ChatRemote markAsRead \(messageIds.count) msgs uid=\(uid)")
    }
    
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
    }
    
    // MARK: - INBOUND (Realtime)
    
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
                        // ✅ readBy arriva come array di stringhe da Firestore
                        let readByArray = data["readBy"] as? [String] ?? []
                        let readByJSON: String? = {
                            guard !readByArray.isEmpty,
                                  let d = try? JSONEncoder().encode(readByArray),
                                  let s = String(data: d, encoding: .utf8) else { return nil }
                            return s
                        }()
                        
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
                            readByJSON:           readByJSON,
                            createdAt:            (data["createdAt"] as? Timestamp)?.dateValue(),
                            isDeleted:            data["isDeleted"] as? Bool ?? false
                        )
                        return .upsert(dto)
                    }
                }
                
                if !changes.isEmpty {
                    onChange(changes)
                }
            }
    }
}

// MARK: - Array+chunked

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
