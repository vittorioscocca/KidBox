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

// MARK: - Intent di configurazione (cinque pagine in galleria, «Modifica widget» sceglie cosa mostrare)

enum KBWidgetContent: String, AppEnum, CaseIterable {
    case calendar, todo, grocery, care, fitness

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Contenuto"
    static let caseDisplayRepresentations: [KBWidgetContent: DisplayRepresentation] = [
        .calendar: DisplayRepresentation(title: "Calendario", image: .init(systemName: "calendar")),
        .todo:     DisplayRepresentation(title: "To-do", image: .init(systemName: "checklist")),
        .grocery:  DisplayRepresentation(title: "Spesa", image: .init(systemName: "cart")),
        .care:     DisplayRepresentation(title: "Cure", image: .init(systemName: "pills")),
        .fitness:  DisplayRepresentation(title: "Piano Fitness", image: .init(systemName: "figure.run")),
    ]
}

/// Cosa serve al provider da qualunque pagina della galleria. Ogni pagina ha il
/// suo intent solo perché il valore predefinito di «Mostra» è statico: per il
/// resto sono identici, e da «Modifica widget» ognuna può mostrare tutto.
protocol KBContentIntent: WidgetConfigurationIntent {
    var content: KBWidgetContent { get }
    var list: TodoListEntity? { get }
    var member: ProfileEntity? { get }
}

/// Prima pagina (e widget nato dall'icona): parte dal Calendario. Nome e kind invariati, o i widget già sulla Home perdono il legame.
struct KidBoxWidgetIntent: KBContentIntent {
    static let title: LocalizedStringResource = "KidBox"
    static let description = IntentDescription("Scegli cosa mostrare: calendario, to-do, spesa, cure o piano fitness.")

    @Parameter(title: "Mostra", default: .calendar)
    var content: KBWidgetContent

    @Parameter(title: "Lista")
    var list: TodoListEntity?

    @Parameter(title: "Membro")
    var member: ProfileEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$content, .equalTo, KBWidgetContent.todo) {
            Summary("Mostra \(\.$content)") { \.$list }
        } otherwise: {
            When(\.$content, .equalTo, KBWidgetContent.care) {
                Summary("Mostra \(\.$content)") { \.$member }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.fitness) {
                    Summary("Mostra \(\.$content)") { \.$member }
                } otherwise: {
                    Summary("Mostra \(\.$content)")
                }
            }
        }
    }
}

/// Pagina To-do.
struct KidBoxTodoWidgetIntent: KBContentIntent {
    static let title: LocalizedStringResource = "KidBox"
    static let description = IntentDescription("Scegli cosa mostrare: calendario, to-do, spesa, cure o piano fitness.")

    @Parameter(title: "Mostra", default: .todo)
    var content: KBWidgetContent

    @Parameter(title: "Lista")
    var list: TodoListEntity?

    @Parameter(title: "Membro")
    var member: ProfileEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$content, .equalTo, KBWidgetContent.todo) {
            Summary("Mostra \(\.$content)") { \.$list }
        } otherwise: {
            When(\.$content, .equalTo, KBWidgetContent.care) {
                Summary("Mostra \(\.$content)") { \.$member }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.fitness) {
                    Summary("Mostra \(\.$content)") { \.$member }
                } otherwise: {
                    Summary("Mostra \(\.$content)")
                }
            }
        }
    }
}

/// Pagina Spesa.
struct KidBoxGroceryWidgetIntent: KBContentIntent {
    static let title: LocalizedStringResource = "KidBox"
    static let description = IntentDescription("Scegli cosa mostrare: calendario, to-do, spesa, cure o piano fitness.")

    @Parameter(title: "Mostra", default: .grocery)
    var content: KBWidgetContent

    @Parameter(title: "Lista")
    var list: TodoListEntity?

    @Parameter(title: "Membro")
    var member: ProfileEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$content, .equalTo, KBWidgetContent.todo) {
            Summary("Mostra \(\.$content)") { \.$list }
        } otherwise: {
            When(\.$content, .equalTo, KBWidgetContent.care) {
                Summary("Mostra \(\.$content)") { \.$member }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.fitness) {
                    Summary("Mostra \(\.$content)") { \.$member }
                } otherwise: {
                    Summary("Mostra \(\.$content)")
                }
            }
        }
    }
}

/// Pagina Cure.
struct KidBoxCareWidgetIntent: KBContentIntent {
    static let title: LocalizedStringResource = "KidBox"
    static let description = IntentDescription("Scegli cosa mostrare: calendario, to-do, spesa, cure o piano fitness.")

    @Parameter(title: "Mostra", default: .care)
    var content: KBWidgetContent

    @Parameter(title: "Lista")
    var list: TodoListEntity?

    @Parameter(title: "Membro")
    var member: ProfileEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$content, .equalTo, KBWidgetContent.todo) {
            Summary("Mostra \(\.$content)") { \.$list }
        } otherwise: {
            When(\.$content, .equalTo, KBWidgetContent.care) {
                Summary("Mostra \(\.$content)") { \.$member }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.fitness) {
                    Summary("Mostra \(\.$content)") { \.$member }
                } otherwise: {
                    Summary("Mostra \(\.$content)")
                }
            }
        }
    }
}

/// Pagina Piano Fitness.
struct KidBoxFitnessWidgetIntent: KBContentIntent {
    static let title: LocalizedStringResource = "KidBox"
    static let description = IntentDescription("Scegli cosa mostrare: calendario, to-do, spesa, cure o piano fitness.")

    @Parameter(title: "Mostra", default: .fitness)
    var content: KBWidgetContent

    @Parameter(title: "Lista")
    var list: TodoListEntity?

    @Parameter(title: "Membro")
    var member: ProfileEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$content, .equalTo, KBWidgetContent.todo) {
            Summary("Mostra \(\.$content)") { \.$list }
        } otherwise: {
            When(\.$content, .equalTo, KBWidgetContent.care) {
                Summary("Mostra \(\.$content)") { \.$member }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.fitness) {
                    Summary("Mostra \(\.$content)") { \.$member }
                } otherwise: {
                    Summary("Mostra \(\.$content)")
                }
            }
        }
    }
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
