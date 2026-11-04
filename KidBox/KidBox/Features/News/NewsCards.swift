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
    /// Il luogo dell'edizione accanto alla categoria: nelle salvate, dove non
    /// ci sono i titoli di paese, regione e città.
    var placeName: String? = nil
    /// La notizia è fra le salvate: il segnalibro è pieno.
    var isSaved: Bool = false
    let onOpen: () -> Void
    /// Il segnalibro in basso a destra; senza, niente segnalibro.
    var onToggleSave: (() -> Void)? = nil
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
                    if let placeName, !placeName.isEmpty {
                        Text(verbatim: "· \(placeName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let badge = keyDateBadge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(badgeColor))
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
                // La riga non deve finire sotto il segnalibro.
                .padding(.trailing, onToggleSave == nil ? 0 : 30)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(KBTheme.cardBackground(colorScheme)))
        }
        .buttonStyle(.plain)
        // Sopra la scheda e non dentro, come il «+» degli eventi: un pulsante
        // nell'etichetta di un altro si prenderebbe anche il tocco che apre.
        .overlay(alignment: .bottomTrailing) {
            if let onToggleSave { saveButton(onToggleSave) }
        }
    }

    private func saveButton(_ onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSaved ? KBTheme.bubbleTint : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSaved)
        .accessibilityLabel(isSaved ? Text("Togli dalle salvate") : Text("Salva notizia"))
    }

    /// Una scadenza passata (succede nelle salvate) non è più rossa.
    private var isPastDeadline: Bool {
        guard item.keyDateKind == "deadline", let day = NewsDates.date(item.keyDate) else { return false }
        return day < Calendar.current.startOfDay(for: Date())
    }

    private var badgeColor: Color {
        if isPastDeadline { return Color.gray.opacity(0.7) }
        return item.keyDateKind == "deadline" ? Color.red.opacity(0.85) : KBTheme.bubbleTint
    }

    private var keyDateBadge: String? {
        guard let day = NewsDates.dayMonth(item.keyDate) else { return nil }
        if isPastDeadline {
            return String(format: NSLocalizedString("Scaduto il %@", comment: "News: badge of a deadline already passed (saved news)"), day)
        }
        switch item.keyDateKind {
        case "deadline": return String(format: NSLocalizedString("Scade il %@", comment: "News: deadline badge"), day)
        case "start":    return String(format: NSLocalizedString("Dal %@", comment: "News: start date badge"), day)
        case "payment":  return String(format: NSLocalizedString("Pagamento il %@", comment: "News: payment date badge"), day)
        default:         return nil
        }
    }
}

/// Icona e testo affiancati come nella scheda Notizie. Dentro una List (le
/// salvate) lo stile automatico delle etichette riserva alle icone la colonna
/// larga delle righe di sistema e le ingrandisce; `labelReservedIconWidth`
/// non basta (l'icona esce dal margine). Visto nell'app-banco il 04/10/2026.
struct NewsCardLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
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

// MARK: - Attesa dell'edizione

/// La prima edizione del giorno si genera in circa 50 secondi: conto alla
/// rovescia e, sotto, gli argomenti che l'edizione cerca davvero. Le ricerche
/// girano sul server e il telefono non le vede in diretta: le frasi seguono
/// quello che chiedono i prompt (`functions/news/prompts.js`), non i singoli passi.
struct NewsPreparingCard: View {

    let pending: [String]
    let city: String
    let startedAt: Date

    @Environment(\.colorScheme) private var colorScheme

    private let expectedSeconds = 60.0
    private let secondsPerStep = 5.0
    private let accent = Color(red: 0.95, green: 0.38, blue: 0.10)

    private var hasCountry: Bool { pending.contains("country") }
    private var hasLocal: Bool { pending.contains("local") && !city.isEmpty }

    private var steps: [LocalizedStringKey] {
        let local: [LocalizedStringKey] = hasLocal
            ? ["Cerco le notizie di \(city)…", "Cerco eventi per famiglie entro 60 km…", "Controllo avvisi su acqua e luce…"]
            : []
        let filter: LocalizedStringKey = "Scarto le notizie vecchie e i doppioni…"
        guard hasCountry else { return local + [filter] }
        let country: [LocalizedStringKey] = [
            "Cerco bonus e agevolazioni per le famiglie…",
            "Controllo bollette, prezzi e tasse di casa…",
            "Controllo calendario, iscrizioni e mense…",
            "Cerco vaccinazioni, prevenzione e prodotti richiamati…",
            "Guardo le nuove leggi che toccano le famiglie…",
            "Cerco consigli su crescita ed educazione…",
        ]
        // Alternati: in un minuto compaiono sia il paese sia la città.
        var mixed: [LocalizedStringKey] = []
        for (i, step) in country.enumerated() {
            mixed.append(step)
            if i < local.count { mixed.append(local[i]) }
        }
        return mixed + [filter]
    }

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let left = max(0, Int((expectedSeconds - elapsed).rounded(.up)))
            let list = steps
            let index = Int(elapsed / secondsPerStep) % max(list.count, 1)

            HStack(alignment: .center, spacing: 14) {
                ring(left: left)
                VStack(alignment: .leading, spacing: 3) {
                    Group {
                        if left == 0 {
                            Text("Quasi pronte…")
                        } else if hasCountry {
                            Text("Sto cercando le notizie di oggi…")
                        } else {
                            Text("Sto cercando le notizie della tua zona e gli eventi vicini…")
                        }
                    }
                    .font(.subheadline.weight(.semibold))

                    Text(list[index])
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(accent)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                        .id(index)
                        .transition(.opacity)

                    Text("La prima edizione del giorno richiede circa un minuto. Puoi uscire: la ritrovi pronta.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .animation(.easeInOut(duration: 0.4), value: index)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(KBTheme.cardBackground(colorScheme)))
            .accessibilityElement(children: .combine)
        }
    }

    private func ring(left: Int) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5)
            if left > 0 {
                Circle()
                    .trim(from: 0, to: max(0.001, Double(left) / expectedSeconds))
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: left)
                Text(verbatim: "\(left) s")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .monospacedDigit()
            } else {
                ProgressView()
            }
        }
        .frame(width: 58, height: 58)
    }
}
