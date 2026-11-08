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
    static let kbPhotos   = Color(hex: "AF52DE")
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
                    .font(.system(size: 24, weight: .bold, design: .rounded))
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

// MARK: - Entità: album delle foto

struct PhotoAlbumEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Album"
    static let defaultQuery = PhotoAlbumQuery()

    var id: String
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct PhotoAlbumQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PhotoAlbumEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [PhotoAlbumEntity] {
        (KBWidgetStore.read()?.albums ?? []).map { PhotoAlbumEntity(id: $0.id, title: $0.title) }
    }
}

// MARK: - Scorciatoie del formato grande

/// Le sezioni di KidBox che il formato grande offre come scorciatoie (al
/// massimo sei). Il valore è quello di `SidebarSection` nell'app: il link
/// `kidbox://widget/<valore>` apre la sezione per la stessa strada del widget.
enum KBShortcutSection: String, AppEnum, CaseIterable {
    case dashboard, calendar, todo, shopping, notes, photos, health, chat,
         documents, expenses, wallet, passwords, location, pets, homeItems,
         vehicles, travel, assistant, news

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sezione"
    static let caseDisplayRepresentations: [KBShortcutSection: DisplayRepresentation] = [
        .dashboard: DisplayRepresentation(title: "Home", image: .init(systemName: "square.grid.2x2.fill")),
        .calendar:  DisplayRepresentation(title: "Calendario", image: .init(systemName: "calendar")),
        .todo:      DisplayRepresentation(title: "To-do", image: .init(systemName: "checklist")),
        .shopping:  DisplayRepresentation(title: "Spesa", image: .init(systemName: "cart.fill")),
        .notes:     DisplayRepresentation(title: "Note", image: .init(systemName: "note.text")),
        .photos:    DisplayRepresentation(title: "Foto", image: .init(systemName: "photo.stack.fill")),
        .health:    DisplayRepresentation(title: "Salute", image: .init(systemName: "heart.fill")),
        .chat:      DisplayRepresentation(title: "Chat", image: .init(systemName: "message.fill")),
        .documents: DisplayRepresentation(title: "Documenti", image: .init(systemName: "doc.text.fill")),
        .expenses:  DisplayRepresentation(title: "Spese", image: .init(systemName: "eurosign.circle.fill")),
        .wallet:    DisplayRepresentation(title: "Wallet", image: .init(systemName: "ticket.fill")),
        .passwords: DisplayRepresentation(title: "Password", image: .init(systemName: "key.fill")),
        .location:  DisplayRepresentation(title: "Posizione", image: .init(systemName: "location.fill")),
        .pets:      DisplayRepresentation(title: "Animali", image: .init(systemName: "pawprint.fill")),
        .homeItems: DisplayRepresentation(title: "Casa", image: .init(systemName: "house.fill")),
        .vehicles:  DisplayRepresentation(title: "Garage", image: .init(systemName: "car.fill")),
        .travel:    DisplayRepresentation(title: "Viaggi", image: .init(systemName: "suitcase.fill")),
        .assistant: DisplayRepresentation(title: "Assistente", image: .init(systemName: "sparkles")),
        .news:      DisplayRepresentation(title: "Notizie", image: .init(systemName: "newspaper.fill")),
    ]

    var label: LocalizedStringKey {
        switch self {
        case .dashboard: "Home"
        case .calendar:  "Calendario"
        case .todo:      "To-do"
        case .shopping:  "Spesa"
        case .notes:     "Note"
        case .photos:    "Foto"
        case .health:    "Salute"
        case .chat:      "Chat"
        case .documents: "Documenti"
        case .expenses:  "Spese"
        case .wallet:    "Wallet"
        case .passwords: "Password"
        case .location:  "Posizione"
        case .pets:      "Animali"
        case .homeItems: "Casa"
        case .vehicles:  "Garage"
        case .travel:    "Viaggi"
        case .assistant: "Assistente"
        case .news:      "Notizie"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .calendar:  "calendar"
        case .todo:      "checklist"
        case .shopping:  "cart.fill"
        case .notes:     "note.text"
        case .photos:    "photo.stack.fill"
        case .health:    "heart.fill"
        case .chat:      "message.fill"
        case .documents: "doc.text.fill"
        case .expenses:  "eurosign.circle.fill"
        case .wallet:    "ticket.fill"
        case .passwords: "key.fill"
        case .location:  "location.fill"
        case .pets:      "pawprint.fill"
        case .homeItems: "house.fill"
        case .vehicles:  "car.fill"
        case .travel:    "suitcase.fill"
        case .assistant: "sparkles"
        case .news:      "newspaper.fill"
        }
    }

