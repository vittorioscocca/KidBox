//
//  FitnessPlanFormComponents.swift
//  KidBox
//
//  Controlli condivisi tra il wizard di onboarding e le impostazioni del piano:
//  le due schermate mostrano le stesse scelte e devono restare identiche.
//

import SwiftUI

/// Tinta del modulo Piano Fitness (stessa della card in Salute).
enum FitnessPlanTheme {
    static let tint = Color(red: 0.35, green: 0.62, blue: 0.88)
}

// MARK: - Capsule di scelta

struct FitnessChoiceChip: View {
    let title: LocalizedStringKey
    let systemImage: String?
    let selected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        selected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }
                Text(title)
                    .font(.footnote.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? FitnessPlanTheme.tint : KBTheme.primaryText(colorScheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(
                    selected
                        ? FitnessPlanTheme.tint.opacity(0.18)
                        : KBTheme.secondaryText(colorScheme).opacity(0.08)
                )
            )
            .overlay(
                Capsule().stroke(
                    selected
                        ? FitnessPlanTheme.tint
                        : KBTheme.secondaryText(colorScheme).opacity(0.28),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}

// MARK: - Layout a capo automatico

/// Equivalente di `FlowRow` su Android: le capsule vanno a capo da sole.
struct FitnessFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Giorni della settimana

/// Selettore dei giorni disponibili, ordinato dal primo giorno della settimana locale.
struct FitnessWeekdayPicker: View {
    @Binding var weekdays: Set<Int>

    @Environment(\.colorScheme) private var colorScheme

    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private func symbol(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        guard weekday >= 1, weekday <= symbols.count else { return "" }
        return symbols[weekday - 1].uppercased(with: kbDeviceLocale())
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                let selected = weekdays.contains(weekday)
                Button {
                    if selected {
                        weekdays.remove(weekday)
                    } else {
                        weekdays.insert(weekday)
                    }
                } label: {
                    Text(symbol(weekday))
                        .font(.footnote.weight(selected ? .bold : .regular))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundStyle(
                            selected ? FitnessPlanTheme.tint : KBTheme.primaryText(colorScheme)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    selected
                                        ? FitnessPlanTheme.tint.opacity(0.18)
                                        : KBTheme.secondaryText(colorScheme).opacity(0.08)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    selected
                                        ? FitnessPlanTheme.tint
                                        : KBTheme.secondaryText(colorScheme).opacity(0.24),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(symbol(weekday)))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Card

/// Sfondo card usato da tutte le schermate del Piano Fitness.
struct FitnessCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(KBTheme.cardBackground(colorScheme))
            .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
    }
}

extension View {
    /// Card standard del modulo: padding, larghezza piena, sfondo.
    func fitnessCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FitnessCardBackground())
    }
}

// MARK: - Utility di formattazione

enum FitnessPlanFormat {

    static func time(minutesFromMidnight: Int) -> String {
        var components = DateComponents()
        components.hour = minutesFromMidnight / 60
        components.minute = minutesFromMidnight % 60
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    static func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// "Settembre 2026", con l'iniziale maiuscola anche dove il locale non la mette.
    static func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        let text = formatter.string(from: date)
        return text.prefix(1).uppercased(with: kbDeviceLocale()) + text.dropFirst()
    }

    /// Simboli dei giorni della settimana a partire dal primo giorno locale.
    static var orderedWeekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7].uppercased(with: kbDeviceLocale()) }
    }

    static func weekdayShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    static func dayNumber(_ date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }
}
