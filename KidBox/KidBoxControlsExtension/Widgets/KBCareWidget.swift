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

    var body: some View {
        Group {
            if entry.snapshot != nil {
                VStack(alignment: .leading, spacing: 6) {
                    KBWidgetHeader(title: title, color: .kbCare, count: pending.isEmpty ? nil : pending.count)
                    if doses.isEmpty {
                        KBWidgetMessage(systemImage: "pills", text: "Nessuna cura attiva", color: .kbCare)
                    } else if pending.isEmpty {
                        KBWidgetMessage(systemImage: "checkmark.circle", text: "Tutto preso", color: .kbCare)
                    } else {
                        ForEach(pending.prefix(3)) { dose in
                            let late = dose.time < entry.date
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 4) {
                                    Text(dose.time, format: .dateTime.hour().minute())
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(late ? Color.kbCalendar : Color.kbCare)
                                    if let who = name(of: dose.childId) {
                                        Text(who).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Text(dose.dosage.isEmpty ? dose.drugName : "\(dose.drugName) · \(dose.dosage)")
                                    .font(.system(.footnote, design: .rounded).weight(.medium))
                                    .lineLimit(1)
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
        .widgetURL(URL(string: "kidbox://widget/health"))
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