    var tint: Color {
        switch self {
        case .dashboard: .orange
        case .calendar:  .kbCalendar
        case .todo:      .kbTodo
        case .shopping:  .kbGrocery
        case .notes:     .yellow
        case .photos:    .kbPhotos
        case .health:    .kbCare
        case .chat:      .green
        case .documents: .orange
        case .expenses:  .mint
        case .wallet:    .indigo
        case .passwords: .blue
        case .location:  .cyan
        case .pets:      .orange
        case .homeItems: .brown
        case .vehicles:  .gray
        case .travel:    .teal
        case .assistant: .purple
        case .news:      .orange
        }
    }

    /// La sezione che il contenuto in alto già mostra, da non ripetere.
    static func shown(by content: KBWidgetContent) -> KBShortcutSection {
        switch content {
        case .calendar: .calendar
        case .todo:     .todo
        case .grocery:  .shopping
        case .care, .fitness: .health
        case .photos:   .photos
        }
    }

    /// Senza scelta: sei sezioni d'uso quotidiano, tolta quella già in alto.
    static func resolved(_ chosen: [KBShortcutEntity]?, content: KBWidgetContent) -> [KBShortcutSection] {
        if let chosen, !chosen.isEmpty { return Array(chosen.map(\.section).prefix(6)) }
        let defaults: [KBShortcutSection] = [.calendar, .todo, .shopping, .photos, .health, .chat, .notes]
        return Array(defaults.filter { $0 != shown(by: content) }.prefix(6))
    }
}

/// La scelta multipla con un massimo per formato (`size:`) vale solo per le
/// entità, non per gli enum: ogni sezione è anche un'entità con l'id del valore.
struct KBShortcutEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sezione"
    static let defaultQuery = KBShortcutQuery()

    var id: String
    var section: KBShortcutSection { KBShortcutSection(rawValue: id) ?? .dashboard }

    var displayRepresentation: DisplayRepresentation {
        KBShortcutSection.caseDisplayRepresentations[section] ?? DisplayRepresentation(title: "\(id)")
    }
}

struct KBShortcutQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [KBShortcutEntity] {
        identifiers.filter { KBShortcutSection(rawValue: $0) != nil }.map(KBShortcutEntity.init(id:))
    }
    func suggestedEntities() async throws -> [KBShortcutEntity] {
        KBShortcutSection.allCases.map { KBShortcutEntity(id: $0.rawValue) }
    }
}

// MARK: - Intent di configurazione (cinque pagine in galleria, «Modifica widget» sceglie cosa mostrare)

enum KBWidgetContent: String, AppEnum, CaseIterable {
    case calendar, todo, grocery, care, fitness, photos

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Contenuto"
    static let caseDisplayRepresentations: [KBWidgetContent: DisplayRepresentation] = [
        .calendar: DisplayRepresentation(title: "Calendario", image: .init(systemName: "calendar")),
        .todo:     DisplayRepresentation(title: "To-do", image: .init(systemName: "checklist")),
        .grocery:  DisplayRepresentation(title: "Spesa", image: .init(systemName: "cart")),
        .care:     DisplayRepresentation(title: "Cure", image: .init(systemName: "pills")),
        .fitness:  DisplayRepresentation(title: "Piano Fitness", image: .init(systemName: "figure.run")),
        .photos:   DisplayRepresentation(title: "Foto", image: .init(systemName: "photo.on.rectangle")),
    ]
}

