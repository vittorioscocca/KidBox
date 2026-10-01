//
//  FamilyRequestService.swift
//  KidBox
//
//  Richieste di famiglia: «Chi prende Marco giovedì?». Chi chiede sceglie i
//  membri da avvisare e, se vuole, manda un link a chi non ha l'app; la prima
//  risposta «Ci penso io» chiude la richiesta e fa nascere il to-do assegnato,
//  visibile a tutta la famiglia.
//
//  Il client CREA la richiesta e può solo ritirarla finché è aperta (le rules
//  non gli permettono altro). Le risposte passano dalla callable
//  `respondToRequest`, che decide «il primo Io vince» in una transazione e
//  crea il to-do lato server. Disegno completo: internal/richieste-disegno.md.
//
//  Niente SwiftData: una richiesta vive qualche ora o qualche giorno e serve
//  solo mentre è aperta, quindi si legge dal vivo con un listener legato alla
//  vita della view (`.task`), non con l'outbox del SyncCenter.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import CryptoKit
internal import os

// MARK: - Modello

struct FamilyRequest: Identifiable, Equatable {

    enum Status: String {
        case open, claimed, expired, cancelled
    }

    struct Response: Equatable {
        /// `uid` per i membri, `ext_<id>` per chi risponde dal link.
        let key: String
        let answer: String
        let name: String
        let isExternal: Bool

        var isYes: Bool { answer == "yes" }
    }

    let id: String
    let familyId: String
    let title: String
    let notes: String?
    let dueAt: Date?
    let dueHasTime: Bool
    let listId: String
    let childId: String
    let createdBy: String
    let recipients: [String]
    let status: Status
    let expiresAt: Date?
    let responses: [Response]
    let claimedByUid: String?
    let claimedByName: String?
    let claimedByExternal: Bool
    let todoId: String?
    let externalLabel: String?
    let hasExternalLink: Bool

    /// Aperta e non ancora scaduta. Lo scheduler la chiude entro 15 minuti
    /// dalla scadenza: nel frattempo il client non deve offrirla come aperta.
    var isOpen: Bool {
        status == .open && (expiresAt.map { $0 > Date() } ?? true)
    }

    func response(of key: String) -> Response? {
        responses.first { $0.key == key }
    }

