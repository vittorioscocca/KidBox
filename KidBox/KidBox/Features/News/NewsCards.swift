//
//  NewsCards.swift
//  KidBox
//
//  Le schede della pagina Notizie: notizia, evento, offerta su misura. Solo
//  SwiftUI e i modelli, senza Firebase: si provano da sole in un'app-banco
//  (memoria «Verifica UI iOS»).
//

import SwiftUI

// MARK: - Schede

/// Paese, regione, città: i tre gruppi dell'edizione, in quest'ordine.
struct NewsLevelGroup: Identifiable {
    let id: String
    let title: String
    let symbol: String
}

struct NewsItemCard: View {
    let item: NewsItem
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let cat = item.newsCategory {
                        Label(cat.title, systemImage: cat.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(cat.tint)
                    }
                    Spacer()
                    if let badge = keyDateBadge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(item.keyDateKind == "deadline" ? Color.red.opacity(0.85) : KBTheme.bubbleTint))
                    }
                }
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                if let action = item.action, !action.isEmpty {
                    Label {
                        Text(action)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(KBTheme.green)
                    }
                    .font(.footnote)
                    .foregroundStyle(.primary)
                }
                HStack(spacing: 4) {
                    Text(item.source)
                    if let date = NewsDates.dayMonth(item.publishedAt) {
                        Text(verbatim: "·")
                        Text(verbatim: date)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(KBTheme.cardBackground(colorScheme)))
        }
        .buttonStyle(.plain)
    }

    private var keyDateBadge: String? {
        guard let day = NewsDates.dayMonth(item.keyDate) else { return nil }
        switch item.keyDateKind {
        case "deadline": return String(format: NSLocalizedString("Scade il %@", comment: "News: deadline badge"), day)
        case "start":    return String(format: NSLocalizedString("Dal %@", comment: "News: start date badge"), day)
        case "payment":  return String(format: NSLocalizedString("Pagamento il %@", comment: "News: payment date badge"), day)
        default:         return nil
        }
    }
}

struct NewsEventCard: View {
    let event: NewsEvent
    /// Un evento con lo stesso titolo e lo stesso giorno c'è già nel calendario
    /// KidBox: il «+» diventa una spunta.
    var isInCalendar: Bool = false
    let onOpen: () -> Void
    /// Il «+» in alto a destra: apre «Nuovo evento» già compilato.
    var onAdd: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Text(verbatim: dayNumber)
                        .font(.title2.weight(.bold))
                    Text(verbatim: monthShort)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                }
                .foregroundStyle(NewsCategory.leisure.tint)
                .frame(width: 48, height: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(NewsCategory.leisure.tint.opacity(0.12)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if let place = event.place, !place.isEmpty {
                            Label(place, systemImage: "mappin")
                        }
                        if let km = event.distanceKm, km > 0 {
                            Text(verbatim: "· \(km) km")
                        }
                        if event.free == true {
                            Text("Gratis")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(KBTheme.green.opacity(0.18)))
                                .foregroundStyle(KBTheme.green)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let range = rangeLabel {
                        Text(verbatim: range)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let summary = event.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                // Il titolo non deve finire sotto il «+».
                .padding(.trailing, onAdd == nil ? 0 : 26)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(KBTheme.cardBackground(colorScheme)))
        }
        .buttonStyle(.plain)
        // Sopra la scheda e non dentro: un pulsante nell'etichetta di un altro
        // pulsante si prenderebbe anche il tocco che apre l'evento.
        .overlay(alignment: .topTrailing) {
            if let onAdd { addButton(onAdd) }
        }
    }

    @ViewBuilder
    private func addButton(_ onAdd: @escaping () -> Void) -> some View {
        let tint = isInCalendar ? KBTheme.green : NewsCategory.leisure.tint
        let mark = Image(systemName: isInCalendar ? "checkmark" : "plus")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(Circle().fill(tint.opacity(0.14)))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        Group {
            if isInCalendar {
                // La spunta non fa niente: il tocco passa alla scheda e apre
                // l'evento, come su Android.
                mark
                    .allowsHitTesting(false)
                    .accessibilityLabel(Text("Già nel calendario"))
            } else {
                Button(action: onAdd) { mark }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Aggiungi al calendario"))
            }
        }
        .padding(4)
    }

    private var start: Date? { NewsDates.date(event.startDate) }
    private var dayNumber: String { start.map { $0.formatted(.dateTime.day().locale(kbDeviceLocale())) } ?? "" }
    private var monthShort: String { start.map { $0.formatted(.dateTime.month(.abbreviated).locale(kbDeviceLocale())) } ?? "" }

    /// «sab 3 ott → dom 4 ott» quando dura più di un giorno.
    private var rangeLabel: String? {
        guard let end = event.endDate, end != event.startDate,
              let a = NewsDates.short(event.startDate), let b = NewsDates.short(end) else { return nil }
        return "\(a) → \(b)"
    }
}

struct NewsOfferCard: View {
    let offer: NewsOffer
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: offer.symbol)
                        .foregroundStyle(NewsCategory.economy.tint)
                    Text(offer.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                Text(offer.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                HStack {
                    if let saving = offer.saving, !saving.isEmpty {
                        Label(saving, systemImage: "arrow.down.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NewsCategory.economy.tint)
                    }
                    Spacer()
                    Text(offer.source)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(KBTheme.cardBackground(colorScheme))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(NewsCategory.economy.tint.opacity(0.35), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}