/// Cosa serve al provider da qualunque pagina della galleria. Ogni pagina ha il
/// suo intent solo perché il valore predefinito di «Mostra» è statico: per il
/// resto sono identici, e da «Modifica widget» ognuna può mostrare tutto.
protocol KBContentIntent: WidgetConfigurationIntent {
    var content: KBWidgetContent { get }
    var list: TodoListEntity? { get }
    var member: ProfileEntity? { get }
    var album: PhotoAlbumEntity? { get }
    var shortcuts: [KBShortcutEntity]? { get }
}

/// Prima pagina (e widget nato dall'icona): parte dal Calendario. Nome e kind invariati, o i widget già sulla Home perdono il legame.
struct KidBoxWidgetIntent: KBContentIntent {
    static let title: LocalizedStringResource = "KidBox"
    static let description = IntentDescription("Scegli cosa mostrare: calendario, to-do, spesa, cure, piano fitness o foto.")

    @Parameter(title: "Mostra", default: .calendar)
    var content: KBWidgetContent

    @Parameter(title: "Lista")
    var list: TodoListEntity?

    @Parameter(title: "Membro")
    var member: ProfileEntity?

    @Parameter(title: "Album")
    var album: PhotoAlbumEntity?

    /// Solo nel formato grande: le scorciatoie sotto il contenuto.
    @Parameter(title: "Scorciatoie", size: [.systemLarge: 6])
    var shortcuts: [KBShortcutEntity]?

    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemLarge) {
            When(\.$content, .equalTo, KBWidgetContent.todo) {
                Summary("Mostra \(\.$content)") { \.$list; \.$shortcuts }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.care) {
                    Summary("Mostra \(\.$content)") { \.$member; \.$shortcuts }
                } otherwise: {
                    When(\.$content, .equalTo, KBWidgetContent.fitness) {
                        Summary("Mostra \(\.$content)") { \.$member; \.$shortcuts }
                    } otherwise: {
                        When(\.$content, .equalTo, KBWidgetContent.photos) {
                            Summary("Mostra \(\.$content)") { \.$album; \.$shortcuts }
                        } otherwise: {
                            Summary("Mostra \(\.$content)") { \.$shortcuts }
                        }
                    }
                }
            }
        } otherwise: {
            When(\.$content, .equalTo, KBWidgetContent.todo) {
                Summary("Mostra \(\.$content)") { \.$list }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.care) {
                    Summary("Mostra \(\.$content)") { \.$member }
                } otherwise: {
                    When(\.$content, .equalTo, KBWidgetContent.fitness) {
                        Summary("Mostra \(\.$content)") { \.$member }
                    } otherwise: {
                        When(\.$content, .equalTo, KBWidgetContent.photos) {
                            Summary("Mostra \(\.$content)") { \.$album }
                        } otherwise: {
                            Summary("Mostra \(\.$content)")
                        }
                    }
                }
            }
        }
    }
}

/// Pagina To-do.
struct KidBoxTodoWidgetIntent: KBContentIntent {
    static let title: LocalizedStringResource = "KidBox"
    static let description = IntentDescription("Scegli cosa mostrare: calendario, to-do, spesa, cure, piano fitness o foto.")

    @Parameter(title: "Mostra", default: .todo)
    var content: KBWidgetContent

    @Parameter(title: "Lista")
    var list: TodoListEntity?

    @Parameter(title: "Membro")
    var member: ProfileEntity?

    @Parameter(title: "Album")
    var album: PhotoAlbumEntity?

