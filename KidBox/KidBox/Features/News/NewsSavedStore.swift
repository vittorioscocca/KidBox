//
//  NewsSavedStore.swift
//  KidBox
//
//  Le notizie salvate col segnalibro (richiesta dell'utente del 04/10/2026):
//  di chi le salva, non della famiglia, su `users/{uid}/savedNews/{id}` con
//  id = SHA-256 dell'URL. Un ascolto per sessione, aperto la prima volta che
//  serve: a schermo arriva subito anche la scrittura fatta da qui (latenza
//  compensata da Firestore, anche offline). Android legge e scrive gli stessi
//  documenti; `deleteAccount` li cancella con l'account.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class NewsSavedStore: ObservableObject {

    static let shared = NewsSavedStore()

    /// Dalla più recente.
    @Published private(set) var items: [NewsSavedItem] = []
    @Published private(set) var savedIds: Set<String> = []
    /// Falso finché non arriva la prima risposta (cache o server).
    @Published private(set) var isLoaded = false

    private var uid: String?
    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()

    private init() {}

    private func collection(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("savedNews")
    }

    // MARK: - Lettura

    /// Ascolta le notizie salvate di chi è collegato. Richiamarla dalla scheda
    /// o dall'elenco non riapre l'ascolto: le letture si pagano una volta.
    func bind() {
        guard let uid = Auth.auth().currentUser?.uid, uid != self.uid else { return }
        listener?.remove()
        self.uid = uid
        items = []
        savedIds = []
        isLoaded = false
        listener = collection(uid)
            .order(by: "savedAtMs", descending: true)
            .addSnapshotListener { [weak self] snap, error in
                Task { @MainActor in
                    guard let self, self.uid == uid else { return }
                    if let error {
                        KBLog.data.kbError("NewsSaved listen failed: \(error.localizedDescription)")
                        self.isLoaded = true
                        return
                    }
                    guard let snap else { return }
                    let decoded = snap.documents.compactMap { Self.decode(id: $0.documentID, $0.data()) }
                    self.items = decoded
                    self.savedIds = Set(decoded.map(\.id))
                    self.isLoaded = true
                }
            }
    }

    func isSaved(_ item: NewsItem) -> Bool {
        savedIds.contains(NewsSavedItem.documentId(url: item.url))
    }

    // MARK: - Scrittura

    /// Il segnalibro: salva la notizia, o la toglie se c'era già. Vero se l'ha
    /// salvata.
    @discardableResult
    func toggle(_ item: NewsItem, placeName: String?) -> Bool {
        bind()
        guard let uid else { return false }
        let id = NewsSavedItem.documentId(url: item.url)
        if savedIds.contains(id) {
            remove(ids: [id])
            return false
        }
        let saved = NewsSavedItem(id: id, item: item, placeName: placeName, savedAt: Date())
        // Subito a schermo, senza aspettare l'ascolto.
        savedIds.insert(id)
        collection(uid).document(id).setData(Self.encode(saved)) { error in
            if let error { KBLog.data.kbError("NewsSaved save failed: \(error.localizedDescription)") }
        }
        return true
    }

    func remove(ids: Set<String>) {
        guard let uid, !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        savedIds.subtract(ids)
        // Un batch tiene al massimo 500 scritture.
        let all = Array(ids)
        for start in stride(from: 0, to: all.count, by: 400) {
            let batch = db.batch()
            for id in all[start..<min(start + 400, all.count)] {
                batch.deleteDocument(collection(uid).document(id))
            }
            batch.commit { error in
                if let error { KBLog.data.kbError("NewsSaved delete failed: \(error.localizedDescription)") }
            }
        }
    }

    func removeAll() {
        remove(ids: Set(items.map(\.id)))
    }

    // MARK: - Formato (uguale su Android)

    private static func encode(_ s: NewsSavedItem) -> [String: Any] {
        let i = s.item
        var d: [String: Any] = [
            "url": i.url,
            "title": i.title,
            "summary": i.summary,
            "category": i.category,
            "level": i.level,
            "source": i.source,
            "savedAtMs": Int64(s.savedAt.timeIntervalSince1970 * 1000),
        ]
        if let v = i.action, !v.isEmpty { d["action"] = v }
        if let v = i.keyDate, !v.isEmpty { d["keyDate"] = v }
        if let v = i.keyDateKind, !v.isEmpty { d["keyDateKind"] = v }
        if let v = i.publishedAt, !v.isEmpty { d["publishedAt"] = v }
        if let v = s.placeName, !v.isEmpty { d["placeName"] = v }
        return d
    }

    private static func decode(id: String, _ d: [String: Any]) -> NewsSavedItem? {
        guard let url = d["url"] as? String, !url.isEmpty,
              let title = d["title"] as? String, !title.isEmpty else { return nil }
        func text(_ key: String) -> String? { (d[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let item = NewsItem(
            category: text("category") ?? "",
            level: text("level") ?? "",
            title: title,
            summary: text("summary") ?? "",
            action: text("action"),
            keyDate: text("keyDate"),
            keyDateKind: text("keyDateKind"),
            publishedAt: text("publishedAt"),
            source: text("source") ?? "",
            url: url
        )
        let ms = (d["savedAtMs"] as? NSNumber)?.doubleValue ?? 0
        return NewsSavedItem(id: id, item: item, placeName: text("placeName"), savedAt: Date(timeIntervalSince1970: ms / 1000))
    }

    /// All'uscita dall'account: niente ascolto e niente copie a schermo.
    func resetOnSignOut() {
        listener?.remove()
        listener = nil
        uid = nil
        items = []
        savedIds = []
        isLoaded = false
    }
}