    init?(snapshot: DocumentSnapshot, familyId: String) {
        guard let d = snapshot.data(),
              let title = d["title"] as? String,
              let createdBy = d["createdBy"] as? String
        else { return nil }

        self.id = snapshot.documentID
        self.familyId = familyId
        self.title = title
        let notes = (d["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = (notes?.isEmpty ?? true) ? nil : notes
        self.dueAt = (d["dueAt"] as? Timestamp)?.dateValue()
        self.dueHasTime = (d["dueHasTime"] as? Bool) ?? true
        self.listId = (d["listId"] as? String) ?? ""
        self.childId = (d["childId"] as? String) ?? ""
        self.createdBy = createdBy
        self.recipients = (d["recipients"] as? [String]) ?? []
        self.status = Status(rawValue: (d["status"] as? String) ?? "") ?? .open
        self.expiresAt = (d["expiresAt"] as? Timestamp)?.dateValue()

        let raw = (d["responses"] as? [String: Any]) ?? [:]
        self.responses = raw.compactMap { key, value in
            guard let m = value as? [String: Any], let answer = m["answer"] as? String else { return nil }
            return Response(
                key: key,
                answer: answer,
                name: (m["name"] as? String) ?? "",
                isExternal: (m["type"] as? String) == "external"
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let claimed = d["claimedBy"] as? [String: Any]
        self.claimedByUid = claimed?["uid"] as? String
        self.claimedByName = claimed?["name"] as? String
        self.claimedByExternal = (claimed?["type"] as? String) == "external"
        self.todoId = d["todoId"] as? String

        let external = d["external"] as? [String: Any]
        self.externalLabel = (external?["label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.hasExternalLink = external != nil
    }
}

// MARK: - Servizio

enum FamilyRequestService {

    /// Chi chiedere, come lo sceglie l'utente nel foglio «Chiedi a…».
    struct Draft: Equatable {
        var recipients: [String] = []
        var askOutside = false
        /// Come chi chiede chiama la persona fuori dall'app («Nonna»). Serve a
        /// lui, nell'elenco; alla persona non si mostra.
        var outsideLabel = ""
        /// Il link porta anche l'invito alla famiglia (scelta del 01/10/2026:
        /// sì di default, è il motivo per cui la funzione esiste).
        var includeInvite = true

        var isEmpty: Bool { recipients.isEmpty && !askOutside }
    }

    /// Richiesta appena creata: il link c'è solo se si è chiesto fuori.
    struct Created: Identifiable {
        let id: String
        let shareLink: String?
        let shareText: String?
        let notifiedCount: Int
    }

    enum Outcome: Equatable {
        case claimedByMe
        case claimedBy(name: String)
        case declined
        case closed
    }

    enum Failure: LocalizedError {
        case notAuthenticated
        case dueInPast

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return String(localized: "Accedi di nuovo per inviare la richiesta.")
            case .dueInPast:
                return String(localized: "La scadenza è già passata: cambiala per chiedere.")
            }
        }
    }

    static let linkBaseURL = "https://kidboxapp.com/r"
    /// Senza scadenza la richiesta resta aperta due giorni.
    static let defaultTTL: TimeInterval = 48 * 3600
    /// Le rules accettano al massimo 7 giorni (più un'ora di margine).
    static let maxTTL: TimeInterval = 7 * 24 * 3600 - 600
    private static let titleMax = 200
    private static let functions = Functions.functions(region: "europe-west1")

    private static func collection(_ familyId: String) -> CollectionReference {
        Firestore.firestore().collection("families").document(familyId).collection("requests")
    }

    /// Fine della richiesta: alla scadenza del to-do (dopo non ha senso), al
    /// massimo 7 giorni; senza scadenza 48 ore. `nil` se la scadenza è già
    /// passata o sta per passare.
    ///
    /// Un to-do «tutto il giorno» ha `dueAt` alle 9:00 (l'ora del promemoria):
    /// la richiesta resta aperta fino a fine giornata, o chiedere alle 10 per
    /// oggi risulterebbe già scaduto.
    static func expiresAt(dueAt: Date?, hasTime: Bool, now: Date = Date()) -> Date? {
        guard let dueAt else { return now.addingTimeInterval(defaultTTL) }
        var cutoff = dueAt
        if !hasTime, let endOfDay = Calendar.current.date(
            byAdding: DateComponents(day: 1, second: -60),
            to: Calendar.current.startOfDay(for: dueAt)
        ) {
            cutoff = endOfDay
        }
        guard cutoff > now.addingTimeInterval(5 * 60) else { return nil }
        return min(cutoff, now.addingTimeInterval(maxTTL))
    }

    // MARK: Crea

    /// Crea la richiesta. Se si chiede fuori dall'app prepara anche il link,
    /// con il token nel frammento (il server ne vede solo l'impronta) e, se
    /// scelto, l'invito alla famiglia: lo stesso `createInvite` del foglio
    /// «Invita», quindi monouso e valido 7 giorni.
    static func create(
        familyId: String,
        childId: String,
        listId: String,
        title: String,
        notes: String?,
        isUrgent: Bool,
        dueAt: Date?,
        dueHasTime: Bool,
        draft: Draft,
        familyName: String,
        inviterName: String
    ) async throws -> Created {
        guard let uid = Auth.auth().currentUser?.uid else { throw Failure.notAuthenticated }
        guard let expires = expiresAt(dueAt: dueAt, hasTime: dueHasTime) else { throw Failure.dueInPast }

        let requestId = UUID().uuidString
        let cleanTitle = String(title.prefix(titleMax))
        let recipients = Array(Set(draft.recipients.filter { $0 != uid })).sorted().prefix(20)

        var external: [String: Any]? = nil
        var shareLink: String? = nil
        if draft.askOutside {
            let token = InviteCrypto.randomBytes(32).base64url()
            let tokenHash = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
            var fields: [String: Any] = [
                "label": draft.outsideLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                "tokenHash": tokenHash,
            ]
            var fragment = "t=\(token)"
            if draft.includeInvite {
                let invite = try await InviteWrapService().createInvite(
                    familyId: familyId,
                    familyName: familyName,
                    inviterDisplayName: inviterName
                )
                fields["inviteId"] = invite.inviteId
                fragment += "&k=\(invite.secretBase64url)"
            }
            external = fields
            shareLink = "\(linkBaseURL)?f=\(familyId)&r=\(requestId)#\(fragment)"
        }

        let data: [String: Any] = [
            "kind": "todo",
            "title": cleanTitle,
            "notes": notes ?? NSNull(),
            "priority": isUrgent ? 1 : 0,
            "dueAt": dueAt.map { Timestamp(date: $0) } ?? NSNull(),
            "dueHasTime": dueHasTime,
            "listId": listId,
            "childId": childId,
            "createdBy": uid,
            "createdVia": "app",
            "recipients": Array(recipients),
            "expiresAt": Timestamp(date: expires),
            "status": "open",
            "external": external ?? NSNull(),
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        try await collection(familyId).document(requestId).setData(data)
        KBLog.todo.kbInfo("FamilyRequest created requestId=\(requestId) recipients=\(recipients.count) outside=\(draft.askOutside)")

        var shareText: String? = nil
        if let shareLink {
            saveShareLink(shareLink, requestId: requestId)
            shareText = Self.shareText(title: cleanTitle, dueAt: dueAt, dueHasTime: dueHasTime, link: shareLink)
        }
        return Created(id: requestId, shareLink: shareLink, shareText: shareText, notifiedCount: recipients.count)
    }

    static func shareText(title: String, dueAt: Date?, dueHasTime: Bool, link: String) -> String {
        let what: String
        if let dueAt {
            what = "\(title) · \(whenText(dueAt, hasTime: dueHasTime))"
        } else {
            what = title
        }
        return String(localized: "Puoi pensarci tu? «\(what)»\nRispondi qui, anche senza app: \(link)")
    }

    static func whenText(_ date: Date, hasTime: Bool) -> String {
        if hasTime {
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    // MARK: Rispondi / ritira

    /// «Ci penso io» o «Non posso». Il server decide chi vince e crea il to-do.
    static func respond(familyId: String, requestId: String, yes: Bool) async throws -> Outcome {
        do {
            let result = try await functions.httpsCallable("respondToRequest").call([
                "familyId": familyId,
                "requestId": requestId,
                "answer": yes ? "yes" : "no",
            ])
            let d = (result.data as? [String: Any]) ?? [:]
            let outcome = d["outcome"] as? String
            KBLog.todo.kbInfo("FamilyRequest respond requestId=\(requestId) yes=\(yes) outcome=\(outcome ?? "nil")")
            if outcome == "declined" { return .declined }
            if (d["status"] as? String) == "claimed" {
                if (d["mine"] as? Bool) == true { return .claimedByMe }
                let claimed = d["claimedBy"] as? [String: Any]
                return .claimedBy(name: (claimed?["name"] as? String) ?? "")
            }
            return .closed
        } catch {
            let ns = error as NSError
            let details = ns.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
            let reason = details?["reason"] as? String
            // Richiesta sparita o propria: per l'utente è «non più disponibile».
            if reason == "not_found" || reason == "own_request" { return .closed }
            KBLog.todo.kbError("FamilyRequest respond failed requestId=\(requestId) err=\(error.localizedDescription)")
            throw error
        }
    }

    /// Ritira una richiesta aperta. Le rules lo permettono solo a chi l'ha
    /// fatta e solo finché nessuno l'ha presa.
    static func cancel(familyId: String, requestId: String) async throws {
        try await collection(familyId).document(requestId).updateData([
            "status": "cancelled",
            "cancelledAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ])
        forgetShareLink(requestId: requestId)
        KBLog.todo.kbInfo("FamilyRequest cancelled requestId=\(requestId)")
    }

    // MARK: Ascolto

    /// Le richieste aperte della famiglia. Il listener vive quanto il `for await`
    /// che lo consuma: niente start/stop da onAppear/onDisappear, che fra
    /// padre e figlio arrivano nell'ordine sbagliato.
    static func observeOpen(familyId: String) -> AsyncStream<[FamilyRequest]> {
        AsyncStream { continuation in
            let registration = collection(familyId)
                .whereField("status", isEqualTo: "open")
                .addSnapshotListener { snap, error in
                    if let error {
                        KBLog.todo.kbError("FamilyRequest listener error familyId=\(familyId) err=\(error.localizedDescription)")
                        return
                    }
                    // `documents` e non `documentChanges`: con la cache il
                    // delta può arrivare vuoto anche con risultati veri.
                    let list = (snap?.documents ?? [])
                        .compactMap { FamilyRequest(snapshot: $0, familyId: familyId) }
                        .filter(\.isOpen)
                        .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
                    continuation.yield(list)
                }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    /// Una richiesta sola, anche chiusa: serve al foglio aperto da una notifica.
    static func observe(familyId: String, requestId: String) -> AsyncStream<FamilyRequest?> {
        AsyncStream { continuation in
            let registration = collection(familyId).document(requestId)
                .addSnapshotListener { snap, error in
                    if let error {
                        KBLog.todo.kbError("FamilyRequest doc listener error requestId=\(requestId) err=\(error.localizedDescription)")
                        continuation.yield(nil)
                        return
                    }
                    guard let snap, snap.exists else {
                        continuation.yield(nil)
                        return
                    }
                    continuation.yield(FamilyRequest(snapshot: snap, familyId: familyId))
                }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    // MARK: Link salvati sul telefono di chi chiede

    /// Il token esiste solo nel link: il server ne ha l'impronta. Per poterlo
    /// rimandare («Invia di nuovo il link») lo si tiene su questo telefono.
    private static let linksKey = "kb_familyRequestLinks"

    static func savedShareLink(requestId: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: linksKey) as? [String: String])?[requestId]
    }

    private static func saveShareLink(_ link: String, requestId: String) {
        var all = (UserDefaults.standard.dictionary(forKey: linksKey) as? [String: String]) ?? [:]
        all[requestId] = link
        // Le richieste durano al massimo 7 giorni: ne bastano poche.
        if all.count > 30 { all = Dictionary(uniqueKeysWithValues: all.suffix(30).map { ($0.key, $0.value) }) }
        UserDefaults.standard.set(all, forKey: linksKey)
    }

    private static func forgetShareLink(requestId: String) {
        var all = (UserDefaults.standard.dictionary(forKey: linksKey) as? [String: String]) ?? [:]
        all[requestId] = nil
        UserDefaults.standard.set(all, forKey: linksKey)
    }
}
