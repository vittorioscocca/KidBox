//
//  KBCalendarWidget.swift
//  KidBoxControlsExtension
//
//  Widget quadrato «Calendario»: il giorno e i prossimi eventi di oggi.
//

import SwiftUI
import WidgetKit

struct KBCalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> KBWidgetEntry { .init(date: .now, snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (KBWidgetEntry) -> Void) {
        completion(.init(date: .now, snapshot: KBWidgetStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KBWidgetEntry>) -> Void) {
        let snap = KBWidgetStore.read()
        let now = Date()
        let midnight = kbNextMidnight(after: now)
        // Una voce ad ogni fine evento di oggi: quello finito sparisce da solo.
        var dates: Set<Date> = [now]
        for e in snap?.events ?? [] where !e.isAllDay && e.end > now && e.end < midnight {
            dates.insert(e.end)
        }
        let entries = dates.sorted().map { KBWidgetEntry(date: $0, snapshot: snap) }
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

struct KBCalendarWidgetView: View {
    let entry: KBWidgetEntry

    private var cal: Calendar { .current }

    /// Eventi di oggi non ancora finiti; quelli «tutto il giorno» per primi.
    private var todayEvents: [KBWidgetSnapshot.Event] {
        guard let snap = entry.snapshot else { return [] }
        let start = cal.startOfDay(for: entry.date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return snap.events
            .filter { $0.start < end && $0.end >= start && ($0.isAllDay || $0.end > entry.date) }
            .sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                return $0.start < $1.start
            }
    }

    private var nextEvent: KBWidgetSnapshot.Event? {
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: entry.date)) ?? entry.date
        return entry.snapshot?.events.first { $0.start >= end }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.date, format: .dateTime.weekday(.wide))
                .textCase(.uppercase)
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(Color.kbCalendar)
            Text(entry.date, format: .dateTime.day())
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .padding(.bottom, 4)

            if entry.snapshot == nil {
                Spacer(minLength: 0)
                Text("Apri KidBox per iniziare")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if todayEvents.isEmpty {
                Text("Nessun evento oggi")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                if let next = nextEvent {
                    Spacer(minLength: 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(next.start, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(next.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            } else {
                ForEach(todayEvents.prefix(2)) { event in
                    HStack(alignment: .top, spacing: 5) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(hex: event.colorHex))
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(event.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            if event.isAllDay {
                                Text("Tutto il giorno")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else {
                                Text(event.start, format: .dateTime.hour().minute())
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.bottom, 3)
                }
                if todayEvents.count > 2 {
                    Text("+\(todayEvents.count - 2)")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "kidbox://widget/calendar"))
        .containerBackground(.background, for: .widget)
    }
}

struct KBCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KidBoxCalendarWidget", provider: KBCalendarProvider()) { entry in
            KBCalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("Calendario")
        .description("Gli eventi di oggi della tua famiglia.")
        .supportedFamilies([.systemSmall])
    }
}
