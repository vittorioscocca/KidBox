//
//  TravelItineraryDetailView.swift
//  KidBox
//

import SwiftUI

private let itineraryAccent = Color(red: 0.95, green: 0.38, blue: 0.1)

struct TravelItineraryDetailView: View {

    @Environment(\.colorScheme) private var colorScheme

    let overview: TravelItineraryOverview
    let legs: [KBTripLeg]
    var introduction: String? = nil
    var hotelsCount: Int = 0
    var restaurantsCount: Int = 0
    var activitiesCount: Int = 0
    var onHotelsTap: (() -> Void)? = nil
    var onRestaurantsTap: (() -> Void)? = nil
    var onActivitiesTap: (() -> Void)? = nil
    var onStopTap: ((TravelItineraryStopContext) -> Void)? = nil
    var onRegenerateDayTap: ((TravelItineraryDay) -> Void)? = nil
    var regeneratingDayId: String? = nil
    /// Padding orizzontale per testo e card sotto l’hero (l’immagine resta a tutta larghezza).
    var contentHorizontalPadding: CGFloat = 16

    private var cardFill: Color { KBTheme.cardBackground(colorScheme) }
    private var cardStroke: Color { KBTheme.separator(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            heroHeader
            VStack(alignment: .leading, spacing: 20) {
                budgetSummaryCard
                budgetCategoryCards
                if let introduction, !introduction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Introduzione")
                            .font(.title3.bold())
                        Text(introduction)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                itinerarySection
            }
            .padding(.horizontal, contentHorizontalPadding)
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            TravelTripCardBackgroundView(
                tripName: "Viaggio a \(overview.destinationTitle)",
                legs: legs
            )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 0))

            VStack(alignment: .leading, spacing: 4) {
                Text(overview.destinationTitle)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text(overview.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(20)
        }
    }

    // MARK: - Budget

