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

struct KBHomeProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> KBHomeEntry {
        .init(date: .now, snapshot: nil, content: .calendar, listId: nil, memberId: nil)
    }

    func snapshot(for configuration: KidBoxWidgetIntent, in context: Context) async -> KBHomeEntry {
        entry(configuration, at: .now, snapshot: KBWidgetStore.read())
    }

    func timeline(for configuration: KidBoxWidgetIntent, in context: Context) async -> Timeline<KBHomeEntry> {
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

    private func entry(_ c: KidBoxWidgetIntent, at date: Date, snapshot: KBWidgetSnapshot?) -> KBHomeEntry {
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

struct KBHomeWidget: Widget {
    static let kind = "KidBoxHomeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: KidBoxWidgetIntent.self,
                               provider: KBHomeProvider()) { entry in
            KBHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("KidBox")
        .description("Calendario, to-do, spesa, cure o piano fitness: scegli da «Modifica widget».")
        .supportedFamilies([.systemSmall])
    }
}
