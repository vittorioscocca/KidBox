//
//  KBAnalytics.swift
//  KidBox
//
//  Design: internal/analytics-active-users.md
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Logger analytics lato client.
///
/// Registra i due soli eventi che il server non può vedere: le **letture**
/// (`content_retrieved`) e le aperture (`session_start`). Un trigger Firestore
/// scatta su una scrittura; aprire il wallet, copiare una password o guardare
/// dov'è un familiare non producono scritture. Senza questo logger il DAU
/// misurerebbe solo chi crea contenuti — l'onboarding, non il prodotto.
///
/// **Privacy — vincolo non negoziabile.** Si registra la FORMA della lettura, mai
/// l'OGGETTO: niente id, titoli, nomi file, testo. Un registro di *quale*
/// documento ha aperto *chi* sarebbe sorveglianza interna alla famiglia, per di
/// più consultabile dalla console admin. Le domande sono aggregate: non serve.
/// `daysSinceUpload` è a bucket proprio perché il valore esatto è quasi un
/// identificatore del documento.
///
/// **Costo.** Le letture sono l'evento più frequente dell'app: una scrittura
/// Firestore ciascuna costerebbe più del valore che produce. Gli eventi si
/// accumulano in memoria e partono in un unico batch quando l'app va in
/// background.
actor KBAnalytics {

    static let shared = KBAnalytics()

    // Allineato a RETENTION_DAYS in functions/analytics.js.
    private static let retentionDays = 90

    /// Finestra di inattività oltre la quale un ritorno in foreground è una
    /// nuova sessione. Senza, ogni cambio di app conterebbe come apertura.
    private static let sessionGap: TimeInterval = 30 * 60

    /// Oltre questa soglia si scarica subito, per non perdere tutto se l'app
    /// viene terminata senza passare da background.
    private static let flushThreshold = 25

    private var buffer: [RetrievalKey: Int] = [:]
    private var lastSessionStart: Date?

    private init() {}

    // MARK: - API

    /// Registra una lettura intenzionale di un contenuto.
    ///
    /// Da chiamare quando l'utente **recupera** davvero qualcosa (apre il
    /// dettaglio, copia una password), non quando scorre una lista.
    ///
    /// - Parameters:
    ///   - feature: area del contenuto.
    ///   - uploaderUid: `createdBy` del contenuto. Serve solo a calcolare
    ///     `uploaderIsSelf`: non viene mai scritto.
    ///   - createdAt: data di caricamento, usata solo per il bucket.
    ///   - entryPoint: come ci è arrivato — distingue il recupero riuscito dal
    ///     brancolare tra le liste.
    func logRetrieval(
        feature: KBAnalyticsFeature,
        uploaderUid: String?,
        createdAt: Date?,
        entryPoint: KBAnalyticsEntryPoint
    ) {
        guard let uid = Self.currentUid() else { return }
        // `uploaderUid` nil o vuoto → si assume propria. Meglio sottostimare le
        // cross-member read che gonfiare la metrica su cui poggia la tesi.
        let isSelf = uploaderUid.flatMap { $0.isEmpty ? nil : $0 }.map { $0 == uid } ?? true
        logRetrieval(
            feature: feature,
            uploaderIsSelf: isSelf,
            createdAt: createdAt,
            entryPoint: entryPoint
        )
    }

    /// Variante per i contenuti che non hanno un "uploader" singolo — la posizione
    /// dei familiari, per esempio: guardare dov'è un altro membro è cross-member
    /// per definizione, e non c'è un `createdBy` da confrontare.
    func logRetrieval(
        feature: KBAnalyticsFeature,
        uploaderIsSelf: Bool,
        createdAt: Date?,
        entryPoint: KBAnalyticsEntryPoint
    ) {
        guard Self.currentUid() != nil else { return }

        let key = RetrievalKey(
            feature: feature,
            uploaderIsSelf: uploaderIsSelf,
            entryPoint: entryPoint,
            daysBucket: Self.bucket(for: createdAt)
        )
        buffer[key, default: 0] += 1

        if buffer.count >= Self.flushThreshold {
            Task { await self.flush() }
        }
    }

    /// Registra un'apertura dell'app. Non conta come utente attivo: serve solo
    /// come denominatore, per sapere quanti aprono senza fare nulla.
    func logSessionStart(entryPoint: KBAnalyticsEntryPoint) {
        let now = Date()
        if let last = lastSessionStart, now.timeIntervalSince(last) < Self.sessionGap {
            return
        }
        lastSessionStart = now

        guard let uid = Self.currentUid(), let familyId = Self.currentFamilyId() else { return }

        Task {
            await Self.write([
                Self.event(
                    name: "session_start",
                    uid: uid,
                    familyId: familyId,
                    feature: "app",
                    props: ["entryPoint": entryPoint.rawValue]
                )
            ])
        }
    }

    /// Registra un evento del motore di nudge.
    ///
    /// `campaignId` è l'id di una campagna del catalogo, non un dato
    /// dell'utente: dice *quale messaggio* è stato mostrato, non cosa quella
    /// persona ha o non ha in casa. Senza questi eventi i nudge si spingono al
    /// buio, e l'unico segnale di ritorno sarebbe la disattivazione dei
    /// permessi — che è irreversibile e arriva quando è troppo tardi.
    ///
    /// - Parameter name: `nudge_scheduled`, `nudge_opened` o `nudge_dismissed`.
    func logNudge(name: String, campaignId: String) {
        guard let uid = Self.currentUid(), let familyId = Self.currentFamilyId() else { return }
        Task {
            await Self.write([
                Self.event(
                    name: name,
                    uid: uid,
                    familyId: familyId,
                    feature: "nudge",
                    props: ["campaignId": campaignId]
                )
            ])
        }
    }

    /// Scarica il buffer in un unico batch. Idempotente: svuota prima di
    /// scrivere, così un fallimento non duplica gli eventi al flush successivo.
    func flush() async {
        guard !buffer.isEmpty else { return }
        guard let uid = Self.currentUid(), let familyId = Self.currentFamilyId() else {
            buffer.removeAll()
            return
        }

        let pending = buffer
        buffer.removeAll()

        let events = pending.map { key, count in
            Self.event(
                name: "content_retrieved",
                uid: uid,
                familyId: familyId,
                feature: key.feature.rawValue,
                props: [
                    "uploaderIsSelf": key.uploaderIsSelf,
                    "entryPoint": key.entryPoint.rawValue,
                    "daysSinceUpload": key.daysBucket.rawValue,
                    "count": count
                ]
            )
        }
        await Self.write(events)
    }

    // MARK: - Scrittura

    private static func event(
        name: String,
        uid: String,
        familyId: String,
        feature: String,
        props: [String: Any]
    ) -> [String: Any] {
        // Le chiavi devono restare allineate alla whitelist in firestore.rules:
        // una chiave in più fa fallire la create.
        [
            "name": name,
            "uid": uid,
            "familyId": familyId,
            "feature": feature,
            "ts": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: Calendar.current.date(
                byAdding: .day, value: retentionDays, to: Date()) ?? Date()),
            "props": props
        ]
    }

    private static func write(_ events: [[String: Any]]) async {
        guard !events.isEmpty else { return }
        let db = Firestore.firestore()
        let batch = db.batch()
        for e in events {
            batch.setData(e, forDocument: db.collection("analyticsEvents").document())
        }
        do {
            try await batch.commit()
            await log("[KBAnalytics] flush ok events=\(events.count)")
        } catch {
            // L'analytics non deve mai disturbare l'utente né propagare errori:
            // gli eventi persi sono un costo accettabile.
            await log("[KBAnalytics] flush failed: \(String(describing: error))")
        }
    }

    /// `KBLog.app` è isolato al main actor: va raggiunto da lì.
    @MainActor
    private static func log(_ message: String) {
        KBLog.app.kbDebug(message)
    }

    // MARK: - Contesto

    private static func currentUid() -> String? {
        Auth.auth().currentUser?.uid
    }

    /// Stessa fonte usata da AIService: l'App Group.
    private static func currentFamilyId() -> String? {
        let id = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
            .string(forKey: "activeFamilyId") ?? ""
        return id.isEmpty ? nil : id
    }

    private static func bucket(for date: Date?) -> KBAnalyticsAgeBucket {
        guard let date else { return .unknown }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case ..<1:   return .today
        case 1...7:  return .week
        case 8...30: return .month
        case 31...180: return .halfYear
        default:     return .older
        }
    }

    private struct RetrievalKey: Hashable {
        let feature: KBAnalyticsFeature
        let uploaderIsSelf: Bool
        let entryPoint: KBAnalyticsEntryPoint
        let daysBucket: KBAnalyticsAgeBucket
    }
}

// MARK: - Tassonomia

/// Allineata a `TRACKED` in functions/analytics.js.
enum KBAnalyticsFeature: String {
    case documents, wallet, passwords, health, travel, vehicles, pets
    case note, expenses, calendar, photoVideo, homeItems, todo, grocery
    case chat, familyLocation
}

/// Come l'utente è arrivato al contenuto. Distingue "a portata di click" dal
/// cercare: è la proprietà che dice se la promessa del prodotto è mantenuta.
enum KBAnalyticsEntryPoint: String {
    case search, widget, home, list, notification, deepLink
    case icon, dynamicIsland, shareExt
}

/// Bucket, mai il valore esatto: `daysSinceUpload` preciso è quasi un
/// identificatore del documento.
enum KBAnalyticsAgeBucket: String {
    case today = "0"
    case week = "1-7"
    case month = "8-30"
    case halfYear = "31-180"
    case older = "180+"
    case unknown = "unknown"
}
