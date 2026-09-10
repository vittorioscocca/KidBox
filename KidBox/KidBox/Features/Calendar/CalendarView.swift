//
//  CalendarView.swift
//  KidBox
//
//  Created by vscocca on 10/03/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import Combine

// MARK: - CalendarView

struct CalendarView: View {
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    @State private var sharePrefillTitle: String = ""
    @State private var sharePrefillNotes: String = ""
    @State private var sharePrefillDate: Date? = nil
    
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
    private var primaryText:   Color { .primary }
    private var secondaryText: Color { .secondary }
    private var accentPrimary: Color {
        colorScheme == .dark ? .white : .black
    }
    private var overlayScrim: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }
    
    @Query(
        sort: \KBCalendarEvent.startDate,
        order: .forward
    ) private var allEvents: [KBCalendarEvent]
    
    var familyId: String
    var highlightEventId: String? = nil
    
    private var events: [KBCalendarEvent] {
        let uid = Auth.auth().currentUser?.uid
        return allEvents.filter {
            $0.familyId == familyId && !$0.isDeleted && $0.isVisible(to: uid)
        }
    }
    
    private var datesWithEvents: Set<DateComponents> {
        Set(
            events.flatMap { event in
                calendarDayComponentsCoveredByEvent(event)
            }
        )
    }
    
    @State private var selectedDate = Date()
    @State private var addSheetDate: AddSheetDate?
    @State private var editingEvent: KBCalendarEvent?
    @State private var viewMode: CalendarViewMode = .month
    /// Evento già aperto dalla notifica. Una sola apertura: senza questo,
    /// chiudere la scheda la farebbe riaprire al primo aggiornamento della
    /// lista eventi. Equivale a `openedEventId` di `CalendarScreen` su Android.
    @State private var openedPushEventId: String? = nil
    /// Si sta aspettando che la sincronizzazione porti l'evento della notifica.
    /// Gemello di `waitingForEvent` su Android.
    @State private var isWaitingForPushEvent = false

    /// Wrapper Identifiable per presentare la sheet "nuovo evento" con `.sheet(item:)`,
    /// così la data iniziale viene letta sempre fresca (evita lo stale di `isPresented`).
    private struct AddSheetDate: Identifiable {
        let id = UUID()
        let date: Date
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Picker("Vista", selection: $viewMode) {
                    ForEach(CalendarViewMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider()
                
                switch viewMode {
                case .day, .week:
                    DayWeekView(
                        selectedDate: $selectedDate,
                        isWeek:       viewMode == .week,
                        events:       events,
                        onEditEvent:  { editingEvent = $0 },
                        onAddEvent:   { addSheetDate = AddSheetDate(date: $0) }
                    )
                case .year:
                    YearOverviewView(
                        year:            Calendar.current.component(.year, from: selectedDate),
                        datesWithEvents: datesWithEvents,
                        selectedDate:    $selectedDate,
                        onSelectDate: { date in
                            selectedDate = date
                            viewMode = .month
                        }
                    )
                case .month:
                    MonthDetailView(
                        selectedDate:    $selectedDate,
                        datesWithEvents: datesWithEvents,
                        events:          events,
                        cardBackground:  cardBackground,
                        familyId:        familyId,
                        onEditEvent:     { editingEvent = $0 },
                        onDeleteEvent:   { deleteEvent($0) },
                        onAddEvent:      { addSheetDate = AddSheetDate(date: $0) }
                    )
                }
            }
        }
        .kbRefreshable {
            await SyncCenter.shared.forceRefresh(modelContext: modelContext) {
                SyncCenter.shared.stopCalendarRealtime()
                SyncCenter.shared.startCalendarRealtime(familyId: familyId, modelContext: modelContext)
            }
        }
        .trackSectionPresence(.calendar, familyId: familyId)
        .navigationTitle("Calendario")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    addSheetDate = AddSheetDate(date: sharePrefillDate ?? selectedDate)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $addSheetDate) { wrapper in
            CalendarEventFormView(
                familyId: familyId,
                initialDate: wrapper.date,
                event: nil,
                prefillTitle: sharePrefillTitle
            )
            .environment(\.modelContext, modelContext)
        }
        .sheet(item: $editingEvent) { event in
            CalendarEventFormView(familyId: familyId, initialDate: event.startDate, event: event)
                .environment(\.modelContext, modelContext)
        }
        .onReceive(coordinator.$pendingShareEventDraft.compactMap { $0 }) { draft in
            KBLog.sync.kbInfo("CalendarView.onReceive: draft received title=\(draft.title)")
            coordinator.pendingShareEventDraft = nil
            sharePrefillTitle = draft.title
            sharePrefillNotes = draft.notes
            sharePrefillDate  = draft.startDate
            if let d = draft.startDate { selectedDate = d }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                addSheetDate = AddSheetDate(date: sharePrefillDate ?? selectedDate)
            }
        }
        // Attesa dell'evento arrivato da notifica. L'attesa vive QUI e non nel
        // coordinator: chi sa davvero se l'evento c'è è la `@Query` che disegna
        // questa schermata, non una lettura separata del contesto. È anche il
        // motivo per cui prima non si apriva nulla — il coordinator navigava
        // due volte sulla stessa rotta, la view veniva riusata senza un nuovo
        // `onAppear` e nessun trigger scattava. Come `CalendarScreen` su Android.
        .overlay {
            if isWaitingForPushEvent {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    HStack(spacing: 14) {
                        ProgressView()
                        Text("Apro l'evento…").font(.subheadline)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(radius: 12, y: 4)
                }
                .transition(.opacity)
                // Toccando fuori si rinuncia ad aspettare.
                .onTapGesture { isWaitingForPushEvent = false }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isWaitingForPushEvent)
        // `events.count` copre l'evento che arriva dalla sync;
        // `highlightEventId` la notifica toccata con il calendario già aperto.
        .onChange(of: events.count) { _, _ in openPushEventIfNeeded() }
        .onChange(of: highlightEventId) { _, _ in startPushEventWait() }
        // Scaduta l'attesa si smette di bloccare l'utente: resta la vista mese.
        .task(id: highlightEventId) {
            guard highlightEventId?.isEmpty == false else { return }
            try? await Task.sleep(nanoseconds: Self.pushEventWaitTimeout)
            guard !Task.isCancelled, isWaitingForPushEvent else { return }
            isWaitingForPushEvent = false
            coordinator.globalBannerMessage = "Questo contenuto non è più disponibile."
            KBLog.navigation.kbError("CalendarView: evento da push mai arrivato eventId=\(highlightEventId ?? "nil")")
        }
        .onAppear {
            KBLog.sync.kbInfo("CalendarView.onAppear familyId=\(familyId)")
            Task {
                BadgeManager.shared.clearCalendar()
                await CountersService.shared.reset(familyId: familyId, field: .calendar)
            }
            startPushEventWait()
            if let pending = coordinator.pendingShareText {
                sharePrefillTitle = pending
                coordinator.pendingShareText = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    addSheetDate = AddSheetDate(date: sharePrefillDate ?? selectedDate)
                }
            }
            if let draft = coordinator.pendingShareEventDraft {
                coordinator.pendingShareEventDraft = nil
                sharePrefillTitle = draft.title
                sharePrefillNotes = draft.notes
                sharePrefillDate  = draft.startDate
                if let d = draft.startDate { selectedDate = d }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    addSheetDate = AddSheetDate(date: sharePrefillDate ?? selectedDate)
                }
            }
        }
    }
    
    /// Apre la scheda dell'evento arrivato da notifica, invece di fermarsi al
    /// calendario con l'evento evidenziato sotto: la notifica parla di QUEL
    /// evento, quindi si apre quello. Come `CalendarScreen` su Android.
    private func openPushEventIfNeeded() {
        guard let eid = highlightEventId, openedPushEventId != eid else { return }
        guard let match = events.first(where: { $0.id == eid }) else { return }
        openedPushEventId = eid
        isWaitingForPushEvent = false
        selectedDate = match.startDate
        // La sheet non si presenta durante la transizione di push: aspetta che
        // sia finita, come già fa qui sotto il draft condiviso.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            editingEvent = match
        }
        KBLog.navigation.kbInfo("CalendarView: apertura scheda evento da push eventId=\(eid)")
    }

    /// Accende l'attesa se la notifica punta a un evento non ancora in locale.
    private func startPushEventWait() {
        guard let eid = highlightEventId, !eid.isEmpty, openedPushEventId != eid else { return }
        if events.contains(where: { $0.id == eid }) {
            openPushEventIfNeeded()
        } else {
            isWaitingForPushEvent = true
        }
    }

    /// Oltre questo limite è più probabile che l'evento non arrivi mai
    /// (cancellato, non visibile) che non un ritardo della sincronizzazione.
    private static let pushEventWaitTimeout: UInt64 = 25_000_000_000

    private func deleteEvent(_ event: KBCalendarEvent) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let eventId = event.id
        let fid     = event.familyId
        if event.linkedHealthItemId != nil {
            KBHealthCalendarService.deleteLinkedHealthItem(
                event:        event,
                familyId:     fid,
                modelContext: modelContext
            )
        }
        event.isDeleted = true
        event.updatedAt = Date()
        event.updatedBy = uid
        SyncCenter.shared.enqueueCalendarDelete(
            eventId: eventId, familyId: fid, modelContext: modelContext)
        modelContext.delete(event)
        try? modelContext.save()
        Task { @MainActor in
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
        }
    }
}

