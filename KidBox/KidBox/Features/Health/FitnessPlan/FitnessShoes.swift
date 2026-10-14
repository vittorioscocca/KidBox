//
//  FitnessShoes.swift
//  KidBox
//
//  Scarpe da corsa del Piano Fitness: marca, data d'acquisto, km massimi e foto.
//  I km percorsi si ricavano dalle corse chiuse nel piano (sedute fatte e
//  allenamenti letti da Apple Salute) e si scalano dai km massimi.
//
//  Perché un registro e non un ricalcolo dal piano: il piano dura un mese e la
//  rigenerazione lo sostituisce (di sedute restano solo i consuntivi), quindi
//  una scarpa che dura 700 km perderebbe la storia a ogni nuovo piano. Ogni
//  scarpa si porta dietro `runs`: id della corsa → metri. L'id è quello della
//  seduta o dell'allenamento Salute, così riconciliare due volte non conta due
//  volte. Parity con `FitnessShoes.kt` su Android.
//
//  Percorso Firestore: users/{uid}/fitnessShoes/{shoeId} (privato per-utente).
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Modello

struct FitnessShoe: Codable, Equatable, Identifiable {
    var id: String
    /// Profilo del piano a cui appartengono le corse (stesso `childId` del piano).
    var childId: String
    var brand: String
    /// Modello o soprannome, facoltativo ("Pegasus 41").
    var model: String
    var purchaseDate: Date
    var maxKm: Double
    /// JPEG ridotto (lato lungo ≤ 480 px): viaggia dentro il documento Firestore.
    var photo: Data?
    /// Da questo momento la scarpa non riceve più corse.
    var retiredAt: Date?
    var isDeleted: Bool
    var updatedAt: Date
    /// id della corsa → metri.
    var runs: [String: Double]
    /// Correzione a mano, in km, che si somma alle corse (può essere negativa):
    /// per le scarpe già usate prima di averle inserite o per un conteggio
    /// sbagliato. Opzionale: le scarpe salvate prima di questo campo restano
    /// leggibili.
    var manualKm: Double?

    init(
        id: String = UUID().uuidString,
        childId: String,
        brand: String,
        model: String = "",
        purchaseDate: Date,
        maxKm: Double,
        photo: Data? = nil,
        retiredAt: Date? = nil,
        isDeleted: Bool = false,
        updatedAt: Date = Date(),
        runs: [String: Double] = [:],
        manualKm: Double? = nil
    ) {
        self.id = id
        self.childId = childId
        self.brand = brand
        self.model = model
        self.purchaseDate = purchaseDate
        self.maxKm = maxKm
        self.photo = photo
        self.retiredAt = retiredAt
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.runs = runs
        self.manualKm = manualKm
    }

    var displayName: String {
        let name = [brand, model].map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? brand : name
    }

    /// Km delle sole corse registrate.
    var runsKm: Double { runs.values.reduce(0, +) / 1000 }
    var usedKm: Double { max(0, runsKm + (manualKm ?? 0)) }
    var remainingKm: Double { max(0, maxKm - usedKm) }
    var progress: Double { maxKm > 0 ? min(1, usedKm / maxKm) : 0 }
    var isWornOut: Bool { maxKm > 0 && usedKm >= maxKm }
    var isRetired: Bool { retiredAt != nil }
}

// MARK: - Attribuzione delle corse

enum FitnessShoeLedger {

    /// Una corsa trovata nel piano.
    struct Run: Equatable {
        let id: String
        let date: Date
        let meters: Double
    }

    /// Le corse con distanza del piano: sedute fatte e allenamenti Salute non
    /// abbinati. Un allenamento già abbinato a una seduta sta nella seduta
    /// (`matchedWorkoutId`) e non compare fra i `loggedWorkouts`.
    static func runs(in plan: FitnessPlanDocument) -> [Run] {
        var result: [Run] = []
        for session in plan.allSessions where session.status == .done {
            guard let meters = session.actualDistanceMeters, meters >= 10 else { continue }
            let symbol: String
            if let actual = session.actualActivityTitle, !actual.isEmpty {
                symbol = FitnessActivityIcon.symbol(workoutTitle: actual)
            } else {
                symbol = FitnessActivityIcon.symbol(activityType: session.activityType, title: session.title)
            }
            guard symbol == "figure.run" else { continue }
            // Con l'allenamento Salute l'id è quello, stabile anche se la
            // seduta viene rigenerata o spostata.
            result.append(Run(
                id: session.matchedWorkoutId ?? session.id,
                date: session.completedAt ?? session.date,
                meters: meters
            ))
        }
        for workout in plan.logged {
            guard let meters = workout.distanceMeters, meters >= 10,
                  FitnessActivityIcon.symbol(workoutTitle: workout.title) == "figure.run"
            else { continue }
            result.append(Run(id: workout.id, date: workout.date, meters: meters))
        }
        return result
    }

