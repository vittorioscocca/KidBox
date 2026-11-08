//
//  KBHomeWidget.swift
//  KidBoxControlsExtension
//
//  L'unico widget quadrato di KidBox: dal menù «Modifica widget» (tocco
//  lungo) si sceglie se mostrare Calendario, To-do, Spesa, Cure o Piano
//  Fitness, e per To-do, Cure e Fitness anche la lista o il membro.
//

import SwiftUI
import WidgetKit
import AppIntents

struct KBHomeEntry: TimelineEntry {
    let date: Date
    let snapshot: KBWidgetSnapshot?
    let content: KBWidgetContent
    let listId: String?
    let memberId: String?
}

struct KBHomeProvider<I: KBContentIntent>: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> KBHomeEntry {
        .init(date: .now, snapshot: nil, content: I().content, listId: nil, memberId: nil)
    }

    func snapshot(for configuration: I, in context: Context) async -> KBHomeEntry {
        entry(configuration, at: .now, snapshot: KBWidgetStore.read())
    }

    func timeline(for configuration: I, in context: Context) async -> Timeline<KBHomeEntry> {
        let snap = KBWidgetStore.read()
        let now = Date()
        let midnight = kbNextMidnight(after: now)
        var dates: Set<Date> = [now]
        switch configuration.content {
        case .calendar:
            // Una voce a ogni fine evento di oggi: quello finito sparisce da solo.
            for e in snap?.events ?? [] where !e.isAllDay && e.end > now && e.end < midnight {
                dates.insert(e.end)
            }
        case .care:
            // Una voce a ogni orario di dose: lo stato «in ritardo» scatta da solo.
            let member = configuration.member?.id
            for d in snap?.doses ?? [] where d.time > now && (member == nil || d.childId == member) {
                dates.insert(d.time)
                if dates.count >= 12 { break }
            }
        default:
            break
        }
        let entries = dates.sorted().map { entry(configuration, at: $0, snapshot: snap) }
        return Timeline(entries: entries, policy: .after(midnight))
    }

    private func entry(_ c: I, at date: Date, snapshot: KBWidgetSnapshot?) -> KBHomeEntry {
        .init(date: date, snapshot: snapshot, content: c.content, listId: c.list?.id, memberId: c.member?.id)
    }
}

struct KBHomeWidgetView: View {
    let entry: KBHomeEntry

    var body: some View {
        switch entry.content {
        case .calendar:
            KBCalendarWidgetView(entry: .init(date: entry.date, snapshot: entry.snapshot))
        case .todo:
            KBTodoWidgetView(entry: .init(date: entry.date, snapshot: entry.snapshot, listId: entry.listId))
        case .grocery:
            KBGroceryWidgetView(entry: .init(date: entry.date, snapshot: entry.snapshot))
        case .care:
            KBCareWidgetView(entry: .init(date: entry.date, snapshot: entry.snapshot, memberId: entry.memberId))
        case .fitness:
            KBFitnessWidgetView(entry: .init(date: entry.date, snapshot: entry.snapshot, memberId: entry.memberId))
        }
    }
}

/// Le cinque pagine della galleria. L'ordine conta: la prima è quella che iOS
/// usa quando l'icona dell'app diventa un widget. I kind sono nuovi rispetto
/// alla prima build (KidBoxCalendarWidget, KidBoxTodoWidget, …): riusarli
/// riaggancerebbe istanze vecchie senza configurazione.
private func kbHomeConfiguration<I: KBContentIntent>(
    kind: String, intent: I.Type, name: LocalizedStringResource, description: LocalizedStringResource
) -> some WidgetConfiguration {
    AppIntentConfiguration(kind: kind, intent: I.self, provider: KBHomeProvider<I>()) { entry in
        KBHomeWidgetView(entry: entry)
    }
    .configurationDisplayName(Text(name))
    .description(Text(description))
    .supportedFamilies([.systemSmall])
}

struct KBHomeWidget: Widget {
    static let kind = "KidBoxHomeWidget"
    var body: some WidgetConfiguration {
        kbHomeConfiguration(kind: Self.kind, intent: KidBoxWidgetIntent.self,
                            name: "Calendario",
                            description: "Gli eventi di oggi. Da «Modifica widget» puoi mostrare anche to-do, spesa, cure o piano fitness.")
    }
}

struct KBTodoHomeWidget: Widget {
    var body: some WidgetConfiguration {
        kbHomeConfiguration(kind: "KidBoxHomeWidget.todo", intent: KidBoxTodoWidgetIntent.self,
                            name: "To-do",
                            description: "I to-do della famiglia, di una lista a tua scelta.")
    }
}

struct KBGroceryHomeWidget: Widget {
    var body: some WidgetConfiguration {
        kbHomeConfiguration(kind: "KidBoxHomeWidget.grocery", intent: KidBoxGroceryWidgetIntent.self,
                            name: "Lista della spesa",
                            description: "Cosa resta da comprare.")
    }
}

struct KBCareHomeWidget: Widget {
    var body: some WidgetConfiguration {
        kbHomeConfiguration(kind: "KidBoxHomeWidget.care", intent: KidBoxCareWidgetIntent.self,
                            name: "Cure",
                            description: "La prossima dose di un membro della famiglia, da segnare come presa.")
    }
}

struct KBFitnessHomeWidget: Widget {
    var body: some WidgetConfiguration {
        kbHomeConfiguration(kind: "KidBoxHomeWidget.fitness", intent: KidBoxFitnessWidgetIntent.self,
                            name: "Piano Fitness",
                            description: "L'allenamento di oggi dal piano di un membro della famiglia.")
    }
}
