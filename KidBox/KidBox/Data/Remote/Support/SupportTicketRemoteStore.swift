//
//  SupportTicketRemoteStore.swift
//  KidBox
//

import FirebaseAuth
import FirebaseFirestore
import Foundation
import UIKit

struct SupportConversationMessagePayload {
    let role: String
    let content: Any
}

struct SupportTicketSubmitPayload {
    let id: String
    let familyId: String
    let uid: String
    let userEmail: String
    let type: String
    let title: String
    let summary: String
    let conversation: [SupportConversationMessagePayload]
    var imagesBase64: [String] = []
    let appVersion: String
    let osVersion: String
    let device: String
    var rawLogs: String?

    static let validTypes: Set<String> = ["question", "bug", "suggestion"]

    static func make(
        id: String,
        familyId: String,
        type: String,
        title: String,
        summary: String,
        conversation: [SupportConversationMessagePayload],
        imagesBase64: [String] = [],
        rawLogs: String? = nil,
    ) throws -> SupportTicketSubmitPayload {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "SupportTicket", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Autenticazione richiesta.",
            ])
        }
        guard validTypes.contains(type) else {
            throw NSError(domain: "SupportTicket", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Tipo ticket non valido.",
            ])
        }
        guard imagesBase64.count <= SupportImageEncoder.maxImages else {
            throw NSError(domain: "SupportTicket", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Massimo \(SupportImageEncoder.maxImages) immagini.",
            ])
        }
        let logs = rawLogs?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachLogs = (logs?.isEmpty == false) && type == "bug" ? logs : nil
        return SupportTicketSubmitPayload(
            id: id,
            familyId: familyId,
            uid: user.uid,
            userEmail: user.email ?? "",
            type: type,
            title: title,
            summary: summary,
            conversation: conversation,
            imagesBase64: imagesBase64,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            osVersion: UIDevice.current.systemVersion,
            device: "\(UIDevice.current.model) \(UIDevice.current.name)".trimmingCharacters(in: .whitespaces),
            rawLogs: attachLogs,
        )
    }

    func conversationFirestoreArray() -> [[String: Any]] {
        conversation.map { msg in
            ["role": msg.role, "content": msg.content]
        }
    }
}

struct SupportTicketDTO: Identifiable {
    let id: String
    let familyId: String
    let uid: String
    let userEmail: String
    let type: String
    let title: String
    let summary: String
    let status: String
    let conversation: [[String: Any]]
    let createdAtMillis: Int64?
}

final class SupportTicketRemoteStore {
    static let shared = SupportTicketRemoteStore()

    private let collection = "support_tickets"
    private var db: Firestore { Firestore.firestore() }

    private init() {}

    func submit(_ ticket: SupportTicketSubmitPayload) async throws -> String {
        let uid = Auth.auth().currentUser?.uid
        guard let uid, ticket.uid == uid else {
            throw NSError(domain: "SupportTicket", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Utente non autenticato.",
            ])
        }

        let docId = ticket.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? db.collection(collection).document().documentID
            : ticket.id

        let data = try SupportTicketFirestorePayload.buildDocumentData(
            ticket: ticket,
            docId: docId,
        )

        try await db.collection(collection).document(docId).setData(data, merge: true)
        KBLog.data.kbInfo("Support ticket submitted id=\(docId) type=\(ticket.type)")
        return docId
    }
}