    /// La scarpa che riceve una corsa: la più recente fra quelle già comprate
    /// e non ancora ritirate quel giorno.
    static func owner(of run: Run, in shoes: [FitnessShoe]) -> FitnessShoe? {
        let cal = Calendar.current
        let day = cal.startOfDay(for: run.date)
        return shoes
            .filter { shoe in
                guard !shoe.isDeleted, cal.startOfDay(for: shoe.purchaseDate) <= day else { return false }
                if let retired = shoe.retiredAt, run.date >= retired { return false }
                return true
            }
            .max { $0.purchaseDate < $1.purchaseDate }
    }

    /// Aggiunge al registro le corse nuove e aggiorna i metri di quelle già
    /// viste. Non toglie mai niente: una corsa sparita dal piano resta alla
    /// scarpa che l'ha consumata. Restituisce le scarpe cambiate.
    static func reconcile(shoes: [FitnessShoe], plan: FitnessPlanDocument, now: Date = Date()) -> [FitnessShoe] {
        var updated = shoes
        var changed = Set<String>()
        for run in runs(in: plan) {
            if let index = updated.firstIndex(where: { $0.runs[run.id] != nil }) {
                if updated[index].runs[run.id] != run.meters {
                    updated[index].runs[run.id] = run.meters
                    changed.insert(updated[index].id)
                }
                continue
            }
            guard let target = owner(of: run, in: updated),
                  let index = updated.firstIndex(where: { $0.id == target.id })
            else { continue }
            updated[index].runs[run.id] = run.meters
            changed.insert(updated[index].id)
        }
        return updated.filter { changed.contains($0.id) }.map { shoe in
            var copy = shoe
            copy.updatedAt = now
            return copy
        }
    }

    /// Unione fra copia locale e remota: vince la più recente per i campi, e le
    /// corse si sommano per id (una corsa registrata su un device non si perde).
    static func merge(local: FitnessShoe, remote: FitnessShoe) -> FitnessShoe {
        var winner = local.updatedAt >= remote.updatedAt ? local : remote
        let loser = local.updatedAt >= remote.updatedAt ? remote : local
        for (id, meters) in loser.runs where winner.runs[id] == nil {
            winner.runs[id] = meters
        }
        return winner
    }
}

// MARK: - Archivio locale

enum FitnessShoeStore {

