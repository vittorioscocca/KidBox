//
//  AIChatRemoteStore.swift
//  KidBox
//
//  Sincronizzazione cross-device delle conversazioni AI.
//
//  Le chat AI sono PRIVATE per-utente: vengono salvate sotto
//  `users/{uid}/aiConversations/{docId}` e sincronizzate solo tra i dispositivi
//  dello stesso utente (nessun altro membro famiglia le vede).
//
//  Identità: il documento usa un id deterministico derivato dallo scope della
//  conversazione (provider + visitId), così ogni device scrive sullo stesso
//  documento e le conversazioni convergono. I messaggi sono incorporati come
//  array nel documento (testo leggero), con merge a livello di conversazione
//  via Last-Writer-Wins su `updatedAt`.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - DTOs

struct AIMessageDTO {
    let id: String
    let roleRaw: String
    let content: String
    let createdAt: Date
}

struct AIConversationDTO {
    let id: String
    let familyId: String
    let childId: String
    let visitId: String
    let providerRaw: String
    let ownerUserId: String
    let createdAt: Date
    let updatedAt: Date
    let summary: String?
    let summaryUpdatedAt: Date?
    let summarizedMessageCount: Int
    let isDeleted: Bool
    let messages: [AIMessageDTO]
}

enum AIConversationRemoteChange {
    case upsert(AIConversationDTO)
    case remove(String)
}

// MARK: - Remote store

final class AIChatRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func col(uid: String) -> CollectionReference {
        db.collection("users")
            .document(uid)
            .collection("aiConversations")
    }

    private func ref(uid: String, docId: String) -> DocumentReference {
        col(uid: uid).document(docId)
    }

    // MARK: - Upsert

    /// Carica (merge) l'intera conversazione, messaggi inclusi.
    func upsert(conversation: KBAIConversation) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let messagesPayload: [[String: Any]] = conversation.sortedMessages.map { m in
            [
                "id": m.id,
                "roleRaw": m.roleRaw,
                "content": m.content,
                "createdAt": Timestamp(date: m.createdAt)
            ]
        }

        var data: [String: Any] = [
            "conversationId": conversation.id,
            "familyId": conversation.familyId,
            "childId": conversation.childId,
            "visitId": conversation.visitId,
            "providerRaw": conversation.providerRaw,
            "ownerUserId": uid,
            "createdAt": Timestamp(date: conversation.createdAt),
            "updatedAt": Timestamp(date: conversation.updatedAt),
            "summarizedMessageCount": conversation.summarizedMessageCount,
            "isDeleted": false,
            "messages": messagesPayload
        ]
        data["summary"] = conversation.summary as Any
        data["summaryUpdatedAt"] = conversation.summaryUpdatedAt.map { Timestamp(date: $0) } as Any

        try await ref(uid: uid, docId: conversation.remoteDocId).setData(data, merge: true)
        KBLog.sync.kbInfo("[AIChatRemote] upsert OK docId=\(conversation.remoteDocId) msgs=\(messagesPayload.count)")
    }

    // MARK: - Decoding

    private func decode(_ doc: DocumentSnapshot) -> AIConversationDTO? {
        guard let data = doc.data() else { return nil }

        let rawMessages = data["messages"] as? [[String: Any]] ?? []
        let messages: [AIMessageDTO] = rawMessages.compactMap { m in
            guard let id = m["id"] as? String,
                  let roleRaw = m["roleRaw"] as? String,
                  let content = m["content"] as? String else { return nil }
            let createdAt = (m["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
            return AIMessageDTO(id: id, roleRaw: roleRaw, content: content, createdAt: createdAt)
        }

        return AIConversationDTO(
            id: data["conversationId"] as? String ?? doc.documentID,
            familyId: data["familyId"] as? String ?? "",
            childId: data["childId"] as? String ?? "",
            visitId: data["visitId"] as? String ?? "",
            providerRaw: data["providerRaw"] as? String ?? "claude",
            ownerUserId: data["ownerUserId"] as? String ?? "",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date.distantPast,
            summary: data["summary"] as? String,
            summaryUpdatedAt: (data["summaryUpdatedAt"] as? Timestamp)?.dateValue(),
            summarizedMessageCount: data["summarizedMessageCount"] as? Int ?? 0,
            isDeleted: data["isDeleted"] as? Bool ?? false,
            messages: messages
        )
    }

    // MARK: - Realtime listener

    func listenConversations(
        onChange: @escaping ([AIConversationRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration? {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.sync.kbError("[AIChatRemote] listen: not authenticated")
            return nil
        }

        KBLog.sync.kbInfo("[AIChatRemote] listenConversations ATTACH uid=\(uid)")

        return col(uid: uid)
            .addSnapshotListener(includeMetadataChanges: false) { [weak self] snap, err in
                guard let self else { return }
                if let err {
                    KBLog.sync.kbError("[AIChatRemote] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else { return }

                let changes: [AIConversationRemoteChange] = snap.documentChanges.compactMap { diff in
                    switch diff.type {
                    case .added, .modified:
                        guard let dto = self.decode(diff.document) else { return nil }
                        return .upsert(dto)
                    case .removed:
                        return .remove(diff.document.documentID)
                    }
                }
                if !changes.isEmpty { onChange(changes) }
            }
    }

    // MARK: - One-shot fetch (per backfill / pull on demand)

    func fetchAll() async throws -> [AIConversationDTO] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let snap = try await col(uid: uid).getDocuments()
        return snap.documents.compactMap { decode($0) }
    }
}
