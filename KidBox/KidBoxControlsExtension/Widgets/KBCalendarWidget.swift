//
//  KBCalendarWidget.swift
//  KidBoxControlsExtension
//
//  Widget quadrato «Calendario»: il giorno e i prossimi eventi di oggi.
//

import SwiftUI
import WidgetKit

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

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemMedium { mediumBody } else { smallBody }
    }

    @ViewBuilder
    private var smallBody: some View {
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

// MARK: - Largo: oggi a sinistra, i prossimi giorni a destra (come Calendario di Apple)

extension KBCalendarWidgetView {

    /// Eventi dai prossimi giorni (da domani in poi).
    private var upcoming: [KBWidgetSnapshot.Event] {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: entry.date)) ?? entry.date
        return (entry.snapshot?.events ?? []).filter { $0.start >= tomorrow }
    }

    private func dayHeader(_ date: Date) -> some View {
        Group {
            if cal.isDateInTomorrow(date) {
                Text("Domani")
            } else {
                Text(date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
            }
        }
        .textCase(.uppercase)
        .font(.system(.caption, design: .rounded).weight(.bold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func card(_ event: KBWidgetSnapshot.Event) -> some View {
        let color = Color(hex: event.colorHex)
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                Group {
                    if event.isAllDay {
                        Text("Tutto il giorno")
                    } else {
                        Text("\(event.start, format: .dateTime.hour().minute()) - \(event.end, format: .dateTime.hour().minute())")
                    }
                }
                .font(.caption2)
                .foregroundStyle(color.opacity(0.85))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.trailing, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.12)))
    }

    private var mediumLeft: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.date, format: .dateTime.weekday(.wide))
                .textCase(.uppercase)
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(Color.kbCalendar)
            Text(entry.date, format: .dateTime.day())
                .font(.system(size: 34, weight: .semibold, design: .rounded))
            Spacer(minLength: 2)
            if entry.snapshot == nil {
                Text("Apri KidBox per iniziare")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if todayEvents.isEmpty {
                Text("Nessun evento oggi")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(todayEvents.prefix(2)) { card($0) }
                }
                if todayEvents.count > 2 {
                    Text(String(localized: "\(todayEvents.count - 2) altri eventi"))
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Due eventi in scheda, ognuno sotto l'intestazione del suo giorno; del
    /// giorno dopo solo quanti sono, come fa Calendario quando non c'è spazio.
    @ViewBuilder
    private var mediumRight: some View {
        let events = upcoming
        let shown = Array(events.prefix(2))
        VStack(alignment: .leading, spacing: 4) {
            if events.isEmpty {
                Spacer(minLength: 0)
                Text("Nessun evento in programma")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, event in
                    if i == 0 || !cal.isDate(event.start, inSameDayAs: shown[i - 1].start) {
                        dayHeader(event.start)
                    }
                    card(event)
                }
                if let next = events.dropFirst(shown.count).first {
                    let sameDay = events.dropFirst(shown.count).filter { cal.isDate($0.start, inSameDayAs: next.start) }
                    if !cal.isDate(next.start, inSameDayAs: shown.last?.start ?? .distantPast) {
                        dayHeader(next.start)
                    }
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(hex: next.colorHex))
                            .frame(width: 3, height: 13)
                        Text(String(localized: "\(sameDay.count) altri eventi"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var mediumBody: some View {
        HStack(alignment: .top, spacing: 14) {
            mediumLeft
            mediumRight
        }
        .widgetURL(URL(string: "kidbox://widget/calendar"))
        .containerBackground(.background, for: .widget)
    }
}
