//
//  KBGroceryWidget.swift
//  KidBoxControlsExtension
//
//  Widget quadrato «Spesa»: quello che resta da comprare.
//

import SwiftUI
import WidgetKit
import AppIntents

struct KBGroceryWidgetView: View {
    let entry: KBWidgetEntry

    /// Dentro il formato grande: disegna il largo senza fondo proprio.
    var embedded = false

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemMedium || embedded { mediumBody } else { smallBody }
    }

    @ViewBuilder
    private var smallBody: some View {
        Group {
            if let snap = entry.snapshot {
                VStack(alignment: .leading, spacing: 7) {
                    KBWidgetHeader(title: String(localized: "Spesa"), color: .kbGrocery,
                                   count: snap.grocery.count)
                    if snap.grocery.isEmpty {
                        KBWidgetMessage(systemImage: "cart", text: "Lista vuota", color: .kbGrocery)
                    } else {
                        // Quattro righe al massimo: con cinque il riquadro era pieno
                        // fino al bordo e il numero usciva in alto.
                        ForEach(snap.grocery.prefix(4)) { item in
                            HStack(spacing: 7) {
                                Button(intent: KBMarkGroceryBoughtIntent(itemId: item.id)) {
                                    Image(systemName: "circle")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Text(item.name)
                                    .font(.system(.footnote, design: .rounded))
                                    .lineLimit(1)
                                if let q = item.quantity, q > 1 {
                                    Spacer(minLength: 2)
                                    Text("×\(q)").font(.caption2).foregroundStyle(.secondary)
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
        .widgetURL(URL(string: "kidbox://widget/shopping"))
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Largo: numero a sinistra, le voci a destra (come Promemoria)

extension KBGroceryWidgetView {

    @ViewBuilder
    var mediumBody: some View {
        Group {
            if let snap = entry.snapshot {
                HStack(alignment: .top, spacing: 12) {
                    KBWidgetCountColumn(systemImage: "cart.fill", color: .kbGrocery,
                                        count: snap.grocery.count, title: String(localized: "Spesa"))
                        .frame(width: 110, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        if snap.grocery.isEmpty {
                            KBWidgetMessage(systemImage: "cart", text: "Lista vuota", color: .kbGrocery)
                        } else {
                            ForEach(snap.grocery.prefix(4)) { item in
                                HStack(spacing: 8) {
                                    Button(intent: KBMarkGroceryBoughtIntent(itemId: item.id)) {
                                        Image(systemName: "circle")
                                            .font(.system(size: 20, weight: .light))
                                            .foregroundStyle(.secondary)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    Text(item.name)
                                        .font(.system(.subheadline, design: .rounded))
                                        .lineLimit(1)
                                    Spacer(minLength: 2)
                                    if let q = item.quantity, q > 1 {
                                        Text("×\(q)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                KBWidgetSignedOut()
            }
        }
        .widgetURL(URL(string: "kidbox://widget/shopping"))
        .kbWidgetBackground(embedded)
    }
}
