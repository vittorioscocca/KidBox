//
//  KBTodoWidget.swift
//  KidBoxControlsExtension
//
//  Widget quadrato «To-do»: la lista scelta (o tutti), col numero dei
//  rimasti in alto a destra, come Promemoria di Apple.
//

import SwiftUI
import WidgetKit
import AppIntents

struct KBTodoEntry: TimelineEntry {
    let date: Date
    let snapshot: KBWidgetSnapshot?
    let listId: String?     // nil = tutti
}

struct KBTodoProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> KBTodoEntry { .init(date: .now, snapshot: nil, listId: nil) }

    func snapshot(for configuration: TodoWidgetIntent, in context: Context) async -> KBTodoEntry {
        .init(date: .now, snapshot: KBWidgetStore.read(), listId: configuration.list?.id)
    }

    func timeline(for configuration: TodoWidgetIntent, in context: Context) async -> Timeline<KBTodoEntry> {
        let entry = KBTodoEntry(date: .now, snapshot: KBWidgetStore.read(), listId: configuration.list?.id)
        return Timeline(entries: [entry], policy: .after(kbNextMidnight(after: .now)))
    }
}

struct KBTodoWidgetView: View {
    let entry: KBTodoEntry

    private struct Content {
        var title: String
        var count: Int
        var items: [KBWidgetSnapshot.TodoItem]
    }

    private var content: Content? {
        guard let snap = entry.snapshot else { return nil }
        if let id = entry.listId {
            let key = id == TodoListEntity.noListId ? "" : id
            if let list = snap.todoLists.first(where: { $0.id == key }) {
                return Content(title: list.name.isEmpty ? String(localized: "Senza lista") : list.name,
                               count: list.openCount, items: list.items)
            }
            // Lista cancellata dopo la scelta: ripiega su tutti.
        }
        // Tutti: scadenze prima, poi il resto.
        let all = snap.todoLists.flatMap(\.items).sorted {
            switch ($0.due, $1.due) {
            case let (a?, b?): return a < b
            case (_?, nil):    return true
            case (nil, _?):    return false
            default:           return false
            }
        }
        return Content(title: String(localized: "To-do"),
                       count: snap.todoLists.reduce(0) { $0 + $1.openCount }, items: all)
    }

    var body: some View {
        Group {
            if let content {
                VStack(alignment: .leading, spacing: 6) {
                    KBWidgetHeader(title: content.title, color: .kbTodo, count: content.count)
                    if content.items.isEmpty {
                        KBWidgetMessage(systemImage: "checkmark.circle", text: "Niente da fare", color: .kbTodo)
                    } else {
                        ForEach(content.items.prefix(4)) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "circle")
                                    .font(.system(size: 15))
                                    .foregroundStyle(item.isUrgent ? Color.kbCalendar : .secondary)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.title)
                                        .font(.system(.footnote, design: .rounded).weight(.medium))
                                        .lineLimit(1)
                                    if let due = item.due {
                                        Group {
                                            if item.hasTime {
                                                Text(due, format: .dateTime.day().month(.abbreviated).hour().minute())
                                            } else {
                                                Text(due, format: .dateTime.day().month(.abbreviated))
                                            }
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(due < entry.date ? Color.kbCalendar : .secondary)
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                KBWidgetSignedOut()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "kidbox://widget/todo"))
        .containerBackground(.background, for: .widget)
    }
}

struct KBTodoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "KidBoxTodoWidget", intent: TodoWidgetIntent.self,
                               provider: KBTodoProvider()) { entry in
            KBTodoWidgetView(entry: entry)
        }
        .configurationDisplayName("To-do")
        .description("I to-do della famiglia, di una lista a tua scelta.")
        .supportedFamilies([.systemSmall])
    }
}
