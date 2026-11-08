//
//  KBGroceryWidget.swift
//  KidBoxControlsExtension
//
//  Widget quadrato «Spesa»: quello che resta da comprare.
//

import SwiftUI
import WidgetKit

struct KBGroceryWidgetView: View {
    let entry: KBWidgetEntry

    var body: some View {
        Group {
            if let snap = entry.snapshot {
                VStack(alignment: .leading, spacing: 6) {
                    KBWidgetHeader(title: String(localized: "Spesa"), color: .kbGrocery,
                                   count: snap.grocery.count)
                    if snap.grocery.isEmpty {
                        KBWidgetMessage(systemImage: "cart", text: "Lista vuota", color: .kbGrocery)
                    } else {
                        ForEach(snap.grocery.prefix(5)) { item in
                            HStack(spacing: 6) {
                                Image(systemName: "circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Text(item.name)
                                    .font(.system(.footnote, design: .rounded).weight(.medium))
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
