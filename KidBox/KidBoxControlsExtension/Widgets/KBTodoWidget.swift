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

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemMedium { mediumBody } else { smallBody }
    }

    @ViewBuilder
    private var smallBody: some View {
        Group {
            if let content {
                VStack(alignment: .leading, spacing: 6) {
                    KBWidgetHeader(title: content.title, color: .kbTodo, count: content.count)
                    if content.items.isEmpty {
                        KBWidgetMessage(systemImage: "checkmark.circle", text: "Niente da fare", color: .kbTodo)
                    } else {
                        // Le scadenze occupano una seconda riga: con quelle ne stanno tre.
                        let rows = content.items.prefix(4).contains { $0.due != nil } ? 3 : 4
                        ForEach(content.items.prefix(rows)) { item in
                            HStack(alignment: .top, spacing: 6) {
                                // Toccabile come in Promemoria: il to-do sparisce e il numero scala.
                                Button(intent: KBMarkTodoDoneIntent(todoId: item.id)) {
                                    Image(systemName: "circle")
                                        .font(.system(size: 15))
                                        .foregroundStyle(item.isUrgent ? Color.kbCalendar : .secondary)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.title)
                                        .font(.system(.footnote, design: .rounded))
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

// MARK: - Largo: numero e nome a sinistra, le righe a destra (come Promemoria)

extension KBTodoWidgetView {

    private func row(_ item: KBWidgetSnapshot.TodoItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button(intent: KBMarkTodoDoneIntent(todoId: item.id)) {
                Image(systemName: "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(item.isUrgent ? Color.kbCalendar : .secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(.subheadline, design: .rounded))
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
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    var mediumBody: some View {
        Group {
            if let content {
                HStack(alignment: .top, spacing: 12) {
                    KBWidgetCountColumn(systemImage: "checklist", color: .kbTodo,
                                        count: content.count, title: content.title)
                        .frame(width: 110, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        if content.items.isEmpty {
                            KBWidgetMessage(systemImage: "checkmark.circle", text: "Niente da fare", color: .kbTodo)
                        } else {
                            let rows = content.items.prefix(4).contains { $0.due != nil } ? 3 : 4
                            ForEach(content.items.prefix(rows)) { row($0) }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                KBWidgetSignedOut()
            }
        }
        .widgetURL(URL(string: "kidbox://widget/todo"))
        .containerBackground(.background, for: .widget)
    }
}
