//
//  KBFitnessWidget.swift
//  KidBoxControlsExtension
//
//  Widget quadrato «Piano Fitness»: l'allenamento di oggi del membro scelto.
//  Solo Pro/Max: sui Free il widget lo dice, non mostra dati.
//

import SwiftUI
import WidgetKit
import AppIntents

struct KBFitnessEntry: TimelineEntry {
    let date: Date
    let snapshot: KBWidgetSnapshot?
    let memberId: String?
}

struct KBFitnessWidgetView: View {
    let entry: KBFitnessEntry

    private var profile: KBWidgetSnapshot.FitnessProfile? {
        guard let snap = entry.snapshot else { return nil }
        if let id = entry.memberId { return snap.fitness.first { $0.id == id } }
        return snap.fitness.first
    }

    private var memberName: String? {
        guard let p = profile else { return nil }
        return entry.snapshot?.profiles.first { $0.id == p.id }?.name
            .split(separator: " ").first.map(String.init)
    }

    private func icon(_ type: String) -> String {
        let t = type.lowercased()
        if t.contains("cors") || t.contains("run")      { return "figure.run" }
        if t.contains("cammin") || t.contains("walk")   { return "figure.walk" }
        if t.contains("bici") || t.contains("cicl")     { return "figure.outdoor.cycle" }
        if t.contains("nuot")                           { return "figure.pool.swim" }
        if t.contains("yoga") || t.contains("mobil")    { return "figure.yoga" }
        if t.contains("forz") || t.contains("pesi")     { return "figure.strengthtraining.traditional" }
        return "figure.mixed.cardio"
    }

    /// Apre il piano del membro mostrato; senza piano, la Salute.
    private var deepLink: URL? {
        var c = URLComponents(string: "kidbox://widget/fitness")
        if let id = profile?.id, entry.snapshot?.fitnessUnlocked == true {
            c?.queryItems = [.init(name: "child", value: id)]
        }
        return c?.url
    }

    /// Dentro il formato grande: disegna il largo senza fondo proprio.
    var embedded = false

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemMedium || embedded { mediumBody } else { smallBody }
    }

    @ViewBuilder
    private var smallBody: some View {
        let cal = Calendar.current
        Group {
            if entry.snapshot == nil {
                KBWidgetSignedOut()
            } else if entry.snapshot?.fitnessUnlocked == false {
                KBWidgetMessage(systemImage: "lock.fill", text: "Disponibile con Pro", color: .kbFitness)
            } else if let profile {
                let today = profile.sessions.first { cal.isDate($0.date, inSameDayAs: entry.date) }
                let next = profile.sessions.first { $0.date > entry.date && !$0.isDone && !$0.isSkipped }
                VStack(alignment: .leading, spacing: 6) {
                    KBWidgetHeader(title: memberName ?? String(localized: "Fitness"), color: .kbFitness)
                    if let today {
                        HStack(spacing: 8) {
                            Image(systemName: today.isDone ? "checkmark.circle.fill" : icon(today.activityType))
                                .font(.title2)
                                .foregroundStyle(today.isDone ? Color.kbGrocery : Color.kbFitness)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(today.title)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .lineLimit(2)
                                Group {
                                    if today.isDone { Text("Fatto") } else { Text("\(today.minutes) min") }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Label("Riposo oggi", systemImage: "moon.zzz")
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                    }
                    Spacer(minLength: 0)
                    if let next, today?.isDone != false || today == nil {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(next.date, format: .dateTime.weekday(.wide).day())
                                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Text(next.title).font(.caption.weight(.medium)).lineLimit(1)
                        }
                    }
                }
            } else {
                KBWidgetMessage(systemImage: "figure.run", text: "Nessun piano fitness", color: .kbFitness)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(deepLink)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Largo: oggi a sinistra, le prossime sedute a destra

extension KBFitnessWidgetView {

    var mediumBody: some View {
        let cal = Calendar.current
        return Group {
            if entry.snapshot == nil {
                KBWidgetSignedOut()
            } else if entry.snapshot?.fitnessUnlocked == false {
                KBWidgetMessage(systemImage: "lock.fill", text: "Disponibile con Pro", color: .kbFitness)
            } else if let profile {
                let today = profile.sessions.first { cal.isDate($0.date, inSameDayAs: entry.date) }
                let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: entry.date)) ?? entry.date
                let next = Array(profile.sessions.filter { $0.date >= tomorrow && !$0.isSkipped }.prefix(3))
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        KBWidgetHeader(title: memberName ?? String(localized: "Fitness"), color: .kbFitness)
                        Text("Oggi")
                            .textCase(.uppercase)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(.secondary)
                        if let today {
                            HStack(spacing: 8) {
                                Image(systemName: today.isDone ? "checkmark.circle.fill" : icon(today.activityType))
                                    .font(.title2)
                                    .foregroundStyle(today.isDone ? Color.kbGrocery : Color.kbFitness)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(today.title)
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .lineLimit(2)
                                    Group {
                                        if today.isDone { Text("Fatto") } else { Text("\(today.minutes) min") }
                                    }
                                    .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Label("Riposo oggi", systemImage: "moon.zzz")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Prossime")
                            .textCase(.uppercase)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(.secondary)
                        if next.isEmpty {
                            Text("Nessuna seduta in programma")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(next) { s in
                                HStack(spacing: 6) {
                                    Image(systemName: s.isDone ? "checkmark.circle.fill" : icon(s.activityType))
                                        .font(.footnote)
                                        .foregroundStyle(s.isDone ? Color.kbGrocery : Color.kbFitness)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(s.title)
                                            .font(.system(.caption, design: .rounded).weight(.semibold))
                                            .lineLimit(1)
                                        Text("\(s.date, format: .dateTime.weekday(.wide).day()) · \(s.minutes) min")
                                            .font(.caption2).foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                KBWidgetMessage(systemImage: "figure.run", text: "Nessun piano fitness", color: .kbFitness)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(deepLink)
        .kbWidgetBackground(embedded)
    }
}
