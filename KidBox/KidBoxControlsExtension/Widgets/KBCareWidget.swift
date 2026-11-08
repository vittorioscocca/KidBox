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

struct KBCareWidgetView: View {
    let entry: KBCareEntry

    private var doses: [KBWidgetSnapshot.Dose] {
        guard let snap = entry.snapshot else { return [] }
        return snap.doses.filter { entry.memberId == nil || $0.childId == entry.memberId }
    }

    /// Da prendere: quelle di oggi non prese (anche in ritardo), poi domani.
    private var pending: [KBWidgetSnapshot.Dose] { doses.filter(\.isPending) }

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

    /// Dosi di oggi già gestite (prese o saltate), sul totale di oggi.
    private var todayProgress: (done: Int, total: Int) {
        let cal = Calendar.current
        let today = doses.filter { cal.isDate($0.time, inSameDayAs: entry.date) }
        return (today.filter { !$0.isPending }.count, today.count)
    }

    private func actionButton(_ dose: KBWidgetSnapshot.Dose, taken: Bool) -> some View {
        Button(intent: KBMarkDoseTakenIntent(doseId: dose.id, taken: taken)) {
            Group {
                if taken {
                    Label("Presa", systemImage: "checkmark")
                } else {
                    Label("Saltata", systemImage: "xmark")
                }
            }
            .labelStyle(.titleAndIcon)
            .font(.system(.caption, design: .rounded).weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(taken ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Capsule().fill(taken ? Color.kbCare : Color.secondary.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        Group {
            if entry.snapshot != nil {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Color.kbCare)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        let p = todayProgress
                        if p.total > 0 {
                            Text("\(p.done)/\(p.total)")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if doses.isEmpty {
                        KBWidgetMessage(systemImage: "pills", text: "Nessuna cura attiva", color: .kbCare)
                    } else if let dose = pending.first {
                        let late = dose.time < entry.date
                        Text(dose.time, format: .dateTime.hour().minute())
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(late ? Color.kbCalendar : Color.kbCare)
                        Text(dose.drugName)
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                        let detail = [dose.dosage, name(of: dose.childId) ?? ""].filter { !$0.isEmpty }
                        if !detail.isEmpty {
                            Text(detail.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        HStack(spacing: 6) {
                            actionButton(dose, taken: true)
                            actionButton(dose, taken: false)
                        }
                    } else {
                        KBWidgetMessage(systemImage: "checkmark.circle", text: "Tutto fatto per oggi", color: .kbCare)
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
