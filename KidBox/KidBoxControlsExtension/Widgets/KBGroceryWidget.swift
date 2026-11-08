//
//  KBGroceryWidget.swift
//  KidBoxControlsExtension
//
//  Widget quadrato «Spesa»: quello che resta da comprare.
//

import SwiftUI
import WidgetKit

struct KBGroceryProvider: TimelineProvider {
    func placeholder(in context: Context) -> KBWidgetEntry { .init(date: .now, snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (KBWidgetEntry) -> Void) {
        completion(.init(date: .now, snapshot: KBWidgetStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KBWidgetEntry>) -> Void) {
        let entry = KBWidgetEntry(date: .now, snapshot: KBWidgetStore.read())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

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

struct KBGroceryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KidBoxGroceryWidget", provider: KBGroceryProvider()) { entry in
            KBGroceryWidgetView(entry: entry)
        }
        .configurationDisplayName("Lista della spesa")
        .description("Cosa resta da comprare.")
        .supportedFamilies([.systemSmall])
    }
}