    /// Solo nel formato grande: le scorciatoie sotto il contenuto.
    @Parameter(title: "Scorciatoie", size: [.systemLarge: 6])
    var shortcuts: [KBShortcutEntity]?

    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemLarge) {
            When(\.$content, .equalTo, KBWidgetContent.todo) {
                Summary("Mostra \(\.$content)") { \.$list; \.$shortcuts }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.care) {
                    Summary("Mostra \(\.$content)") { \.$member; \.$shortcuts }
                } otherwise: {
                    When(\.$content, .equalTo, KBWidgetContent.fitness) {
                        Summary("Mostra \(\.$content)") { \.$member; \.$shortcuts }
                    } otherwise: {
                        When(\.$content, .equalTo, KBWidgetContent.photos) {
                            Summary("Mostra \(\.$content)") { \.$album; \.$shortcuts }
                        } otherwise: {
                            Summary("Mostra \(\.$content)") { \.$shortcuts }
                        }
                    }
                }
            }
        } otherwise: {
            When(\.$content, .equalTo, KBWidgetContent.todo) {
                Summary("Mostra \(\.$content)") { \.$list }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.care) {
                    Summary("Mostra \(\.$content)") { \.$member }
                } otherwise: {
                    When(\.$content, .equalTo, KBWidgetContent.fitness) {
                        Summary("Mostra \(\.$content)") { \.$member }
                    } otherwise: {
                        When(\.$content, .equalTo, KBWidgetContent.photos) {
                            Summary("Mostra \(\.$content)") { \.$album }
                        } otherwise: {
                            Summary("Mostra \(\.$content)")
                        }
                    }
                }
            }
        }
    }
}

/// Pagina Spesa.
struct KidBoxGroceryWidgetIntent: KBContentIntent {
    static let title: LocalizedStringResource = "KidBox"
    static let description = IntentDescription("Scegli cosa mostrare: calendario, to-do, spesa, cure, piano fitness o foto.")

    @Parameter(title: "Mostra", default: .grocery)
    var content: KBWidgetContent

    @Parameter(title: "Lista")
    var list: TodoListEntity?

    @Parameter(title: "Membro")
    var member: ProfileEntity?

    @Parameter(title: "Album")
    var album: PhotoAlbumEntity?

    /// Solo nel formato grande: le scorciatoie sotto il contenuto.
    @Parameter(title: "Scorciatoie", size: [.systemLarge: 6])
    var shortcuts: [KBShortcutEntity]?

    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemLarge) {
            When(\.$content, .equalTo, KBWidgetContent.todo) {
                Summary("Mostra \(\.$content)") { \.$list; \.$shortcuts }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.care) {
                    Summary("Mostra \(\.$content)") { \.$member; \.$shortcuts }
                } otherwise: {
                    When(\.$content, .equalTo, KBWidgetContent.fitness) {
                        Summary("Mostra \(\.$content)") { \.$member; \.$shortcuts }
                    } otherwise: {
                        When(\.$content, .equalTo, KBWidgetContent.photos) {
                            Summary("Mostra \(\.$content)") { \.$album; \.$shortcuts }
                        } otherwise: {
                            Summary("Mostra \(\.$content)") { \.$shortcuts }
                        }
                    }
                }
            }
        } otherwise: {
            When(\.$content, .equalTo, KBWidgetContent.todo) {
                Summary("Mostra \(\.$content)") { \.$list }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.care) {
                    Summary("Mostra \(\.$content)") { \.$member }
                } otherwise: {
                    When(\.$content, .equalTo, KBWidgetContent.fitness) {
                        Summary("Mostra \(\.$content)") { \.$member }
                    } otherwise: {
                        When(\.$content, .equalTo, KBWidgetContent.photos) {
                            Summary("Mostra \(\.$content)") { \.$album }
                        } otherwise: {
                            Summary("Mostra \(\.$content)")
                        }
                    }
                }
            }
        }
    }
}

/// Pagina Cure.
struct KidBoxCareWidgetIntent: KBContentIntent {
    static let title: LocalizedStringResource = "KidBox"
    static let description = IntentDescription("Scegli cosa mostrare: calendario, to-do, spesa, cure, piano fitness o foto.")

    @Parameter(title: "Mostra", default: .care)
    var content: KBWidgetContent