// MARK: - View Mode

private enum CalendarViewMode: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .day:   return "Giorno"
        case .week:  return "Settimana"
        case .month: return "Mese"
        case .year:  return "Anno"
        }
    }
}

// MARK: - YearOverviewView

private struct YearOverviewView: View {
    
    let year:            Int
    let datesWithEvents: Set<DateComponents>
    @Binding var selectedDate: Date
    let onSelectDate: (Date) -> Void
    
    private let todayYear: Int = Calendar.current.component(.year, from: Date())
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    
    private var firstYear: Int { todayYear - 40 }
    private var lastYear:  Int { todayYear + 40 }
    
    private func anchorID(for y: Int) -> String { "year-\(y)" }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(firstYear...lastYear, id: \.self) { y in
                        Section {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(1...12, id: \.self) { month in
                                    MiniMonthView(
                                        year:            y,
                                        month:           month,
                                        datesWithEvents: datesWithEvents,
                                        selectedDate:    selectedDate,
                                        onSelectDate:    onSelectDate
                                    )
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                        } header: {
                            HStack(spacing: 8) {
                                Text(String(y))
                                    .font(.title2.weight(.bold))
                                if y == todayYear {
                                    Text("oggi")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor, in: Capsule())
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(.thinMaterial)
                            .id(anchorID(for: y))
                        }
                    }
                }
                .padding(.top, 4)
            }
            .onAppear {
                let targetYear = Calendar.current.component(.year, from: selectedDate)
                let clamped    = min(max(targetYear, firstYear), lastYear)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo(anchorID(for: clamped), anchor: .top)
                }
            }
        }
    }
}

// MARK: - MiniMonthView

private struct MiniMonthView: View {
    
