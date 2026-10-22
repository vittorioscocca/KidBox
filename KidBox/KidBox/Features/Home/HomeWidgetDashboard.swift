//
//  HomeWidgetDashboard.swift
//  KidBox
//
//  Dashboard della Home quando c'è la barra laterale (iPad, iPhone Duo aperto,
//  Mac): le sezioni sono già tutte nella barra, quindi la Home non le ripete e
//  mostra invece cosa c'è dentro. Stessi riquadri della web app
//  (`KidboxWebApp/src/pages/Home.jsx`): intestazione che apre la sezione e
//  fino a quattro righe di anteprima. L'intestazione sceglie la sezione nella
//  barra laterale, così resta evidenziata come se la si fosse toccata lì.
//
//  Il piano fitness della web qui non c'è: vive su Firestore sotto
//  `users/{uid}` e non in SwiftData, e la Home non fa letture di rete.
//

import SwiftUI
import SwiftData

struct HomeWidgetDashboard: View {
    let familyId: String
    let onOpen: (SidebarSection) -> Void

    @Query private var events: [KBCalendarEvent]
    @Query private var todos: [KBTodoItem]
    @Query private var groceries: [KBGroceryItem]
    @Query private var notes: [KBNote]
    @Query private var recentExpenses: [KBExpense]
    @Query private var monthExpenses: [KBExpense]
    @Query private var photos: [KBFamilyPhoto]

    @StateObject private var locationObserver = LocationSharingObserver()