    @Parameter(title: "Lista")
    var list: TodoListEntity?

    @Parameter(title: "Membro")
    var member: ProfileEntity?

    @Parameter(title: "Album")
    var album: PhotoAlbumEntity?

    /// Solo nel formato grande: le scorciatoie sotto il contenuto.
    @Parameter(title: "Scorciatoie", size: [.systemLarge: 6])
    var shortcuts: [KBShortcutEntity]?

    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemLarge) {
            When(\.$content, .equalTo, KBWidgetContent.todo) {
                Summary("Mostra \(\.$content)") { \.$list; \.$shortcuts }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.care) {
                    Summary("Mostra \(\.$content)") { \.$member; \.$shortcuts }
                } otherwise: {
                    When(\.$content, .equalTo, KBWidgetContent.fitness) {
                        Summary("Mostra \(\.$content)") { \.$member; \.$shortcuts }
                    } otherwise: {
                        When(\.$content, .equalTo, KBWidgetContent.photos) {
                            Summary("Mostra \(\.$content)") { \.$album; \.$shortcuts }
                        } otherwise: {
                            Summary("Mostra \(\.$content)") { \.$shortcuts }
                        }
                    }
                }
            }
        } otherwise: {
            When(\.$content, .equalTo, KBWidgetContent.todo) {
                Summary("Mostra \(\.$content)") { \.$list }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.care) {
                    Summary("Mostra \(\.$content)") { \.$member }
                } otherwise: {
                    When(\.$content, .equalTo, KBWidgetContent.fitness) {
                        Summary("Mostra \(\.$content)") { \.$member }
                    } otherwise: {
                        When(\.$content, .equalTo, KBWidgetContent.photos) {
                            Summary("Mostra \(\.$content)") { \.$album }
                        } otherwise: {
                            Summary("Mostra \(\.$content)")
                        }
                    }
                }
            }
        }
    }
}

/// Pagina Foto.
struct KidBoxPhotosWidgetIntent: KBContentIntent {
    static let title: LocalizedStringResource = "KidBox"
    static let description = IntentDescription("Scegli cosa mostrare: calendario, to-do, spesa, cure, piano fitness o foto.")

    @Parameter(title: "Mostra", default: .photos)
    var content: KBWidgetContent

    @Parameter(title: "Lista")
    var list: TodoListEntity?

    @Parameter(title: "Membro")
    var member: ProfileEntity?

    @Parameter(title: "Album")
    var album: PhotoAlbumEntity?

    /// Solo nel formato grande: le scorciatoie sotto il contenuto.
    @Parameter(title: "Scorciatoie", size: [.systemLarge: 6])
    var shortcuts: [KBShortcutEntity]?

    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemLarge) {
            When(\.$content, .equalTo, KBWidgetContent.todo) {
                Summary("Mostra \(\.$content)") { \.$list; \.$shortcuts }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.care) {
                    Summary("Mostra \(\.$content)") { \.$member; \.$shortcuts }
                } otherwise: {
                    When(\.$content, .equalTo, KBWidgetContent.fitness) {
                        Summary("Mostra \(\.$content)") { \.$member; \.$shortcuts }
                    } otherwise: {
                        When(\.$content, .equalTo, KBWidgetContent.photos) {
                            Summary("Mostra \(\.$content)") { \.$album; \.$shortcuts }
                        } otherwise: {
                            Summary("Mostra \(\.$content)") { \.$shortcuts }
                        }
                    }
                }
            }
        } otherwise: {
            When(\.$content, .equalTo, KBWidgetContent.todo) {
                Summary("Mostra \(\.$content)") { \.$list }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.care) {
                    Summary("Mostra \(\.$content)") { \.$member }
                } otherwise: {
                    When(\.$content, .equalTo, KBWidgetContent.fitness) {
                        Summary("Mostra \(\.$content)") { \.$member }
                    } otherwise: {
                        When(\.$content, .equalTo, KBWidgetContent.photos) {
                            Summary("Mostra \(\.$content)") { \.$album }
                        } otherwise: {
                            Summary("Mostra \(\.$content)")
                        }
                    }
                }
            }
        }
    }
}

