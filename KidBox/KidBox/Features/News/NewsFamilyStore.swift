//
//  NewsFamilyStore.swift
//  KidBox
//
//  Le scelte delle Notizie che valgono per tutta la famiglia — accese o no,
//  dove vive, lingua delle edizioni — su `families/{familyId}/news/settings`
//  (le rules lo aprono ai membri col wildcard delle sottocollezioni). Un
//  ascolto sul documento: quando un membro accende le Notizie o cambia città,
//  gli altri lo vedono subito, senza ripassare dalla presentazione, e leggono
//  le stesse edizioni che la famiglia ha già pagato. Android legge e scrive lo
//  stesso documento, il server lo preferisce a quello che manda il telefono.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class NewsFamilyStore: ObservableObject {

    static let shared = NewsFamilyStore()

    @Published private(set) var settings = NewsFamilySettings()
    /// Falso finché non si sa com'è la famiglia (né cache né server): la
    /// scheda aspetta invece di mostrare la presentazione a chi ha già le
    /// Notizie accese da un altro membro.
    @Published private(set) var isLoaded = false

    private(set) var familyId: String?
    private var listener: ListenerRegistration?
    /// L'ultima scrittura: le chiamate al server la aspettano, così un
    /// «Attiva» appena toccato non arriva dopo la richiesta dell'edizione.
    private var lastWrite: Task<Void, Never>?
    private let db = Firestore.firestore()

    private init() {}

    private func ref(_ familyId: String) -> DocumentReference {
        db.collection("families").document(familyId).collection("news").document("settings")
    }

    // MARK: - Lettura

    func bind(familyId: String) {
        guard !familyId.isEmpty, familyId != self.familyId else { return }
        listener?.remove()
        self.familyId = familyId
        if let cached = Self.loadLocal(familyId) {
            settings = cached
            isLoaded = true
        } else {
            settings = NewsFamilySettings()
            isLoaded = false
        }
        // Con i cambi di metadati: un documento che non c'è, letto da una
        // cache vuota, non dice che la famiglia ha le Notizie spente — lo
        // dice solo la conferma del server, che altrimenti non arriverebbe
        // se la cache è identica.
        listener = ref(familyId).addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            Task { @MainActor in
                guard let self, self.familyId == familyId else { return }
                if let error {
                    KBLog.settings.kbError("NewsFamily listen failed: \(error.localizedDescription)")
                    return
                }
                guard let snap else { return }
                if snap.exists, let raw = snap.data() {
                    let remote = Self.decode(raw)
                    if remote != self.settings { self.settings = remote }
                    Self.saveLocal(remote, familyId: familyId)
                    self.isLoaded = true
                } else if !snap.metadata.isFromCache {
                    self.settings = NewsFamilySettings()
                    Self.clearLocal(familyId)
                    self.isLoaded = true
                }
            }
        }
    }

    // MARK: - Scrittura

    /// Cambia le scelte della famiglia: subito sul telefono, poi sul server.
    /// La lingua delle edizioni la fissa chi le accende per primo.
    func update(_ change: (inout NewsFamilySettings) -> Void) {
        guard let familyId else { return }
        var next = settings
        change(&next)
        if next.enabled, next.place == nil { next.place = .deviceDefault }
        if next.enabled, next.lang == nil { next.lang = LanguageManager.shared.currentLanguageCode }
        guard next != settings else { return }
        next.updatedAt = Date()
        next.updatedBy = Auth.auth().currentUser?.uid
        settings = next
        isLoaded = true
        Self.saveLocal(next, familyId: familyId)
        let previous = lastWrite
        let data = Self.encode(next)
        let target = ref(familyId)
        lastWrite = Task {
            await previous?.value
            do {
                try await target.setData(data, merge: true)
            } catch {
                KBLog.settings.kbError("NewsFamily push failed: \(error.localizedDescription)")
            }
        }
    }

    /// Aspetta che l'ultima scelta sia arrivata al server.
    func settled() async {
        await lastWrite?.value
    }

    // MARK: - Formato (uguale su Android)

    private static func encode(_ s: NewsFamilySettings) -> [String: Any] {
        var d: [String: Any] = [
            "enabled": s.enabled,
            "updatedAtMs": Int64(s.updatedAt.timeIntervalSince1970 * 1000),
        ]
        d["place"] = s.place?.dictionary ?? NSNull()
        d["lang"] = s.lang ?? NSNull()
        d["updatedBy"] = s.updatedBy ?? NSNull()
        return d
    }

    private static func decode(_ d: [String: Any]) -> NewsFamilySettings {
        var s = NewsFamilySettings()
        s.enabled = d["enabled"] as? Bool ?? false
        s.place = NewsPlace(dictionary: d["place"] as? [String: Any])
        s.lang = (d["lang"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        s.updatedBy = d["updatedBy"] as? String
        if let ms = (d["updatedAtMs"] as? NSNumber)?.doubleValue {
            s.updatedAt = Date(timeIntervalSince1970: ms / 1000)
        }
        return s
    }

    private static func defaultsKey(_ familyId: String) -> String { "kb.news.family.\(familyId)" }

    private static func loadLocal(_ familyId: String) -> NewsFamilySettings? {
        guard let raw = UserDefaults.standard.dictionary(forKey: defaultsKey(familyId)) else { return nil }
        return decode(raw)
    }

    private static func saveLocal(_ s: NewsFamilySettings, familyId: String) {
        let d = encode(s).filter { !($0.value is NSNull) }
        UserDefaults.standard.set(d, forKey: defaultsKey(familyId))
    }

    private static func clearLocal(_ familyId: String) {
        UserDefaults.standard.removeObject(forKey: defaultsKey(familyId))
    }

    /// All'uscita dall'account: niente ascolto e niente copie sul telefono.
    func resetOnSignOut() {
        listener?.remove()
        listener = nil
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("kb.news.family.") {
            defaults.removeObject(forKey: key)
        }
        familyId = nil
        settings = NewsFamilySettings()
        isLoaded = false
        lastWrite = nil
    }
}
