//
//  KBWidgetSnapshot.swift
//  KidBox
//
//  Istantanea dei dati per i widget della Home. File condiviso tra app e
//  estensione (KidBoxControlsExtension): contiene solo Foundation.
//
//  Perché un file e non SwiftData: lo store dell'app è nell'App Group ma ha
//  oltre cento modelli e CloudKit; aprirlo da un'estensione è fragile e pesa.
//  Il piano Fitness poi vive in UserDefaults.standard, che l'estensione non
//  vede. L'app scrive qui un JSON piccolo, il widget lo legge soltanto.
//
//  Solo la famiglia attiva: l'app sincronizza solo quella.
//

import Foundation

struct KBWidgetSnapshot: Codable, Equatable {

    var version: Int = 1
    var familyId: String
    var familyName: String
    var updatedAt: Date
    /// Piano Fitness: solo Pro/Max (prova compresa).
    var fitnessUnlocked: Bool

    var events: [Event] = []
    var todoLists: [TodoList] = []
    var grocery: [GroceryItem] = []
    var profiles: [Profile] = []
    var doses: [Dose] = []
    var fitness: [FitnessProfile] = []

    // MARK: Calendario

    struct Event: Codable, Equatable, Identifiable {
        var id: String          // occorrenza: «eventId|indice»
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var colorHex: String
    }

    // MARK: To-do

    struct TodoList: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        /// Quanti da fare in tutto (le righe sotto sono solo le prime).
        var openCount: Int
        var items: [TodoItem]
    }

    struct TodoItem: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var due: Date?
        var hasTime: Bool
        var isUrgent: Bool
    }

    // MARK: Spesa

    struct GroceryItem: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var category: String?
        var quantity: Int?
    }

    // MARK: Cure e Fitness

    struct Profile: Codable, Equatable, Identifiable {
        var id: String
        var name: String
    }

    /// Una dose di oggi o di domani.
    struct Dose: Codable, Equatable, Identifiable {
        var id: String          // «treatmentId|giorno|slot»
        var childId: String
        var drugName: String
        var dosage: String
        var time: Date
        var taken: Bool
    }

    struct FitnessProfile: Codable, Equatable, Identifiable {
        var id: String          // childId
        var sessions: [FitnessSession]
    }

    struct FitnessSession: Codable, Equatable, Identifiable {
        var id: String
        var date: Date          // mezzanotte locale
        var title: String
        var activityType: String
        var minutes: Int
        var isDone: Bool
        var isSkipped: Bool
    }
}

// MARK: - Disco

enum KBWidgetStore {

    static let appGroupId = "group.it.vittorioscocca.kidbox"
    private static let fileName = "widget-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(fileName)
    }

    static func read() -> KBWidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(KBWidgetSnapshot.self, from: data)
    }

    /// `true` se il contenuto è cambiato (e quindi vale la pena ricaricare i widget).
    @discardableResult
    static func write(_ snapshot: KBWidgetSnapshot) -> Bool {
        guard let url = fileURL else { return false }
        if var old = read() {
            old.updatedAt = snapshot.updatedAt
            if old == snapshot { return false }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Al logout: i widget non devono mostrare i dati di chi è uscito.
    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