/// Pagina Piano Fitness.
struct KidBoxFitnessWidgetIntent: KBContentIntent {
    static let title: LocalizedStringResource = "KidBox"
    static let description = IntentDescription("Scegli cosa mostrare: calendario, to-do, spesa, cure, piano fitness o foto.")

    @Parameter(title: "Mostra", default: .fitness)
    var content: KBWidgetContent

    @Parameter(title: "Lista")
    var list: TodoListEntity?

    @Parameter(title: "Membro")
    var member: ProfileEntity?

    @Parameter(title: "Album")
    var album: PhotoAlbumEntity?

    /// Solo nel formato grande: le scorciatoie sotto il contenuto.
    @Parameter(title: "Scorciatoie", size: [.systemLarge: 6])
    var shortcuts: [KBShortcutEntity]?

    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemLarge) {
            When(\.$content, .equalTo, KBWidgetContent.todo) {
                Summary("Mostra \(\.$content)") { \.$list; \.$shortcuts }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.care) {
                    Summary("Mostra \(\.$content)") { \.$member; \.$shortcuts }
                } otherwise: {
                    When(\.$content, .equalTo, KBWidgetContent.fitness) {
                        Summary("Mostra \(\.$content)") { \.$member; \.$shortcuts }
                    } otherwise: {
                        When(\.$content, .equalTo, KBWidgetContent.photos) {
                            Summary("Mostra \(\.$content)") { \.$album; \.$shortcuts }
                        } otherwise: {
                            Summary("Mostra \(\.$content)") { \.$shortcuts }
                        }
                    }
                }
            }
        } otherwise: {
            When(\.$content, .equalTo, KBWidgetContent.todo) {
                Summary("Mostra \(\.$content)") { \.$list }
            } otherwise: {
                When(\.$content, .equalTo, KBWidgetContent.care) {
                    Summary("Mostra \(\.$content)") { \.$member }
                } otherwise: {
                    When(\.$content, .equalTo, KBWidgetContent.fitness) {
                        Summary("Mostra \(\.$content)") { \.$member }
                    } otherwise: {
                        When(\.$content, .equalTo, KBWidgetContent.photos) {
                            Summary("Mostra \(\.$content)") { \.$album }
                        } otherwise: {
                            Summary("Mostra \(\.$content)")
                        }
                    }
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

// MARK: - Colonna sinistra dei widget larghi (come Promemoria di Apple)

/// Icona tonda in alto, numero grande e titolo colorato in basso.
struct KBWidgetCountColumn: View {
    let systemImage: String
    let color: Color
    let count: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(color))
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxHeight: .infinity, alignment: .leading)
    }
}

extension View {
    /// Il fondo del widget, tranne quando la vista è un pezzo del formato grande.
    @ViewBuilder
    func kbWidgetBackground(_ embedded: Bool) -> some View {
        if embedded { self } else { self.containerBackground(.background, for: .widget) }
    }
}

// MARK: - Griglia di scorciatoie (formato grande)

/// Due file da tre: icona sul quadrato del colore della sezione, nome sotto.
/// Ogni casella è un `Link`, che nel widget vale più del `widgetURL` del contenuto.
struct KBShortcutGrid: View {
    let sections: [KBShortcutSection]

    var body: some View {
        let rows = stride(from: 0, to: sections.count, by: 3).map { Array(sections[$0..<min($0 + 3, sections.count)]) }
        VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(rows[r], id: \.self) { tile($0) }
                    // Caselle vuote: tengono la misura senza farsi vedere.
                    ForEach(0..<(3 - rows[r].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }

    private func tile(_ section: KBShortcutSection) -> some View {
        Link(destination: URL(string: "kidbox://widget/\(section.rawValue)")!) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(section.tint.gradient)
                    .frame(height: 48)
                    .overlay {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                Text(section.label)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
