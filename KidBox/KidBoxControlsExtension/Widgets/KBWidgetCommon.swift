//
//  KBWidgetCommon.swift
//  KidBoxControlsExtension
//
//  Pezzi comuni dei widget della Home: entità per la scelta di lista e
//  membro, intestazione, stato vuoto, colori.
//

import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Colori

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static let kbCalendar = Color(hex: "E74C3C")
    static let kbTodo     = Color(hex: "3478F6")
    static let kbGrocery  = Color(hex: "2FA84F")
    static let kbCare     = Color(hex: "E8507A")
    static let kbFitness  = Color(hex: "F5821F")
}

// MARK: - Intestazione (nome a sinistra, numero a destra, come Promemoria)

struct KBWidgetHeader: View {
    let title: String
    let color: Color
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if let count {
                Text("\(count)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
    }
}

/// Messaggio centrato: dati assenti, sezione vuota, funzione bloccata.
struct KBWidgetMessage: View {
    let systemImage: String
    let text: LocalizedStringKey
    var color: Color = .secondary

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)
            Text(text)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Nessuna istantanea: app mai aperta o utente uscito.
struct KBWidgetSignedOut: View {
    var body: some View {
        KBWidgetMessage(systemImage: "person.crop.circle.badge.questionmark",
                        text: "Apri KidBox per iniziare")
    }
}

// MARK: - Entità: lista to-do

struct TodoListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Lista"
    static let defaultQuery = TodoListQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    /// L'id vuoto dei to-do senza lista non è un identificatore valido.
    static let noListId = "none"

    init(list: KBWidgetSnapshot.TodoList) {
        id = list.id.isEmpty ? Self.noListId : list.id
        name = list.name.isEmpty ? String(localized: "Senza lista") : list.name
    }
}

struct TodoListQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TodoListEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [TodoListEntity] {
        (KBWidgetStore.read()?.todoLists ?? []).map(TodoListEntity.init(list:))
    }
}

// MARK: - Entità: membro (cure e fitness)

struct ProfileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Membro"
    static let defaultQuery = ProfileQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ProfileQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProfileEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [ProfileEntity] {
        (KBWidgetStore.read()?.profiles ?? []).map { ProfileEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Intent di configurazione

struct TodoWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "To-do"
    static let description = IntentDescription("Scegli la lista da mostrare. Senza scelta vedi tutti i to-do.")

    @Parameter(title: "Lista")
    var list: TodoListEntity?
}

struct CareWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Cure"
    static let description = IntentDescription("Scegli di chi mostrare le cure. Senza scelta vedi tutta la famiglia.")

    @Parameter(title: "Membro")
    var member: ProfileEntity?
}

struct FitnessWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Piano Fitness"
    static let description = IntentDescription("Scegli di chi mostrare il piano. Senza scelta vedi il primo piano trovato.")

    @Parameter(title: "Membro")
    var member: ProfileEntity?
}

// MARK: - Voce di timeline

struct KBWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: KBWidgetSnapshot?
}

/// Mezzanotte successiva a `date`.
func kbNextMidnight(after date: Date) -> Date {
    let cal = Calendar.current
    return cal.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0),
                        matchingPolicy: .nextTime) ?? date.addingTimeInterval(86_400)
}
