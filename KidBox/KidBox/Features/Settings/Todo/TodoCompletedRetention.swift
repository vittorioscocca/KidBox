//
//  TodoCompletedRetention.swift
//  KidBox
//
//  Per quanto tempo restano visibili i to-do segnati come fatti.
//
//  Solo su questo dispositivo: il to-do resta sul server e per gli altri
//  membri, nulla viene cancellato. Se un altro membro lo riapre, torna.
//

import SwiftUI

enum TodoCompletedRetention: String, CaseIterable, Identifiable {
    case hideNow = "hideNow"
    case week    = "week"
    case month   = "month"

    static let key = "kidbox.todo.completedRetention"
    static let `default`: TodoCompletedRetention = .week

    var id: Self { self }

    static var current: TodoCompletedRetention {
        UserDefaults.standard.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .default
    }

    var label: String {
        switch self {
        case .hideNow: return NSLocalizedString("Nascondi subito", comment: "Completed to-dos: hide immediately")
        case .week:    return NSLocalizedString("Mostra per una settimana", comment: "Completed to-dos: show for a week")
        case .month:   return NSLocalizedString("Mostra per un mese", comment: "Completed to-dos: show for a month")
        }
    }

    var icon: String {
        switch self {
        case .hideNow: return "eye.slash"
        case .week:    return "calendar.badge.clock"
        case .month:   return "calendar"
        }
    }

    /// Da quando in poi un to-do fatto si vede ancora; `nil` = mai.
    func cutoff(now: Date = Date()) -> Date? {
        let cal = Calendar.current
        switch self {
        case .hideNow: return nil
        case .week:    return cal.date(byAdding: .day, value: -7, to: now)
        case .month:   return cal.date(byAdding: .month, value: -1, to: now)
        }
    }

    /// I to-do aperti si vedono sempre; quelli fatti finché non scade la finestra.
    /// `keep` sono gli id appena chiusi a schermo: restano barrati finché non si
    /// esce dalla schermata, altrimenti con «Nascondi subito» sparirebbero sotto il dito.
    func shows(_ todo: KBTodoItem, cutoff: Date?, keep: Set<String> = []) -> Bool {
        guard todo.isDone else { return true }
        if keep.contains(todo.id) { return true }
        guard let cutoff else { return false }
        return (todo.doneAt ?? todo.updatedAt) >= cutoff
    }
}

struct TodoCompletedSettingsView: View {

    @AppStorage(TodoCompletedRetention.key) private var raw = TodoCompletedRetention.default.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var cardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }

    var body: some View {
        List {
            Section {
                ForEach(TodoCompletedRetention.allCases) { option in
                    Button {
                        raw = option.rawValue
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: option.icon)
                                .font(.title3)
                                .foregroundStyle(KBTheme.bubbleTint)
                                .frame(width: 28)
                            Text(option.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if raw == option.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(KBTheme.bubbleTint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(cardBackground)
                }
            } footer: {
                Text("Vale solo su questo dispositivo: i to-do fatti non vengono cancellati e gli altri membri continuano a vederli secondo la loro scelta.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("To-do completati")
        .navigationBarTitleDisplayMode(.inline)
    }
}