    let year:            Int
    let month:           Int
    let datesWithEvents: Set<DateComponents>
    let selectedDate:    Date
    let onSelectDate:    (Date) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }
    
    private var monthDate: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }
    
    // ── FIX: DateFormatter rispetta il locale di sistema ──────────────────
    private func monthAbbrev(_ date: Date) -> String {
        let locale = appLocale()
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: date).capitalized(with: locale)
    }
    // ─────────────────────────────────────────────────────────────────────
    
    var body: some View {
        VStack(spacing: 4) {
            Text(monthAbbrev(monthDate))
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            
            let symbols = orderedWeekdayInitials()
            HStack(spacing: 0) {
                ForEach(symbols.indices, id: \.self) { i in
                    Text(symbols[i])
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            let days = calendarDays(for: monthDate)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7),
                spacing: 1
            ) {
                ForEach(days.indices, id: \.self) { i in
                    if let date = days[i] {
                        miniDayCell(date)
                    } else {
                        Color.clear.frame(height: 16)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardBackground)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelectDate(monthDate) }
    }
    
    @ViewBuilder
    private func miniDayCell(_ date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let isToday    = Calendar.current.isDateInToday(date)
        let comps      = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let hasEvent   = datesWithEvents.contains(comps)
        
        ZStack(alignment: .bottom) {
            Circle()
                .fill(isSelected ? Color.accentColor : isToday ? Color.accentColor.opacity(0.15) : Color.clear)
                .frame(width: 16, height: 16)
            
            Text(date, format: .dateTime.day())
                .font(.system(size: 8))
                .foregroundStyle(isSelected ? .white : isToday ? .accentColor : .primary)
            
            if hasEvent && !isSelected {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 3)
                    .offset(y: 6)
            }
        }
        .frame(height: 18)
        .onTapGesture { onSelectDate(date) }
    }
}

// MARK: - MonthDetailView

private struct MonthDetailView: View {
    
    @Binding var selectedDate:   Date
    let datesWithEvents:         Set<DateComponents>
    let events:                  [KBCalendarEvent]
    let cardBackground:          Color
    let familyId:                String
    let onEditEvent:             (KBCalendarEvent) -> Void
    let onDeleteEvent:           (KBCalendarEvent) -> Void
    let onAddEvent:              (Date) -> Void
    
    @State private var displayedMonth = Date()
    
    private var eventsOnSelectedDate: [KBCalendarEvent] {
        events.filter { eventOccursOnDay($0, day: selectedDate) }
    }
    
