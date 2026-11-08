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
    /// Opzionali: le istantanee scritte prima del widget Foto devono restare leggibili.
    var photos: [Photo]? = nil
    var albums: [Album]? = nil

    // MARK: Foto

    /// Una foto con la sua miniatura già pronta in `KBWidgetPhotoFiles`.
    struct Photo: Codable, Equatable, Identifiable {
        var id: String
        var takenAt: Date
        var albumIds: [String]
    }

    struct Album: Codable, Equatable, Identifiable {
        var id: String
        var title: String
    }

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
        /// Segnata come saltata. Opzionale: le istantanee scritte prima
        /// del campo devono restare leggibili.
        var skipped: Bool? = nil

        /// Ancora da gestire: né presa né saltata.
        var isPending: Bool { !taken && skipped != true }
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
        KBWidgetPhotoFiles.clear()
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Miniature delle foto

/// Le foto della famiglia sono cifrate: il widget non può né scaricarle né
/// leggerle. L'app ne scrive qui una copia piccola (JPEG)
/// per le sole foto che il widget può mostrare (lato lungo ~1000 px: basta anche al widget largo); il resto non esce dall'app.
enum KBWidgetPhotoFiles {

    static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: KBWidgetStore.appGroupId)?
            .appendingPathComponent("widget-photos", isDirectory: true)
    }

    /// Suffisso della misura: le prime miniature (520 px, solo quadrato) si
    /// chiamavano «id.jpg» e vengono tolte e rifatte più grandi per il largo.
    static func fileName(for photoId: String) -> String { "\(photoId)_1000.jpg" }

    static func url(for photoId: String) -> URL? {
        directory?.appendingPathComponent(fileName(for: photoId))
    }

    static func clear() {
        guard let dir = directory else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Chiave che il widget aggiorna quando gli serve una foto: l'app prepara le
    /// miniature solo se c'è davvero un widget Foto, niente download a vuoto.
    static let requestedKey = "kidbox.widget.photosRequestedAt"

    static func markRequested() {
        UserDefaults(suiteName: KBWidgetStore.appGroupId)?.set(Date(), forKey: requestedKey)
    }

    static var recentlyRequested: Bool {
        guard let d = UserDefaults(suiteName: KBWidgetStore.appGroupId)?.object(forKey: requestedKey) as? Date
        else { return false }
        return Date().timeIntervalSince(d) < 14 * 86_400
    }
}

// MARK: - «Presa» / «Saltata» dal widget Cure

/// Dosi gestite dal widget, in attesa che l'app le scriva davvero.
///
/// Il pulsante del widget gira nell'estensione (a meno che il sistema non lo
/// esegua nell'app): lì non c'è SwiftData né la sincronizzazione. L'estensione
/// aggiorna subito l'istantanea, così il widget passa alla dose dopo, e mette
/// la voce in coda; l'app la svuota appena può (`KBWidgetSync.drainPendingDoses`).
enum KBWidgetDoseQueue {

    private static let key = "kidbox.widget.pendingDoses"
    private static let takenPrefix = "taken:"
    private static let skippedPrefix = "skipped:"

    /// Impostato dall'app: se l'intent gira nel suo processo, svuota subito.
    nonisolated(unsafe) static var drainInApp: (@Sendable () async -> Void)?

    private static var defaults: UserDefaults? { UserDefaults(suiteName: KBWidgetStore.appGroupId) }

    private static var raw: [String] {
        get { defaults?.stringArray(forKey: key) ?? [] }
        set { defaults?.set(newValue, forKey: key) }
    }

    /// Voci in coda: (id della dose, presa sì/no).
    static func pending() -> [(doseId: String, taken: Bool)] {
        raw.compactMap { item in
            if item.hasPrefix(skippedPrefix) { return (String(item.dropFirst(skippedPrefix.count)), false) }
            if item.hasPrefix(takenPrefix) { return (String(item.dropFirst(takenPrefix.count)), true) }
            return (item, true)   // formato precedente: solo «presa»
        }
    }

    private static func id(of item: String) -> String {
        for prefix in [takenPrefix, skippedPrefix] where item.hasPrefix(prefix) {
            return String(item.dropFirst(prefix.count))
        }
        return item
    }

    static func enqueue(_ doseId: String, taken: Bool) {
        var list = raw.filter { id(of: $0) != doseId }
        list.append((taken ? takenPrefix : skippedPrefix) + doseId)
        raw = list
    }

    static func remove(_ doseId: String) {
        raw = raw.filter { id(of: $0) != doseId }
    }

    /// Aggiorna l'istantanea senza aspettare l'app.
    static func markInSnapshot(_ doseId: String, taken: Bool) {
        guard var snap = KBWidgetStore.read(),
              let i = snap.doses.firstIndex(where: { $0.id == doseId }) else { return }
        snap.doses[i].taken = taken
        snap.doses[i].skipped = !taken
        KBWidgetStore.write(snap)
    }
}

// MARK: - «Fatto» dal widget To-do e «Comprato» dal widget Spesa

/// Coda di id toccati nel widget e non ancora scritti dall'app. Stesso schema
/// delle dosi: l'estensione aggiorna subito l'istantanea (la riga sparisce e il
/// numero scala) e mette l'id in coda; l'app lo scrive e lo sincronizza.
struct KBWidgetIdQueue {
    let key: String
    private var defaults: UserDefaults? { UserDefaults(suiteName: KBWidgetStore.appGroupId) }

    func pending() -> [String] { defaults?.stringArray(forKey: key) ?? [] }

    func enqueue(_ id: String) {
        var list = pending()
        if !list.contains(id) { list.append(id) }
        defaults?.set(list, forKey: key)
    }

    func remove(_ id: String) {
        defaults?.set(pending().filter { $0 != id }, forKey: key)
    }
}

/// To-do chiusi dal widget; l'app li chiude con `TodoReminderDoneAction`,
/// che non riapre un to-do già chiuso da un altro membro.
enum KBWidgetTodoQueue {
    static let queue = KBWidgetIdQueue(key: "kidbox.widget.pendingTodosDone")

    static func markDoneInSnapshot(_ todoId: String) {
        guard var snap = KBWidgetStore.read() else { return }
        for i in snap.todoLists.indices {
            let before = snap.todoLists[i].items.count
            snap.todoLists[i].items.removeAll { $0.id == todoId }
            if snap.todoLists[i].items.count < before {
                snap.todoLists[i].openCount = max(0, snap.todoLists[i].openCount - 1)
            }
        }
        KBWidgetStore.write(snap)
    }
}

/// Voci della spesa segnate come comprate dal widget.
enum KBWidgetGroceryQueue {
    static let queue = KBWidgetIdQueue(key: "kidbox.widget.pendingGroceryBought")

    static func markBoughtInSnapshot(_ itemId: String) {
        guard var snap = KBWidgetStore.read() else { return }
        snap.grocery.removeAll { $0.id == itemId }
        KBWidgetStore.write(snap)
    }
}