    private static func fileURL(childId: String) -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("fitness_shoes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shoes_\(childId).json")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Tutte le scarpe del profilo, comprese quelle eliminate (servono a
    /// propagare l'eliminazione agli altri device).
    static func loadAll(childId: String) -> [FitnessShoe] {
        guard let url = fileURL(childId: childId),
              let data = try? Data(contentsOf: url),
              let shoes = try? decoder.decode([FitnessShoe].self, from: data)
        else { return [] }
        return shoes
    }

    /// Scarpe visibili: più recenti per prime.
    static func load(childId: String) -> [FitnessShoe] {
        loadAll(childId: childId)
            .filter { !$0.isDeleted }
            .sorted { $0.purchaseDate > $1.purchaseDate }
    }

    private static func saveAll(_ shoes: [FitnessShoe], childId: String) {
        guard let url = fileURL(childId: childId), let data = try? encoder.encode(shoes) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Crea o modifica una scarpa e la manda a Firestore.
    static func upsert(_ shoe: FitnessShoe) {
        var shoe = shoe
        shoe.updatedAt = Date()
        var all = loadAll(childId: shoe.childId)
        if let index = all.firstIndex(where: { $0.id == shoe.id }) {
            all[index] = shoe
        } else {
            all.append(shoe)
        }
        saveAll(all, childId: shoe.childId)
        Task { await FitnessShoeRemoteStore.upsert(shoe) }
    }

    static func delete(_ shoe: FitnessShoe) {
        var gone = shoe
        gone.isDeleted = true
        gone.photo = nil
        upsert(gone)
    }

    /// Chiamata a ogni salvataggio del piano: porta in registro le corse nuove.
    /// Non fa nulla (né I/O di rete) se l'utente non ha scarpe.
    static func reconcile(plan: FitnessPlanDocument, childId: String) {
        var all = loadAll(childId: childId)
        guard all.contains(where: { !$0.isDeleted }) else { return }
        let changed = FitnessShoeLedger.reconcile(shoes: all, plan: plan)
        guard !changed.isEmpty else { return }
        for shoe in changed {
            if let index = all.firstIndex(where: { $0.id == shoe.id }) { all[index] = shoe }
        }
        saveAll(all, childId: childId)
        Task { for shoe in changed { await FitnessShoeRemoteStore.upsert(shoe) } }
        KBLog.persistence.kbInfo("FitnessShoes reconciled childId=\(childId) shoes=\(changed.count)")
    }

    /// Allinea con Firestore all'apertura delle impostazioni: unisce le due
    /// copie e rimanda su ciò che il server non ha o ha più vecchio.
    static func pull(childId: String) async -> [FitnessShoe] {
        let local = loadAll(childId: childId)
        guard let remote = await FitnessShoeRemoteStore.fetchAll(childId: childId) else {
            return load(childId: childId)
        }
        var merged: [String: FitnessShoe] = [:]
        var toPush: [FitnessShoe] = []
        for shoe in local { merged[shoe.id] = shoe }
        for shoe in remote {
            if let mine = merged[shoe.id] {
                let both = FitnessShoeLedger.merge(local: mine, remote: shoe)
                merged[shoe.id] = both
                if both != shoe { toPush.append(both) }
            } else {
                merged[shoe.id] = shoe
            }
        }
        let remoteIds = Set(remote.map(\.id))
        toPush += local.filter { !remoteIds.contains($0.id) }
        saveAll(Array(merged.values), childId: childId)
        for shoe in toPush { await FitnessShoeRemoteStore.upsert(shoe) }
        return load(childId: childId)
    }
}

// MARK: - Firestore

enum FitnessShoeRemoteStore {

    private static var collection: CollectionReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return Firestore.firestore().collection("users").document(uid).collection("fitnessShoes")
    }

    static func upsert(_ shoe: FitnessShoe) async {
        guard let collection else { return }
        var data: [String: Any] = [
            "childId": shoe.childId,
            "brand": shoe.brand,
            "model": shoe.model,
            "purchaseDate": Timestamp(date: shoe.purchaseDate),
            "maxKm": shoe.maxKm,
            "isDeleted": shoe.isDeleted,
            "updatedAt": Timestamp(date: shoe.updatedAt),
            "runs": shoe.runs,
            "manualKm": shoe.manualKm ?? 0,
            "photoBase64": shoe.photo?.base64EncodedString() ?? "",
        ]
        data["retiredAt"] = shoe.retiredAt.map { Timestamp(date: $0) } ?? NSNull()
        do {
            // Niente merge: `runs` è una mappa e una corsa tolta non deve restare.
            try await collection.document(shoe.id).setData(data)
        } catch {
            KBLog.sync.kbError("FitnessShoe remote upsert failed: \(error.localizedDescription)")
        }
    }

    /// `nil` se la lettura fallisce (si resta sulla copia locale).
    static func fetchAll(childId: String) async -> [FitnessShoe]? {
        guard let collection else { return nil }
        do {
            let snap = try await collection.whereField("childId", isEqualTo: childId).getDocuments()
            return snap.documents.compactMap { doc in
                let data = doc.data()
                guard let brand = data["brand"] as? String,
                      let purchase = (data["purchaseDate"] as? Timestamp)?.dateValue(),
                      let maxKm = (data["maxKm"] as? NSNumber)?.doubleValue
                else { return nil }
                let rawRuns = data["runs"] as? [String: Any] ?? [:]
                let runs = rawRuns.compactMapValues { ($0 as? NSNumber)?.doubleValue }
                let photo64 = data["photoBase64"] as? String ?? ""
                return FitnessShoe(
                    id: doc.documentID,
                    childId: childId,
                    brand: brand,
                    model: data["model"] as? String ?? "",
                    purchaseDate: purchase,
                    maxKm: maxKm,
                    photo: photo64.isEmpty ? nil : Data(base64Encoded: photo64),
                    retiredAt: (data["retiredAt"] as? Timestamp)?.dateValue(),
                    isDeleted: data["isDeleted"] as? Bool ?? false,
                    updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast,
                    runs: runs,
                    manualKm: (data["manualKm"] as? NSNumber)?.doubleValue
                )
            }
        } catch {
            KBLog.sync.kbError("FitnessShoe remote fetch failed: \(error.localizedDescription)")
            return nil
        }
    }
}
