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
//  Cifratura (dal 02/10/2026): testo dei messaggi e riassunto possono viaggiare
//  cifrati con la chiave della famiglia della conversazione (`contentEnc`,
//  `summaryEnc`, stesso formato delle note e del web). La lettura capisce sempre
//  entrambi i formati; la scrittura cifra quando è acceso l'interruttore remoto
//  `text_encryption_enabled`, che si accende insieme alle rules che
//  rifiutano il chiaro (`firestore.rules.next`).
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

        // Cifrate solo a interruttore acceso (`KBFeatureFlags`): finché le build
        // vecchie sono in giro riscriverebbero in chiaro l'intero array,
        // cancellando i messaggi che non sanno leggere. Acceso, senza chiave di
        // famiglia `encryptString` lancia: meglio non sincronizzare che caricare
        // il testo in chiaro.
        let encrypt = KBFeatureFlags.isTextEncryptionEnabled
        let fid = conversation.familyId
        let messagesPayload: [[String: Any]] = try conversation.sortedMessages.map { m in
            var row: [String: Any] = [
                "id": m.id,
                "roleRaw": m.roleRaw,
                "createdAt": Timestamp(date: m.createdAt)
            ]
            if encrypt {
                row["contentEnc"] = try NoteCryptoService.encryptString(m.content, familyId: fid, userId: uid)
            } else {
                row["content"] = m.content
            }
            return row
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
        // Un solo formato per volta: il campo dell'altro si cancella, o la lettura
        // (che preferisce `summaryEnc`) troverebbe un riassunto vecchio.
        if encrypt {
            data["summary"] = FieldValue.delete()
            if let summary = conversation.summary, !summary.isEmpty {
                data["summaryEnc"] = try NoteCryptoService.encryptString(summary, familyId: fid, userId: uid)
            } else {
                data["summaryEnc"] = FieldValue.delete()
            }
        } else {
            data["summary"] = conversation.summary as Any
            data["summaryEnc"] = FieldValue.delete()
        }
        data["summaryUpdatedAt"] = conversation.summaryUpdatedAt.map { Timestamp(date: $0) } as Any

        try await ref(uid: uid, docId: conversation.remoteDocId).setData(data, merge: true)
        KBLog.sync.kbInfo("[AIChatRemote] upsert OK docId=\(conversation.remoteDocId) msgs=\(messagesPayload.count)")
    }

    // MARK: - Decoding

    private func decode(_ doc: DocumentSnapshot) -> AIConversationDTO? {
        guard let data = doc.data() else { return nil }
        let familyId = data["familyId"] as? String ?? ""
        let uid = Auth.auth().currentUser?.uid ?? ""

        /// Campo cifrato se c'è, altrimenti il vecchio in chiaro. Un blob che non
        /// si apre torna nil: il messaggio si salta (l'inbound fa un'unione e non
        /// cancella mai i messaggi locali), mai una stringa vuota al suo posto.
        func open(_ enc: Any?, _ plain: Any?) -> String? {
            if let enc = enc as? String, !enc.isEmpty {
                return try? NoteCryptoService.decryptString(enc, familyId: familyId, userId: uid)
            }
            return plain as? String
        }

        let rawMessages = data["messages"] as? [[String: Any]] ?? []
        let messages: [AIMessageDTO] = rawMessages.compactMap { m in
            guard let id = m["id"] as? String,
                  let roleRaw = m["roleRaw"] as? String,
                  let content = open(m["contentEnc"], m["content"]) else { return nil }
            let createdAt = (m["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
            return AIMessageDTO(id: id, roleRaw: roleRaw, content: content, createdAt: createdAt)
        }
        if messages.count < rawMessages.count {
            KBLog.sync.kbError("[AIChatRemote] decode: \(rawMessages.count - messages.count) messaggi non decifrati docId=\(doc.documentID)")
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
            summary: open(data["summaryEnc"], data["summary"]),
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
                snap?.kbLogSnapshot("AIChat")
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
