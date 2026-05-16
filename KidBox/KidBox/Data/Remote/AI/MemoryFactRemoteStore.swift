//
//  MemoryFactRemoteStore.swift
//  KidBox
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - DTO

struct RemoteMemoryFactDTO: Sendable {
    let id: String
    let familyId: String
    let content: String
    let categoryRaw: String
    let createdAt: Date?
    let updatedAt: Date?
    let sourceConversationId: String?

    init(
        id: String,
        familyId: String,
        content: String,
        categoryRaw: String,
        createdAt: Date?,
        updatedAt: Date?,
        sourceConversationId: String?
    ) {
        self.id = id
        self.familyId = familyId
        self.content = content
        self.categoryRaw = categoryRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceConversationId = sourceConversationId
    }

    init(from fact: KBMemoryFact) {
        id = fact.id
        familyId = fact.familyId
        content = fact.content
        categoryRaw = fact.categoryRaw
        createdAt = fact.createdAt
        updatedAt = fact.updatedAt
        sourceConversationId = fact.sourceConversationId
    }
}

// MARK: - Remote Store

/// Firestore remote store per i fatti di memoria familiare dell'agente AI.
///
/// Percorso: `families/{familyId}/memoryFacts/{factId}`
final class MemoryFactRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func ref(familyId: String, factId: String) -> DocumentReference {
        db.collection("families")
            .document(familyId)
            .collection("memoryFacts")
            .document(factId)
    }

    private func col(familyId: String) -> CollectionReference {
        db.collection("families")
            .document(familyId)
            .collection("memoryFacts")
    }

    // MARK: - OUTBOUND

    func upsert(dto: RemoteMemoryFactDTO) async throws {
        guard Auth.auth().currentUser != nil else {
            KBLog.auth.kbError("MemoryFact upsert failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }

        KBLog.ai.kbInfo("MemoryFact upsert familyId=\(dto.familyId) factId=\(dto.id)")

        var data: [String: Any] = [
            "id": dto.id,
            "familyId": dto.familyId,
            "content": dto.content,
            "categoryRaw": dto.categoryRaw,
            "createdAt": Timestamp(date: dto.createdAt ?? Date()),
            "updatedAt": FieldValue.serverTimestamp(),
        ]

        if let sid = dto.sourceConversationId, !sid.isEmpty {
            data["sourceConversationId"] = sid
        } else {
            data["sourceConversationId"] = FieldValue.delete()
        }

        try await ref(familyId: dto.familyId, factId: dto.id).setData(data, merge: true)

        KBLog.ai.kbInfo("MemoryFact upsert OK familyId=\(dto.familyId) factId=\(dto.id)")
    }

    // MARK: - INBOUND

    func fetchAll(familyId: String) async throws -> [RemoteMemoryFactDTO] {
        guard Auth.auth().currentUser != nil else {
            KBLog.auth.kbError("MemoryFact fetchAll failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }

        KBLog.ai.kbInfo("MemoryFact fetchAll start familyId=\(familyId)")

        let snap = try await col(familyId: familyId).getDocuments()
        let dtos = snap.documents.compactMap { Self.decode($0, familyId: familyId) }

        KBLog.ai.kbInfo("MemoryFact fetchAll OK familyId=\(familyId) count=\(dtos.count)")
        return dtos
    }

    private static func decode(_ doc: QueryDocumentSnapshot, familyId: String) -> RemoteMemoryFactDTO? {
        let d = doc.data()
        guard let content = d["content"] as? String, !content.isEmpty else { return nil }

        let id = (d["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? doc.documentID
        let categoryRaw = (d["categoryRaw"] as? String) ?? MemoryFactCategory.altro.rawValue
        let fid = (d["familyId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? familyId
        let sourceConversationId = d["sourceConversationId"] as? String

        return RemoteMemoryFactDTO(
            id: id,
            familyId: fid,
            content: content,
            categoryRaw: categoryRaw,
            createdAt: (d["createdAt"] as? Timestamp)?.dateValue(),
            updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
            sourceConversationId: sourceConversationId
        )
    }
}