    private var budgetSummaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOTALE STIMATO")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatMoney(overview.estimatedTotal))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("/ \(formatMoney(overview.budgetLimit)) budget")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var budgetCategoryCards: some View {
        VStack(spacing: 10) {
            tappableBudgetRow(
                emoji: "🛏️",
                title: "Hotel",
                subtitle: hotelSubtitle,
                action: hotelsCount > 0 ? "Vedi \(hotelsCount)" : nil,
                onTap: onHotelsTap
            )
            budgetRow(emoji: "✈️", title: "Voli", subtitle: formatMoney(overview.budget.flights), action: nil, showsChevron: false)
            HStack(spacing: 10) {
                tappableBudgetCompactCard(
                    emoji: "🍽️",
                    title: "Ristoranti",
                    amount: overview.budget.restaurants,
                    count: restaurantsCount,
                    onTap: onRestaurantsTap
                )
                tappableBudgetCompactCard(
                    emoji: "🎯",
                    title: "Attività",
                    amount: overview.budget.activities,
                    count: activitiesCount,
                    onTap: onActivitiesTap
                )
            }
        }
    }

    @ViewBuilder
    private func tappableBudgetRow(
        emoji: String,
        title: String,
        subtitle: String,
        action: String?,
        onTap: (() -> Void)?
    ) -> some View {
        if let onTap, action != nil {
            Button(action: onTap) {
                budgetRow(emoji: emoji, title: title, subtitle: subtitle, action: action, showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            budgetRow(emoji: emoji, title: title, subtitle: subtitle, action: action, showsChevron: false)
        }
    }

    @ViewBuilder
    private func tappableBudgetCompactCard(
        emoji: String,
        title: String,
        amount: Double,
        count: Int,
        onTap: (() -> Void)?
    ) -> some View {
        if let onTap, count > 0 {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(emoji).font(.title2)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(itineraryAccent)
                    }
                    Text(title).font(.headline)
                    Text(formatMoney(amount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(count) \(count == 1 ? "risultato" : "risultati")")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(itineraryAccent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        } else {
            budgetCompactCard(emoji: emoji, title: title, amount: amount)
        }
    }

    private var hotelSubtitle: String {
        let nights = max(overview.dayCount - 1, 1)
        return "~\(formatMoney(overview.budget.hotels)) per \(nights) \(nights == 1 ? "notte" : "notti")"
    }

    private func budgetRow(
        emoji: String,
        title: String,
        subtitle: String,
        action: String?,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Text(emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let action {
                HStack(spacing: 4) {
                    Text(action)
                        .font(.caption.weight(.semibold))
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                }
                .foregroundStyle(showsChevron ? itineraryAccent : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.primary.opacity(showsChevron ? 0.15 : 0.2), lineWidth: 1)
                )
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private func budgetCompactCard(emoji: String, title: String, amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emoji).font(.title2)
            Text(title).font(.headline)
            Text(formatMoney(amount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    // MARK: - Days

    private var itinerarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Il tuo itinerario di \(overview.dayCount) giorni")
                .font(.title2.bold())

            ForEach(overview.days) { day in
                daySection(day)
            }
        }
    }

    private func daySection(_ day: TravelItineraryDay) -> some View {
        let isRegenerating = regeneratingDayId == day.id
        return VStack(alignment: .leading, spacing: 12) {
            if day.dayIndex == 1 {
                Text("GIORNO 1 · ANTEPRIMA")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(KBTheme.inputBackground(colorScheme))
                    .clipShape(Capsule())
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.headline).font(.headline)
                    if !day.dateString.isEmpty {
                        Text(formattedDate(day.dateString))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let cost = day.dayCost {
                    Text(formatMoney(cost))
                        .font(.subheadline.weight(.semibold))
                }
                if onRegenerateDayTap != nil {
                    if isRegenerating {
                        ProgressView()
                            .scaleEffect(0.75)
                            .padding(.leading, 4)
                    } else {
                        Button {
                            onRegenerateDayTap?(day)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(itineraryAccent)
                        }
                        .padding(.leading, 4)
                    }
                }
            }

            ForEach(day.blocks) { block in
                periodBlockCard(block, day: day)
            }
        }
    }

    private func periodBlockCard(_ block: TravelItineraryPeriodBlock, day: TravelItineraryDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle().fill(block.period.accentColor).frame(width: 8, height: 8)
                Text("\(block.period.title) · \(block.stops.count) \(block.stops.count == 1 ? "tappa" : "tappe")")
                    .font(.caption.weight(.bold))
                Spacer()
                if !block.durationSummary.isEmpty || !block.costSummary.isEmpty {
                    Text([block.durationSummary, block.costSummary.isEmpty ? nil : "~\(block.costSummary) \(currencySymbol())"]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(block.stops.enumerated()), id: \.element.id) { index, stop in
                    let nextTitle = index + 1 < block.stops.count
                        ? block.stops[index + 1].title
                        : nil
                    stopRow(
                        stop,
                        day: day,
                        block: block,
                        isLast: index == block.stops.count - 1,
                        nextStopTitle: nextTitle
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private func stopRow(
        _ stop: TravelItineraryStop,
        day: TravelItineraryDay,
        block: TravelItineraryPeriodBlock,
        isLast: Bool,
        nextStopTitle: String?
    ) -> some View {
        let row = HStack(alignment: .top, spacing: 12) {
            Text(stop.time.isEmpty ? " " : stop.time)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            VStack(spacing: 0) {
                Text(stop.emoji)
                    .font(.title3)
                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(stop.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    if onStopTap != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(itineraryAccent)
                    }
                }
                if !stop.detail.isEmpty {
                    Text(stop.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, isLast ? 0 : 14)
        }

        return Group {
            if let onStopTap {
                Button {
                    onStopTap(stopContext(stop: stop, day: day, block: block, nextStopTitle: nextStopTitle))
                } label: {
                    row
                }
                .buttonStyle(.plain)
            } else {
                row
            }
        }
    }

    private func stopContext(
        stop: TravelItineraryStop,
        day: TravelItineraryDay,
        block: TravelItineraryPeriodBlock,
        nextStopTitle: String?
    ) -> TravelItineraryStopContext {
        let location = TravelItineraryBuilder.placeSearchLocationContext(
            dayLocation: day.location,
            destinationTitle: overview.destinationTitle
        )
        let metrics = Self.parseStopMetrics(stop.detail)
        return TravelItineraryStopContext(
            id: stop.id.uuidString,
            placeName: TravelItineraryBuilder.placeQueryName(title: stop.title, subtitle: stop.detail),
            locationContext: location,
            scheduleBadge: "GIORNO \(day.dayIndex) · \(block.period.title)",
            time: stop.time,
            staySummary: metrics.stay,
            costSummary: metrics.cost,
            nextStopTitle: nextStopTitle.map {
                TravelItineraryBuilder.placeQueryName(title: $0)
            }
        )
    }

    private static func parseStopMetrics(_ detail: String) -> (stay: String, cost: String) {
        let parts = detail
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return ("", "") }
        if parts.count == 1 {
            if parts[0].localizedCaseInsensitiveContains("€") || parts[0].localizedCaseInsensitiveContains("gratis") {
                return ("", parts[0])
            }
            return (parts[0], "")
        }
        return (parts[0], parts[1])
    }

    private func formatMoney(_ value: Double) -> String {
        let symbol = currencySymbol()
        return "\(Int(value.rounded())) \(symbol)"
    }

    private func currencySymbol() -> String {
        overview.currency.uppercased() == "EUR" ? "€" : overview.currency
    }

    private func formattedDate(_ iso: String) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "it_IT")
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: iso) else { return iso }
        fmt.dateStyle = .medium
        return fmt.string(from: date)
    }
}
