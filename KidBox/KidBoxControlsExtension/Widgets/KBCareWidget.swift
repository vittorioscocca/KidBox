//
//  KBCareWidget.swift
//  KidBoxControlsExtension
//
//  Widget quadrato «Cure»: le prossime dosi del membro scelto (o di tutti).
//

import SwiftUI
import WidgetKit
import AppIntents

struct KBCareEntry: TimelineEntry {
    let date: Date
    let snapshot: KBWidgetSnapshot?
    let memberId: String?
}

struct KBCareProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> KBCareEntry { .init(date: .now, snapshot: nil, memberId: nil) }

    func snapshot(for configuration: CareWidgetIntent, in context: Context) async -> KBCareEntry {
        .init(date: .now, snapshot: KBWidgetStore.read(), memberId: configuration.member?.id)
    }

    func timeline(for configuration: CareWidgetIntent, in context: Context) async -> Timeline<KBCareEntry> {
        let snap = KBWidgetStore.read()
        let memberId = configuration.member?.id
        let now = Date()
        // Una voce a ogni orario di dose: lo stato «in ritardo» scatta da solo.
        var dates: Set<Date> = [now]
        for d in snap?.doses ?? [] where d.time > now && (memberId == nil || d.childId == memberId) {
            dates.insert(d.time)
            if dates.count >= 12 { break }
        }
        let entries = dates.sorted().map { KBCareEntry(date: $0, snapshot: snap, memberId: memberId) }
        return Timeline(entries: entries, policy: .after(kbNextMidnight(after: now)))
    }
}

struct KBCareWidgetView: View {
    let entry: KBCareEntry

    private var doses: [KBWidgetSnapshot.Dose] {
        guard let snap = entry.snapshot else { return [] }
        return snap.doses.filter { entry.memberId == nil || $0.childId == entry.memberId }
    }

    /// Da prendere: quelle di oggi non prese (anche in ritardo), poi domani.
    private var pending: [KBWidgetSnapshot.Dose] { doses.filter { !$0.taken } }

    private var title: String {
        if let id = entry.memberId, let p = entry.snapshot?.profiles.first(where: { $0.id == id }) {
            return p.name
        }
        return String(localized: "Cure")
    }

    private func name(of childId: String) -> String? {
        guard entry.memberId == nil, (entry.snapshot?.profiles.count ?? 0) > 1 else { return nil }
        return entry.snapshot?.profiles.first { $0.id == childId }?.name
    }

    /// Apre la cura della prima dose da prendere; senza dosi, le cure del membro.
    private var deepLink: URL? {
        var c = URLComponents(string: "kidbox://widget/care")
        let first = pending.first
        let child = entry.memberId ?? first?.childId ?? entry.snapshot?.profiles.first?.id
        var q: [URLQueryItem] = []
        if let child { q.append(.init(name: "child", value: child)) }
        if let first, let tid = first.id.split(separator: "|").first {
            q.append(.init(name: "treatment", value: String(tid)))
        }
        c?.queryItems = q.isEmpty ? nil : q
        return c?.url
    }

    /// Quante dosi di oggi sono già prese, sul totale di oggi.
    private var todayProgress: (taken: Int, total: Int) {
        let cal = Calendar.current
        let today = doses.filter { cal.isDate($0.time, inSameDayAs: entry.date) }
        return (today.filter(\.taken).count, today.count)
    }

    var body: some View {
        Group {
            if entry.snapshot != nil {
                VStack(alignment: .leading, spacing: 4) {
                    KBWidgetHeader(title: title, color: .kbCare)
                    if doses.isEmpty {
                        KBWidgetMessage(systemImage: "pills", text: "Nessuna cura attiva", color: .kbCare)
                    } else if let dose = pending.first {
                        let late = dose.time < entry.date
                        Text(dose.time, format: .dateTime.hour().minute())
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(late ? Color.kbCalendar : Color.kbCare)
                        Text(dose.drugName)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if !dose.dosage.isEmpty {
                                Text(dose.dosage).lineLimit(1)
                            }
                            if let who = name(of: dose.childId) {
                                Text("· \(who)").lineLimit(1)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button(intent: KBMarkDoseTakenIntent(doseId: dose.id)) {
                            Label("Presa", systemImage: "checkmark")
                                .font(.system(.footnote, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.kbCare))
                        }
                        .buttonStyle(.plain)
                    } else {
                        KBWidgetMessage(systemImage: "checkmark.circle", text: "Tutto preso", color: .kbCare)
                    }
                    if !doses.isEmpty {
                        let p = todayProgress
                        if p.total > 0 {
                            Text("\(p.taken) di \(p.total) oggi")
                                .font(.caption2).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            } else {
                KBWidgetSignedOut()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(deepLink)
        .containerBackground(.background, for: .widget)
    }
}

struct KBCareWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "KidBoxCareWidget", intent: CareWidgetIntent.self,
                               provider: KBCareProvider()) { entry in
            KBCareWidgetView(entry: entry)
        }
        .configurationDisplayName("Cure")
        .description("Le prossime dosi dei farmaci di un membro della famiglia.")
        .supportedFamilies([.systemSmall])
    }
}
