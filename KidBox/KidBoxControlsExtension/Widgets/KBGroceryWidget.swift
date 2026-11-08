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

    var body: some View {
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