    // ── FIX: DateFormatter rispetta il locale di sistema ──────────────────
    private func monthTitle(_ date: Date) -> String {
        let locale = appLocale()
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date).capitalized(with: locale)
    }
    // ─────────────────────────────────────────────────────────────────────
    
    var body: some View {
        VStack(spacing: 0) {
            monthGrid
                .padding(.horizontal)
                .padding(.top, 8)
            
            Divider().padding(.vertical, 8)
            
            dayEventsList
        }
        .onAppear { displayedMonth = selectedDate }
        .onChange(of: selectedDate) { _, newVal in
            let selComps = Calendar.current.dateComponents([.year, .month], from: newVal)
            let curComps = Calendar.current.dateComponents([.year, .month], from: displayedMonth)
            if selComps != curComps { displayedMonth = newVal }
        }
    }
    
    private var monthGrid: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    displayedMonth = Calendar.current.date(
                        byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.left").foregroundStyle(.secondary)
                }
                Spacer()
                // ── FIX: usa monthTitle con DateFormatter ─────────────────
                Text(monthTitle(displayedMonth))
                    .font(.headline)
                // ─────────────────────────────────────────────────────────
                Spacer()
                Button {
                    displayedMonth = Calendar.current.date(
                        byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
            
            let weekdays = orderedWeekdayInitials()
            HStack(spacing: 0) {
                ForEach(weekdays.indices, id: \.self) { i in
                    Text(weekdays[i])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            let days = calendarDays(for: displayedMonth)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                spacing: 4
            ) {
                ForEach(days.indices, id: \.self) { i in
                    if let date = days[i] {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func dayCell(_ date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let isToday    = Calendar.current.isDateInToday(date)
        let comps      = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let hasEvent   = datesWithEvents.contains(comps)
        
        VStack(spacing: 2) {
            Text(date, format: .dateTime.day())
                .font(.callout.weight(isToday ? .bold : .regular))
                .frame(width: 32, height: 32)
                .background(Circle().fill(isSelected ? Color.accentColor : Color.clear))
                .foregroundStyle(isSelected ? .white : isToday ? .accentColor : .primary)
            
            Circle()
                .fill(hasEvent ? Color.accentColor.opacity(0.7) : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture { selectedDate = date }
    }
    
    private var dayEventsList: some View {
        Group {
            if eventsOnSelectedDate.isEmpty {
                KBEmptyStateView(
                    systemImage: "calendar",
                    title: "Nessun evento",
                    message: "Segna appuntamenti, impegni e ricorrenze della famiglia. Ogni evento ha una categoria e un colore, così capisci a colpo d'occhio di chi è la giornata piena.",
                    actionTitle: "Nuovo evento",
                    actionSystemImage: "plus.circle.fill",
                    action: { onAddEvent(selectedDate) }
                )
            } else {
                List {
                    ForEach(eventsOnSelectedDate) { event in
                        CalendarEventRow(event: event)
                            .contentShape(Rectangle())
                            .onTapGesture { onEditEvent(event) }
                            .listRowBackground(cardBackground)
                    }
                    .onDelete { indexSet in
                        for idx in indexSet { onDeleteEvent(eventsOnSelectedDate[idx]) }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

// MARK: - DayWeekView

/// Viste Giorno e Settimana: la stessa griglia oraria della web app
/// (`TimeGridView` di Calendario.jsx), con la barra di navigazione sopra.
private struct DayWeekView: View {

    @Binding var selectedDate: Date
    let isWeek:      Bool
    let events:      [KBCalendarEvent]
    let onEditEvent: (KBCalendarEvent) -> Void
    let onAddEvent:  (Date) -> Void

    private var days: [Date] {
        isWeek
        ? weekDays(containing: selectedDate)
        : [localizedCalendar().startOfDay(for: selectedDate)]
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
                .padding(.horizontal)
                .padding(.vertical, 6)

            Divider()

            TimeGridView(
                days:          days,
                events:        events,
                showsDayHeader: isWeek,
                onSelectEvent: onEditEvent,
                onCreateAt:    onAddEvent
            )
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 10) {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(spacing: 1) {
                Text(title).font(.headline)
                if !isWeek {
                    Text(weekdayTitle).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button("Oggi") { selectedDate = Date() }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)

            Button { shift(1) } label: {
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
    }

    private func shift(_ delta: Int) {
        let cal = localizedCalendar()
        let step = isWeek ? delta * 7 : delta
        if let next = cal.date(byAdding: .day, value: step, to: selectedDate) {
            selectedDate = next
        }
    }

    private var title: String {
        let locale = appLocale()
        let f = DateFormatter()
        f.locale = locale
        guard isWeek, let first = days.first, let last = days.last else {
            f.dateFormat = "d MMMM yyyy"
            return f.string(from: selectedDate).capitalized(with: locale)
        }
        let cal = localizedCalendar()
        let sameMonth = cal.isDate(first, equalTo: last, toGranularity: .month)
        f.dateFormat = sameMonth ? "d" : "d MMM"
        let start = f.string(from: first)
        f.dateFormat = "d MMMM yyyy"
        let end = f.string(from: last)
        return "\(start) – \(end)".capitalized(with: locale)
    }

    private var weekdayTitle: String {
        let locale = appLocale()
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f.string(from: selectedDate).capitalized(with: locale)
    }
}

// MARK: - TimeGridView

/// Griglia oraria condivisa da Giorno e Settimana. Gli eventi che si
/// sovrappongono vengono affiancati in colonne, come sulla web app.
private struct TimeGridView: View {

    let days:           [Date]
    let events:         [KBCalendarEvent]
    let showsDayHeader: Bool
    let onSelectEvent:  (KBCalendarEvent) -> Void
    let onCreateAt:     (Date) -> Void

    /// Ora di apertura della griglia: a mezzanotte non c'è niente da vedere.
    private static let initialHour = 7

    var body: some View {
        VStack(spacing: 0) {
            if showsDayHeader {
                dayHeader
                Divider()
            }

            allDayRow

            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        hourGutter
                        HStack(spacing: 1) {
                            ForEach(days, id: \.self) { day in
                                dayColumn(day)
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(hourAnchor(Self.initialHour), anchor: .top)
                    }
                }
            }
        }
    }

    private func hourAnchor(_ hour: Int) -> String { "hour-\(hour)" }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            // Altezza esplicita: un `Color` senza altezza si prende tutto lo
            // spazio verticale offerto e stacca l'intestazione dalla griglia.
            Color.clear.frame(width: kbHourGutterWidth, height: 1)
            HStack(spacing: 1) {
                ForEach(days, id: \.self) { day in
                    let isToday = Calendar.current.isDateInToday(day)
                    VStack(spacing: 2) {
                        Text(shortWeekdayLabel(day))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(day, format: .dateTime.day())
                            .font(.footnote.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Color.accentColor : .primary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.trailing, 4)
    }

    /// La riga "tutto il giorno" esiste solo se c'è qualcosa da metterci:
    /// vuota rubava un'altra striscia di spazio sopra la griglia.
    private var hasAllDayEvents: Bool {
        days.contains { !allDayEvents(on: $0).isEmpty }
    }

    @ViewBuilder
    private var allDayRow: some View {
        if hasAllDayEvents {
            HStack(alignment: .top, spacing: 0) {
                Text("tutto il g.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: kbHourGutterWidth, alignment: .trailing)
                    .padding(.trailing, 4)

                HStack(alignment: .top, spacing: 1) {
                    ForEach(days, id: \.self) { day in
                        VStack(spacing: 2) {
                            ForEach(allDayEvents(on: day)) { event in
                                Text(event.title)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        kbCategoryColor(event.category),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    )
                                    .onTapGesture { onSelectEvent(event) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
            .frame(minHeight: 22)
            .padding(.vertical, 4)
            .padding(.trailing, 4)

            Divider()
        }
    }

    private var hourGutter: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: kbHourGutterWidth, height: kbHourHeight, alignment: .topTrailing)
                    .padding(.trailing, 4)
                    .id(hourAnchor(hour))
            }
        }
    }

    @ViewBuilder
    private func dayColumn(_ day: Date) -> some View {
        let laid = layoutTimedEvents(timedEvents(on: day), day: day)

        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { _ in
                    Color.clear
                        .frame(height: kbHourHeight)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.18))
                                .frame(height: 0.5)
                        }
                }
            }

            GeometryReader { geo in
                ForEach(laid) { item in
                    let slot = geo.size.width / CGFloat(max(item.columns, 1))
                    eventBlock(item)
                        .frame(width: max(slot - 3, 20), height: item.height)
                        .offset(x: slot * CGFloat(item.column) + 1.5, y: item.top)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: kbHourHeight * 24)
        .contentShape(Rectangle())
        // Doppio tocco su uno spazio vuoto: nuovo evento a quell'ora, come il
        // doppio click della web app.
        .onTapGesture(count: 2) { location in
            let hour = min(max(Int(location.y / kbHourHeight), 0), 23)
            let cal  = localizedCalendar()
            let base = cal.startOfDay(for: day)
            onCreateAt(cal.date(byAdding: .hour, value: hour, to: base) ?? base)
        }
    }

    @ViewBuilder
    private func eventBlock(_ item: TimedEventLayout) -> some View {
        let color = kbCategoryColor(item.event.category)
        VStack(alignment: .leading, spacing: 1) {
            Text(item.event.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(item.height > 32 ? 2 : 1)
            if item.height > 32 {
                Text("\(item.event.startDate.formatted(date: .omitted, time: .shortened)) - \(item.event.endDate.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.26))
        .overlay(alignment: .leading) {
            Rectangle().fill(color).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onSelectEvent(item.event) }
    }

    private func timedEvents(on day: Date) -> [KBCalendarEvent] {
        events.filter { !$0.isAllDay && eventOccursOnDay($0, day: day) }
    }

    private func allDayEvents(on day: Date) -> [KBCalendarEvent] {
        events.filter { $0.isAllDay && eventOccursOnDay($0, day: day) }
    }

    private func shortWeekdayLabel(_ date: Date) -> String {
        let locale = appLocale()
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date).capitalized(with: locale)
    }
}

// MARK: - Time grid layout

/// Altezza di un'ora nella griglia: gemella di `HOUR_HEIGHT` in calendarUtils.js.
fileprivate let kbHourHeight: CGFloat = 52
fileprivate let kbHourGutterWidth: CGFloat = 42

fileprivate struct TimedEventLayout: Identifiable {
    let event:   KBCalendarEvent
    let top:     CGFloat
    let height:  CGFloat
    let column:  Int
    let columns: Int
    var id: String { event.id }
}

/// Posizione, altezza e colonna di ogni evento a orario dentro un giorno.
/// Porting di `layoutOverlaps` (calendarUtils.js): gli eventi che si
/// sovrappongono si dividono la larghezza invece di coprirsi.
fileprivate func layoutTimedEvents(_ events: [KBCalendarEvent], day: Date) -> [TimedEventLayout] {
    struct Box {
        let event:  KBCalendarEvent
        let top:    CGFloat
        let height: CGFloat
    }

    let dayStart = localizedCalendar().startOfDay(for: day)
    let boxes: [Box] = events.map { event in
        let start = min(event.startDate, event.endDate)
        let end   = max(event.startDate, event.endDate)
        // Un evento su più giorni viene tagliato agli estremi del giorno, così
        // si vede su ognuno di essi.
        let from = min(max(start.timeIntervalSince(dayStart) / 60, 0), 1440)
        let to   = min(max(end.timeIntervalSince(dayStart) / 60, from + 15), 1440)
        return Box(
            event:  event,
            top:    CGFloat(from / 60) * kbHourHeight,
            height: max(CGFloat((to - from) / 60) * kbHourHeight, 18)
        )
    }
    .sorted { $0.top < $1.top }

    var result: [TimedEventLayout] = []

    func flush(_ group: [Box]) {
        guard !group.isEmpty else { return }
        var columnEnds: [CGFloat] = []
        var assigned:   [(Box, Int)] = []
        for item in group {
            let free = columnEnds.firstIndex { item.top >= $0 }
            let col: Int
            if let free {
                col = free
            } else {
                columnEnds.append(0)
                col = columnEnds.count - 1
            }
            columnEnds[col] = item.top + item.height
            assigned.append((item, col))
        }
        let total = max(columnEnds.count, 1)
        result.append(contentsOf: assigned.map {
            TimedEventLayout(
                event: $0.0.event, top: $0.0.top, height: $0.0.height,
                column: $0.1, columns: total
            )
        })
    }

    var group:    [Box]   = []
    var groupEnd: CGFloat = -1
    for item in boxes {
        if !group.isEmpty, item.top >= groupEnd {
            flush(group)
            group = []
            groupEnd = -1
        }
        group.append(item)
        groupEnd = max(groupEnd, item.top + item.height)
    }
    flush(group)

    return result
}

fileprivate func kbCategoryColor(_ category: KBEventCategory) -> Color {
    Color(hex: category.color) ?? .accentColor
}

/// I sette giorni della settimana che contiene `date`, a partire da lunedì.
fileprivate func weekDays(containing date: Date) -> [Date] {
    let cal   = localizedCalendar()
    let start = cal.startOfDay(for: date)
    let diff  = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
    let first = cal.date(byAdding: .day, value: -diff, to: start) ?? start
    return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
}

// MARK: - Shared helpers

// Calendario con primo giorno = lunedì e locale di sistema
// I shortWeekdaySymbols usano il locale corrente → italiano se il sistema è in italiano
fileprivate func appLocale() -> Locale {
    kbDeviceLocale()
}

fileprivate func localizedCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.locale = appLocale()
    cal.firstWeekday = 2   // lunedì
    return cal
}

// Iniziali dei giorni ruotate su firstWeekday: shortWeekdaySymbols parte
// SEMPRE da domenica e senza rotazione le intestazioni risultano sfalsate
// di una colonna rispetto alla griglia (che parte da lunedì).
fileprivate func orderedWeekdayInitials() -> [String] {
    let cal = localizedCalendar()
    let raw = cal.shortWeekdaySymbols
    let shift = cal.firstWeekday - 1
    return (Array(raw[shift...]) + Array(raw[..<shift]))
        .map { String($0.prefix(1)).uppercased(with: appLocale()) }
}

fileprivate func calendarDayComponentsCoveredByEvent(_ event: KBCalendarEvent) -> [DateComponents] {
    let calendar = Calendar.current
    let startDay = calendar.startOfDay(for: min(event.startDate, event.endDate))
    let endDay = calendar.startOfDay(for: max(event.startDate, event.endDate))

    var result: [DateComponents] = []
    var cursor = startDay
    while cursor <= endDay {
        result.append(calendar.dateComponents([.year, .month, .day], from: cursor))
        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
    }
    return result
}

fileprivate func eventOccursOnDay(_ event: KBCalendarEvent, day: Date) -> Bool {
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: day)
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }

    let eventStart = min(event.startDate, event.endDate)
    let eventEnd = max(event.startDate, event.endDate)
    return eventStart < dayEnd && eventEnd >= dayStart
}

fileprivate func calendarDays(for month: Date) -> [Date?] {
    let cal   = localizedCalendar()
    let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
    let range = cal.range(of: .day, in: .month, for: start)!
    let first = cal.component(.weekday, from: start)
    let offset = (first - cal.firstWeekday + 7) % 7
    
    var days: [Date?] = Array(repeating: nil, count: offset)
    for day in range {
        days.append(cal.date(byAdding: .day, value: day - 1, to: start))
    }
    while days.count % 7 != 0 { days.append(nil) }
    // Sempre 6 righe (42 celle) per card uniformi nell'overview annuale.
    while days.count < 42 { days.append(nil) }
    return days
}

// MARK: - CalendarEventRow

private struct CalendarEventRow: View {
    let event: KBCalendarEvent
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(categoryColor(event.category))
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body)
                
                HStack(spacing: 6) {
                    if event.isAllDay {
                        Text("Tutto il giorno").foregroundStyle(.secondary)
                    } else {
                        Text(event.startDate, style: .time)
                        Text("–")
                        Text(event.endDate, style: .time)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                if let loc = event.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: event.category.systemImage)
                .foregroundStyle(categoryColor(event.category))
        }
        .padding(.vertical, 4)
    }
    
    private func categoryColor(_ cat: KBEventCategory) -> Color {
        Color(hex: cat.color) ?? .accentColor
    }
}

// MARK: - CalendarEventFormView

struct CalendarEventFormView: View {
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    
    let familyId:    String
    let initialDate: Date
    var event:       KBCalendarEvent?
    var prefillTitle: String = ""
    
    @Query private var members: [KBFamilyMember]
    
    @State private var title         = ""
    @State private var notes         = ""
    @State private var location      = ""
    @State private var startDate     = Date()
    @State private var endDate       = Date().addingTimeInterval(3600)
    /// Abilita l'allineamento automatico fine→inizio solo DOPO `populateFields()`:
    /// durante il caricamento le due date cambiano insieme, e correggerle in quel
    /// momento falserebbe i valori dell'evento appena aperto.
    @State private var dateAutoAdjustEnabled = false
    @State private var isAllDay      = false
    @State private var category      = KBEventCategory.family
    @State private var recurrence    = KBEventRecurrence.none
    @State private var hasReminder   = false
    @State private var reminderIndex = 1
    
    @State private var isVisibilitySheetPresented = false
    @State private var selectedVisibilityScope = KBVisibilityScope.family
    @State private var selectedVisibilityMemberIds: Set<String> = []
    @State private var showVisibilityLockedAlert = false
    /// Guards `populateFields()` so it only runs once (not again when returning from a navigation push).
    @State private var didPopulateFields = false
    @FocusState private var focusedField: FormField?
    
    private var isNewEvent: Bool { event == nil }
    
    private var currentUid: String? {
        Auth.auth().currentUser?.uid
    }
    
    private var canEditVisibility: Bool {
        guard let uid = currentUid else { return isNewEvent }
        if isNewEvent { return true }
        guard let ev = event else { return false }
        let cid = ev.createdBy.trimmingCharacters(in: .whitespacesAndNewlines)
        return cid.isEmpty || cid == uid
    }
    
    /// Membri selezionabili per visibilità "members" (escluso utente corrente).
    private var visibilitySelectableMembers: [KBFamilyMember] {
        members.filter { $0.userId != currentUid }
    }
    
    init(familyId: String, initialDate: Date, event: KBCalendarEvent? = nil, prefillTitle: String = "") {
        self.familyId = familyId
        self.initialDate = initialDate
        self.event = event
        self.prefillTitle = prefillTitle
        let fid = familyId
        _members = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted },
            sort: \KBFamilyMember.displayName
        )
    }
    
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
    private var primaryText:     Color { .primary }
    private var secondaryText:   Color { .secondary }
    private var buttonBg:        Color { colorScheme == .dark ? .white : .black }
    private var buttonFg:        Color { colorScheme == .dark ? .black : .white }
    
    private let reminderOptions: [(label: String, minutes: Int)] = [
        ("Al momento", 0),
        ("15 minuti prima", 15),
        ("30 minuti prima", 30),
        ("1 ora prima", 60),
        ("1 giorno prima", 1440)
    ]
    
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    private enum FormField: Hashable {
        case title
        case location
        case notes

        var scrollAnchorId: String {
            switch self {
            case .title: return "calendar-event-title"
            case .location: return "calendar-event-location"
            case .notes: return "calendar-event-notes"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()
                
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            
                            formCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    label("Titolo")
                                    TextField("Es. Visita pediatrica", text: $title)
                                        .font(.body)
                                        .focused($focusedField, equals: .title)
                                        .id(FormField.title.scrollAnchorId)
                                }
                                Divider()
                                VStack(alignment: .leading, spacing: 4) {
                                    label("Visibilità")
                                    eventVisibilityChipRow
                                }
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    label("Categoria")
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(KBEventCategory.allCases) { cat in
                                                categoryChip(cat)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                            
                            formCard {
                                Toggle(isOn: $isAllDay) {
                                    Label("Tutto il giorno", systemImage: "sun.max")
                                        .foregroundStyle(primaryText)
                                }
                                .tint(buttonBg)
                                
                                Divider()
                                
                                if isAllDay {
                                    datePicker("Data inizio", selection: $startDate, components: .date)
                                    Divider()
                                    datePicker("Data fine", selection: $endDate, components: .date)
                                } else {
                                    datePicker("Inizio", selection: $startDate, components: [.date, .hourAndMinute])
                                    Divider()
                                    datePicker("Fine", selection: $endDate, components: [.date, .hourAndMinute])
                                }
                                
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    label("Ricorrenza")
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(KBEventRecurrence.allCases) { r in
                                                recurrenceChip(r)
                                            }
                                        }
                                    }
                                }
                            }
                            
                            formCard {
                                Toggle(isOn: $hasReminder) {
                                    Label("Promemoria", systemImage: "bell")
                                        .foregroundStyle(primaryText)
                                }
                                .tint(buttonBg)
                                
                                if hasReminder {
                                    Divider()
                                    Picker("Avviso", selection: $reminderIndex) {
                                        ForEach(reminderOptions.indices, id: \.self) { i in
                                            Text(reminderOptions[i].label).tag(i)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                            
                            formCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    label("Luogo")
                                    HStack {
                                        Image(systemName: "mappin.and.ellipse")
                                            .foregroundStyle(secondaryText)
                                        TextField("Indirizzo o luogo", text: $location)
                                            .focused($focusedField, equals: .location)
                                            .id(FormField.location.scrollAnchorId)
                                    }
                                }
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    label("Note")
                                    TextField("Aggiungi note…", text: $notes, axis: .vertical)
                                        .lineLimit(3...)
                                        .focused($focusedField, equals: .notes)
                                        .id(FormField.notes.scrollAnchorId)
                                }
                            }
                            
                            Button(action: save) {
                                Text(event == nil ? "Aggiungi evento" : "Salva modifiche")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(buttonFg)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(buttonBg.opacity(canSave ? 1 : 0.35), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSave)
                            .padding(.horizontal)
                            
                            Spacer().frame(height: focusedField == nil ? 20 : 280)
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: focusedField) { _, field in
                        guard let field else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(field.scrollAnchorId, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle(event == nil ? "Nuovo evento" : "Modifica evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                        .foregroundStyle(primaryText)
                }
            }
            .onAppear {
                guard !didPopulateFields else { return }
                didPopulateFields = true
                populateFields()
                // Sul giro successivo del runloop: `onChange` scatta dopo
                // l'aggiornamento della vista, quindi abilitarlo subito lo
                // farebbe reagire alle assegnazioni di `populateFields`.
                DispatchQueue.main.async { dateAutoAdjustEnabled = true }
            }
            // Un evento non può finire prima di iniziare.
            //
            // Spostando l'INIZIO si trascina la fine mantenendo la durata:
            // cambiando la data di inizio senza toccare la fine si otteneva
            // altrimenti un evento che comincia dopo essere finito. Toccando
            // invece direttamente la FINE la si blocca all'inizio, che è il
            // minimo sensato. Il secondo `onChange` non innesca un ciclo: dopo
            // la correzione la condizione è già soddisfatta.
            .onChange(of: startDate) { oldStart, newStart in
                guard dateAutoAdjustEnabled else { return }
                let duration = max(0, endDate.timeIntervalSince(oldStart))
                endDate = newStart.addingTimeInterval(duration)
            }
            .onChange(of: endDate) { _, newEnd in
                guard dateAutoAdjustEnabled else { return }
                if newEnd < startDate { endDate = startDate }
            }
            // Push the picker within the SAME NavigationStack instead of a nested sheet/fullScreenCover.
            // This avoids the iOS "sheet-in-sheet" problem where a second presentation inside
            // an already-presented sheet silently fails.
            .navigationDestination(isPresented: $isVisibilitySheetPresented) {
                VisibilityPickerSheet(
                    selectedScope: $selectedVisibilityScope,
                    selectedMemberIds: $selectedVisibilityMemberIds,
                    members: visibilitySelectableMembers,
                    currentUid: currentUid,
                    scopeSectionTitle: "Chi può vedere questo evento",
                    embedded: true
                ) { scope, ids in
                    selectedVisibilityScope = scope
                    selectedVisibilityMemberIds = ids
                    // Pop the navigation push without calling dismiss() (which would risk
                    // dismissing the entire CalendarEventFormView sheet on some iOS versions).
                    isVisibilitySheetPresented = false
                }
            }
        }
        .alert("Visibilità bloccata", isPresented: $showVisibilityLockedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Solo chi ha creato l’evento può modificare la visibilità.")
        }
    }
    
    @ViewBuilder
    private var eventVisibilityChipRow: some View {
        Button {
            if canEditVisibility {
                isVisibilitySheetPresented = true
            } else {
                showVisibilityLockedAlert = true
            }
        } label: {
            HStack {
                eventVisibilityChipLabel
                if canEditVisibility {
                    Spacer(minLength: 8)
                    Text("Cambia")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var eventVisibilityChipLabel: some View {
        Text(KBVisibilityScope.chipLabel(for: selectedVisibilityScope))
            .font(.custom("Nunito", size: 14))
            .foregroundStyle(primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(cardBackground.opacity(colorScheme == .dark ? 0.55 : 0.85))
            .overlay(
                Capsule()
                    .strokeBorder(primaryText.opacity(0.12), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
    
    @ViewBuilder
    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
        )
    }
    
    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(secondaryText)
            .textCase(.uppercase)
            .kerning(0.5)
    }
    
    @ViewBuilder
    private func datePicker(_ title: LocalizedStringKey, selection: Binding<Date>, components: DatePickerComponents) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(primaryText)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: components)
                .labelsHidden()
                .environment(\.locale, appLocale())
        }
    }

    @ViewBuilder
    private func recurrenceChip(_ value: KBEventRecurrence) -> some View {
        let isSelected = recurrence == value
        Button { recurrence = value } label: {
            Text(value.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? buttonBg : cardBackground)
                )
                .overlay(
                    Capsule().strokeBorder(primaryText.opacity(isSelected ? 0 : 0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func categoryChip(_ cat: KBEventCategory) -> some View {
        let isSelected = category == cat
        Button { category = cat } label: {
            Label(cat.label, systemImage: cat.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white : primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected
                              ? (Color(hex: cat.color) ?? .accentColor)
                              : cardBackground)
                        .shadow(color: .black.opacity(isSelected ? 0.15 : 0),
                                radius: 4, y: 2)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : primaryText.opacity(0.12),
                            lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.2), value: category)
    }
    
    private func populateFields() {
        if let e = event {
            title         = e.title
            notes         = e.notes    ?? ""
            location      = e.location ?? ""
            startDate     = e.startDate
            endDate       = e.endDate
            isAllDay      = e.isAllDay
            category      = e.category
            recurrence    = e.recurrence
            selectedVisibilityScope = KBVisibilityScope.normalized(e.visibilityScope)
            selectedVisibilityMemberIds = Set(e.visibilityMemberIds)
            if let mins = e.reminderMinutes {
                hasReminder   = true
                reminderIndex = reminderOptions.firstIndex(where: { $0.minutes == mins }) ?? 1
            }
        } else {
            startDate = Calendar.current.startOfDay(for: initialDate)
            endDate   = startDate.addingTimeInterval(3600)
            selectedVisibilityScope = KBVisibilityScope.family
            selectedVisibilityMemberIds = []
        }
        if event == nil && !prefillTitle.isEmpty {
            title = prefillTitle
        }
    }
    
    private func save() {
        let uid  = Auth.auth().currentUser?.uid ?? ""
        let now  = Date()
        let mins = hasReminder ? reminderOptions[reminderIndex].minutes : nil
        // Rete di sicurezza: i picker già impediscono una fine anteriore
        // all'inizio, ma qui si chiude comunque la porta a un evento salvato
        // con le date invertite.
        let safeEndDate = max(endDate, startDate)

        if let e = event {
            e.title           = title.trimmingCharacters(in: .whitespaces)
            e.notes           = notes.isEmpty    ? nil : notes
            e.location        = location.isEmpty ? nil : location
            e.startDate       = startDate
            e.endDate         = safeEndDate
            e.isAllDay        = isAllDay
            e.category        = category
            e.recurrence      = recurrence
            e.reminderMinutes = mins
            e.visibilityScope = KBVisibilityScope.normalized(selectedVisibilityScope)
            if selectedVisibilityScope == KBVisibilityScope.members {
                e.visibilityMemberIds = Array(selectedVisibilityMemberIds).sorted()
            } else {
                e.visibilityMemberIds = []
            }
            e.updatedAt       = now
            e.updatedBy       = uid
            e.syncState       = .pendingUpsert
            SyncCenter.shared.enqueueCalendarUpsert(
                eventId: e.id, familyId: familyId, modelContext: modelContext)
        } else {
            let isFirstCalendarEvent = ((try? modelContext.fetchCount(FetchDescriptor<KBCalendarEvent>(predicate: #Predicate<KBCalendarEvent> {
                $0.familyId == familyId && $0.isDeleted == false
            }))) ?? 0) == 0
            let newEvent = KBCalendarEvent(
                familyId:        familyId,
                title:           title.trimmingCharacters(in: .whitespaces),
                notes:           notes.isEmpty    ? nil : notes,
                location:        location.isEmpty ? nil : location,
                startDate:       startDate,
                endDate:         safeEndDate,
                isAllDay:        isAllDay,
                category:        category,
                recurrence:      recurrence,
                reminderMinutes: mins,
                visibilityScope: KBVisibilityScope.normalized(selectedVisibilityScope),
                visibilityMemberIds: selectedVisibilityScope == KBVisibilityScope.members
                    ? Array(selectedVisibilityMemberIds).sorted()
                    : [],
                createdAt:       now,
                updatedAt:       now,
                updatedBy:       uid,
                createdBy:       uid
            )
            newEvent.syncState = .pendingUpsert
            modelContext.insert(newEvent)
            SyncCenter.shared.enqueueCalendarUpsert(
                eventId: newEvent.id, familyId: familyId, modelContext: modelContext)
            AppAnalytics.contentCreated(type: "calendar")
            if isFirstCalendarEvent {
                AppAnalytics.featureFirstUse(feature: "calendar")
            }
        }
        
        try? modelContext.save()
        Task { @MainActor in
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
        }
        dismiss()
    }
}

// MARK: - Color hex

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.count == 6 { h = "FF" + h }
        guard h.count == 8, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red:     Double((val >> 16) & 0xFF) / 255,
            green:   Double((val >> 8)  & 0xFF) / 255,
            blue:    Double( val        & 0xFF) / 255,
            opacity: Double((val >> 24) & 0xFF) / 255
        )
    }
}