    /// Due colonne quando c'è posto (iPad in orizzontale, Mac), una sola sul
    /// Duo o sull'iPad stretto.
    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)]

    init(familyId: String, onOpen: @escaping (SidebarSection) -> Void) {
        self.familyId = familyId
        self.onOpen = onOpen

        let fid = familyId
        let monthStart = Calendar.current.dateInterval(of: .month, for: Date())?.start
            ?? Date.distantPast

        _events = Query(filter: #Predicate<KBCalendarEvent> {
            $0.familyId == fid && !$0.isDeleted
        }, sort: [SortDescriptor(\KBCalendarEvent.startDate)])

        _todos = Query(filter: #Predicate<KBTodoItem> {
            $0.familyId == fid && !$0.isDeleted && !$0.isDone
        })

        _groceries = Query(filter: #Predicate<KBGroceryItem> {
            $0.familyId == fid && !$0.isDeleted && !$0.isPurchased
        }, sort: [SortDescriptor(\KBGroceryItem.createdAt, order: .reverse)])

        _notes = Query(filter: #Predicate<KBNote> {
            $0.familyId == fid && !$0.isDeleted
        }, sort: [SortDescriptor(\KBNote.updatedAt, order: .reverse)])

        var recent = FetchDescriptor<KBExpense>(
            predicate: #Predicate<KBExpense> { $0.familyId == fid && !$0.isDeleted },
            sortBy: [SortDescriptor(\KBExpense.date, order: .reverse)]
        )
        recent.fetchLimit = 4
        _recentExpenses = Query(recent)

        _monthExpenses = Query(filter: #Predicate<KBExpense> {
            $0.familyId == fid && !$0.isDeleted && $0.date >= monthStart
        })

        // Le miniature sono base64 dentro il modello: se ne caricano tre, non l'album.
        var photoDescriptor = FetchDescriptor<KBFamilyPhoto>(
            predicate: #Predicate<KBFamilyPhoto> { $0.familyId == fid && !$0.isDeleted },
            sortBy: [SortDescriptor(\KBFamilyPhoto.takenAt, order: .reverse)]
        )
        photoDescriptor.fetchLimit = 3
        _photos = Query(photoDescriptor)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            upcomingWidget
            todosWidget
            groceryWidget
            notesWidget
            expensesWidget
            photosWidget
            locationWidget
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Riquadri

    private var upcomingWidget: some View {
        let items = upcoming
        return HomeWidget(id: .calendar, title: "Prossimi impegni", badge: nil,
                          isEmpty: items.isEmpty) { open(.calendar) } content: {
            ForEach(items) { occurrence in
                HomeWidgetRow(title: occurrence.event.title,
                              meta: Self.dayLabel(occurrence.startDate, allDay: occurrence.event.isAllDay)) {
                    Circle()
                        .fill(Color(hex: occurrence.event.category.color) ?? .gray)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }

    private var todosWidget: some View {
        let open = openTodos
        return HomeWidget(id: .todo, title: "Da fare", badge: open.isEmpty ? nil : "\(open.count)",
                          isEmpty: open.isEmpty) { self.open(.todo) } content: {
            ForEach(open.prefix(4)) { todo in
                HomeWidgetRow(title: todo.title,
                              meta: todo.dueAt.map { Self.dayLabel($0, allDay: !todo.hasDueTime) }) {
                    Image(systemName: "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var groceryWidget: some View {
        HomeWidget(id: .shopping, title: "Lista della spesa",
                   badge: groceries.isEmpty ? nil : "\(groceries.count)",
                   isEmpty: groceries.isEmpty) { open(.shopping) } content: {
            ForEach(groceries.prefix(4)) { item in
                HomeWidgetRow(title: item.name, meta: item.category) {
                    Image(systemName: "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var notesWidget: some View {
        let latest = visibleNotes
        return HomeWidget(id: .note, title: "Note recenti", badge: nil,
                          isEmpty: latest.isEmpty) { open(.note) } content: {
            ForEach(latest) { note in
                VStack(alignment: .leading, spacing: 2) {
                    let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(title.isEmpty ? String(localized: "Senza titolo") : title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(NoteHtmlSanitizer.plainText(from: note.body, maxInputLength: 400)
                        .trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var expensesWidget: some View {
        let total = monthExpenses.reduce(0) { $0 + $1.amount }
        return HomeWidget(id: .expenses, title: "Spese recenti",
                          badge: total > 0 ? Self.amount(total) : nil,
                          isEmpty: recentExpenses.isEmpty) { open(.expenses) } content: {
            ForEach(recentExpenses) { expense in
                HomeWidgetRow(title: expense.title, meta: Self.amount(expense.amount), strongMeta: true) {
                    Image(systemName: "eurosign.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.mint)
                }
            }
        }
    }

    private var photosWidget: some View {
        HomeWidget(id: .photos, title: "Ultime foto", badge: nil,
                   isEmpty: photos.isEmpty) { open(.photos) } content: {
            HStack(spacing: 6) {
                ForEach(photos) { photo in
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                        if let data = photo.thumbnailData, let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var locationWidget: some View {
        HomeWidget(id: .location, title: "Posizione", badge: nil, isEmpty: false) {
            open(.location)
        } content: {
            if locationObserver.isSharing {
                Label("Stai condividendo la posizione", systemImage: "circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                Text("Non stai condividendo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Dati

    private var currentUid: String? { KBUid.current }

    /// I prossimi quattro, ricorrenze comprese: un evento settimanale iniziato
    /// mesi fa è comunque in agenda. Un anno di orizzonte, come sulla web.
    private var upcoming: [KBEventOccurrence] {
        let now = Date()
        let horizon = Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now
        let window = DateInterval(start: now, end: horizon)
        let uid = currentUid
        return events
            .filter { $0.isVisible(to: uid) }
            .flatMap { $0.occurrences(in: window) }
            .filter { $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(4)
            .map { $0 }
    }

    /// Prima chi ha una scadenza, poi per data: in Home conta cosa scade prima.
    private var openTodos: [KBTodoItem] {
        let uid = currentUid
        return todos
            .filter { $0.isVisible(to: uid) }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var visibleNotes: [KBNote] {
        let uid = currentUid
        return Array(notes.filter { $0.isVisible(to: uid) }.prefix(3))
    }

    // MARK: - Tap

    /// Stessi effetti della tessera e della riga corrispondenti
    /// (`HomeSummaryGrid`, `HomeCategoryList`): chi apre la sezione da qui
    /// azzera i contatori come da lì.
    private func open(_ id: HomeCardID) {
        HomeShortcutUsage.shared.record(id.rawValue)
        if let key = HomeCatalog.meta(id).usageKey {
            FABUsageTracker.shared.record(key)
        }
        KBLog.navigation.kbDebug("Home: tap widget \(id.rawValue)")

        let fid = familyId
        switch id {
        case .shopping:
            Task { @MainActor in
                BadgeManager.shared.clearShopping()
                await CountersService.shared.reset(familyId: fid, field: .shopping)
            }
        case .expenses:
            Task { @MainActor in
                BadgeManager.shared.clearExpenses()
                await CountersService.shared.reset(familyId: fid, field: .expenses)
            }
        case .note:
            Task { @MainActor in
                BadgeManager.shared.clearNotes()
                await CountersService.shared.reset(familyId: fid, field: .notes)
            }
        default:
            break
        }

        switch id {
        case .calendar:  onOpen(.calendar)
        case .todo:      onOpen(.todo)
        case .shopping:  onOpen(.shopping)
        case .note:      onOpen(.notes)
        case .expenses:  onOpen(.expenses)
        case .photos:    onOpen(.photos)
        case .location:  onOpen(.location)
        default:         break
        }
    }

    // MARK: - Etichette

    private static func amount(_ value: Double) -> String {
        value.formatted(.currency(code: "EUR").locale(kbDeviceLocale()))
    }

    /// "oggi 08:00", "domani", "ven 05/09".
    private static func dayLabel(_ date: Date, allDay: Bool) -> String {
        let calendar = Calendar.current
        if allDay {
            if calendar.isDateInToday(date) { return String(localized: "oggi") }
            if calendar.isDateInTomorrow(date) { return String(localized: "domani") }
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits)
                .locale(kbDeviceLocale()))
        }
        let time = date.formatted(.dateTime.hour().minute().locale(kbDeviceLocale()))
        if calendar.isDateInToday(date) { return String(localized: "oggi \(time)") }
        if calendar.isDateInTomorrow(date) { return String(localized: "domani \(time)") }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits)
            .locale(kbDeviceLocale()))
    }
}

// MARK: - Riquadro

/// Intestazione che apre la sezione (icona, titolo, badge, «Vedi tutto ›») e
/// sotto le righe di anteprima, o «Niente da mostrare».
private struct HomeWidget<Content: View>: View {
    let id: HomeCardID
    let title: LocalizedStringKey
    let badge: String?
    let isEmpty: Bool
    let onOpen: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        let meta = HomeCatalog.meta(id)
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Image(systemName: meta.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(meta.tint)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(meta.tint.opacity(0.15)))
                            .foregroundStyle(meta.tint)
                    }
                    Spacer(minLength: 4)
                    Text("Vedi tutto ›")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                if isEmpty {
                    Text("Niente da mostrare")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    content()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
        )
    }
}

/// Una riga di anteprima: segno a sinistra, titolo, e a destra data o importo.
private struct HomeWidgetRow<Leading: View>: View {
    let title: String
    let meta: String?
    var strongMeta = false
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        HStack(spacing: 8) {
            leading()
                .frame(width: 16)
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let meta {
                Text(meta)
                    .font(.footnote.weight(strongMeta ? .semibold : .regular))
                    .foregroundStyle(strongMeta ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
        }
    }
}
