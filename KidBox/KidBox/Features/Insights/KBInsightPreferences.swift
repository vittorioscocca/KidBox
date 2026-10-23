//
//  KBInsightPreferences.swift
//  KidBox
//
//  Preferenze degli avvisi proattivi, per utente: come arrivano, gli orari di
//  silenzio, i tipi spenti. Vivono in `users/{uid}.insightPrefs` così seguono
//  l'utente su ogni dispositivo, con una copia locale perché il motore gira
//  anche offline e in background, dove non si legge Firestore.
//

import Combine
import FirebaseAuth
import FirebaseFirestore
import Foundation

struct KBInsightPreferences: Codable, Equatable, Sendable {

    enum Delivery: String, Codable, CaseIterable, Sendable {
        /// Ogni avviso all'orario giusto.
        case immediate
        /// I to-do in un solo riepilogo serale; le dosi restano puntuali.
        case eveningDigest
        /// Nessun avviso.
        case off
    }

    var delivery: Delivery = .immediate
    /// Minuti dalla mezzanotte. Se l'inizio viene dopo la fine, la finestra
    /// scavalca la mezzanotte (21:30–8:00).
    var quietStartMinutes: Int = 21 * 60 + 30
    var quietEndMinutes: Int = 8 * 60
    var mutedTypes: Set<KBInsightType> = []

    static let digestMinutes = 19 * 60

    func isMuted(_ type: KBInsightType) -> Bool { mutedTypes.contains(type) }

    /// `true` se l'orario cade negli orari di silenzio.
    func isQuiet(minutes: Int) -> Bool {
        guard quietStartMinutes != quietEndMinutes else { return false }
        if quietStartMinutes < quietEndMinutes {
            return minutes >= quietStartMinutes && minutes < quietEndMinutes
        }
        return minutes >= quietStartMinutes || minutes < quietEndMinutes
    }

    // MARK: - Firestore

    var firestoreValue: [String: Any] {
        [
            "delivery": delivery.rawValue,
            "quietStart": quietStartMinutes,
            "quietEnd": quietEndMinutes,
            "mutedTypes": mutedTypes.map(\.rawValue).sorted(),
        ]
    }

    init() {}

    init(firestore map: [String: Any]) {
        if let raw = map["delivery"] as? String, let d = Delivery(rawValue: raw) { delivery = d }
        if let v = map["quietStart"] as? Int, (0..<1440).contains(v) { quietStartMinutes = v }
        if let v = map["quietEnd"] as? Int, (0..<1440).contains(v) { quietEndMinutes = v }
        if let types = map["mutedTypes"] as? [String] {
            mutedTypes = Set(types.compactMap(KBInsightType.init(rawValue:)))
        }
    }
}

@MainActor
final class KBInsightPreferencesStore: ObservableObject {

    static let shared = KBInsightPreferencesStore()

    private static let localKey = "kb_insightPrefs"
    private static let remoteField = "insightPrefs"
    /// Rilettura da Firestore al più ogni tanto: il motore gira spesso.
    private static let remoteRefreshInterval: TimeInterval = 10 * 60

    @Published private(set) var prefs: KBInsightPreferences
    private var lastRemoteRefresh: Date?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.localKey),
           let saved = try? JSONDecoder().decode(KBInsightPreferences.self, from: data) {
            prefs = saved
        } else {
            prefs = KBInsightPreferences()
        }
    }

    /// Dall'utente: copia locale subito, Firestore in merge.
    func update(_ change: (inout KBInsightPreferences) -> Void) {
        var next = prefs
        change(&next)
        guard next != prefs else { return }
        apply(next)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let value = next.firestoreValue
        Task {
            do {
                try await Firestore.firestore().collection("users").document(uid)
                    .setData([Self.remoteField: value], merge: true)
            } catch {
                KBLog.ai.kbError("InsightPrefs: remote save failed \(error.localizedDescription)")
            }
        }
    }

    /// Allinea la copia locale a quella dell'account (un altro dispositivo può
    /// averla cambiata). Non più di una lettura ogni dieci minuti.
    func refreshFromRemoteIfNeeded(now: Date = Date()) async {
        if let last = lastRemoteRefresh, now.timeIntervalSince(last) < Self.remoteRefreshInterval { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        lastRemoteRefresh = now
        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let map = snap.get(Self.remoteField) as? [String: Any] else { return }
            let remote = KBInsightPreferences(firestore: map)
            if remote != prefs { apply(remote) }
        } catch {
            KBLog.ai.kbDebug("InsightPrefs: remote read failed \(error.localizedDescription)")
        }
    }

    private func apply(_ next: KBInsightPreferences) {
        prefs = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: Self.localKey)
        }
        KBInsightRunner.shared.preferencesDidChange()
    }
}
