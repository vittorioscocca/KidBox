//
//  NewsPrefsStore.swift
//  KidBox
//
//  Le scelte delle Notizie (categorie, luogo, offerte su misura): sul telefono
//  per partire subito, su `users/{uid}.newsPrefs` per gli altri dispositivi
//  dello stesso utente. Vince la modifica più recente (`updatedAtMs`), come
//  per le altre preferenze sincronizzate. Android legge e scrive lo stesso campo.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class NewsPrefsStore: ObservableObject {

    static let shared = NewsPrefsStore()

    @Published private(set) var prefs: NewsPrefs

    private static let defaultsKey = "kb.news.prefs"
    private let db = Firestore.firestore()

    private init() {
        prefs = Self.loadLocal() ?? NewsPrefs()
    }

    // MARK: - Lettura

    /// Rilegge da Firestore e tiene la versione più recente fra le due.
    func refreshFromRemote() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            guard let raw = snap.get("newsPrefs") as? [String: Any],
                  let remote = Self.decode(raw) else { return }
            if remote.updatedAt > prefs.updatedAt {
                prefs = remote
                Self.saveLocal(remote)
            }
        } catch {
            KBLog.settings.kbError("NewsPrefs refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Scrittura

    func update(_ change: (inout NewsPrefs) -> Void) {
        var next = prefs
        change(&next)
        if next.categories.isEmpty { next.categories = NewsCategory.allCases }
        next.updatedAt = Date()
        guard next != prefs else { return }
        prefs = next
        Self.saveLocal(next)
        Task { await push(next) }
    }

    private func push(_ p: NewsPrefs) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).setData(["newsPrefs": Self.encode(p)], merge: true)
        } catch {
            KBLog.settings.kbError("NewsPrefs push failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Formato (uguale su Android)

    private static func encode(_ p: NewsPrefs) -> [String: Any] {
        var d: [String: Any] = [
            "enabled": p.enabled,
            "categories": p.categories.map(\.rawValue),
            "personalOffers": p.personalOffers,
            "updatedAtMs": Int64(p.updatedAt.timeIntervalSince1970 * 1000),
        ]
        d["place"] = p.place?.dictionary ?? NSNull()
        return d
    }

    private static func decode(_ d: [String: Any]) -> NewsPrefs? {
        var p = NewsPrefs()
        p.enabled = d["enabled"] as? Bool ?? false
        if let cats = d["categories"] as? [String] {
            let parsed = cats.compactMap(NewsCategory.init(rawValue:))
            p.categories = parsed.isEmpty ? NewsCategory.allCases : NewsCategory.allCases.filter(parsed.contains)
        }
        p.place = NewsPlace(dictionary: d["place"] as? [String: Any])
        p.personalOffers = d["personalOffers"] as? Bool ?? true
        if let ms = (d["updatedAtMs"] as? NSNumber)?.doubleValue {
            p.updatedAt = Date(timeIntervalSince1970: ms / 1000)
        }
        return p
    }

    private static func loadLocal() -> NewsPrefs? {
        guard let raw = UserDefaults.standard.dictionary(forKey: defaultsKey) else { return nil }
        return decode(raw)
    }

    private static func saveLocal(_ p: NewsPrefs) {
        var d = encode(p)
        if d["place"] is NSNull { d.removeValue(forKey: "place") }
        UserDefaults.standard.set(d, forKey: defaultsKey)
    }

    /// All'uscita dall'account: le scelte sono dell'utente, non del telefono.
    func resetOnSignOut() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        prefs = NewsPrefs()
    }
}
