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
    
    // MARK: Theming (identico a LoginView)
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
    
    // MARK: Data
    // @Query senza filtro su familyId (non supportato con var) → filtro locale
    @Query(
        sort: \KBCalendarEvent.startDate,
        order: .forward
    ) private var allEvents: [KBCalendarEvent]
    
    var familyId: String
    var highlightEventId: String? = nil
    
    private var events: [KBCalendarEvent] {
        allEvents.filter { $0.familyId == familyId && !$0.isDeleted }
    }
    
    private var datesWithEvents: Set<DateComponents> {
        Set(events.map {
            Calendar.current.dateComponents([.year, .month, .day], from: $0.startDate)
        })
    }
    
    // MARK: State
    @State private var selectedDate = Date()
    @State private var showAddSheet = false
    @State private var editingEvent: KBCalendarEvent?
    @State private var viewMode: CalendarViewMode = .month
    
    // MARK: Body
    
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
                        onDeleteEvent:   { deleteEvent($0) }
                    )
                }
            }
        }
        .navigationTitle("Calendario")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CalendarEventFormView(
                familyId: familyId,
                initialDate: sharePrefillDate ?? selectedDate,
                event: nil,
                prefillTitle: sharePrefillTitle,
            )
            .environment(\.modelContext, modelContext)
        }
        .sheet(item: $editingEvent) { event in
            CalendarEventFormView(familyId: familyId, initialDate: event.startDate, event: event)
                .environment(\.modelContext, modelContext)
        }
        .onReceive(coordinator.$pendingShareEventDraft.compactMap { $0 }) { draft in
            KBLog.sync.kbInfo("CalendarView.onReceive: draft received title=\(draft.title) — consuming and opening sheet")
            coordinator.pendingShareEventDraft = nil
            sharePrefillTitle = draft.title
            sharePrefillNotes = draft.notes
            sharePrefillDate  = draft.startDate
            if let d = draft.startDate { selectedDate = d }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                KBLog.sync.kbInfo("CalendarView.onReceive: showAddSheet = true")
                showAddSheet = true
            }
        }
        .onAppear {
            KBLog.sync.kbInfo("CalendarView.onAppear familyId=\(familyId) pendingDraft=\(coordinator.pendingShareEventDraft?.title ?? "nil")")
            // Azzera badge calendario
            Task {
                BadgeManager.shared.clearCalendar()
                await CountersService.shared.reset(familyId: familyId, field: .calendar)
            }
            // Deep link: seleziona il giorno dell'evento
            if let eid = highlightEventId,
               let match = events.first(where: { $0.id == eid }) {
                selectedDate = match.startDate
            }
            
            if let pending = coordinator.pendingShareText {
                sharePrefillTitle = pending
                coordinator.pendingShareText = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showAddSheet = true
                }
            }
            
            // Fallback: se onReceive ha già emesso prima che CalendarView
            // fosse montata (navigate avviene dopo il draft), leggiamo qui.
            if let draft = coordinator.pendingShareEventDraft {
                KBLog.sync.kbInfo("CalendarView.onAppear: consumed draft via fallback title=\(draft.title)")
                coordinator.pendingShareEventDraft = nil
                sharePrefillTitle = draft.title
                sharePrefillNotes = draft.notes
                sharePrefillDate  = draft.startDate
                if let d = draft.startDate { selectedDate = d }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    KBLog.sync.kbInfo("CalendarView.onAppear: showAddSheet = true (fallback)")
                    showAddSheet = true
                }
            } else {
                KBLog.sync.kbInfo("CalendarView.onAppear: no pending draft (onReceive handles if draft arrives late)")
            }
            
        }
        
    }
    
    
    
    private func deleteEvent(_ event: KBCalendarEvent) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Cattura i valori prima di cancellare il record
        let eventId  = event.id
        let fid      = event.familyId
        // Soft-delete su Firestore via outbox
        // Prima accoda l'op (che legge eventId/familyId dal record ancora vivo)
        event.isDeleted = true
        event.updatedAt = Date()
        event.updatedBy = uid
        SyncCenter.shared.enqueueCalendarDelete(
            eventId: eventId, familyId: fid, modelContext: modelContext)
        // Hard-delete locale subito: evita che il listener Firestore lo ricrochi
        modelContext.delete(event)
        try? modelContext.save()
        // Flush immediato verso Firestore
        Task { @MainActor in
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
        }
    }
}

// MARK: - View Mode

private enum CalendarViewMode: String, CaseIterable, Identifiable {
    case month, year
    var id: String { rawValue }
    var label: String {
        switch self {
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
    
    var body: some View {
        VStack(spacing: 4) {
            Text(monthDate, format: .dateTime.month(.abbreviated).locale(Locale(identifier: "it_IT")))
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            
            let symbols = italianCalendar.shortWeekdaySymbols.map { String($0.prefix(1)).uppercased() }
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
    
    @State private var displayedMonth = Date()
    
    private var eventsOnSelectedDate: [KBCalendarEvent] {
        events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: selectedDate) }
    }
    
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
                Text(displayedMonth, format: .dateTime.month(.wide).year().locale(Locale(identifier: "it_IT")))
                    .font(.headline)
                Spacer()
                Button {
                    displayedMonth = Calendar.current.date(
                        byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
            
            let weekdays = italianCalendar.shortWeekdaySymbols.map { String($0.prefix(1)).uppercased() }
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
                VStack {
                    Spacer()
                    Image(systemName: "calendar.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Nessun evento")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .padding(.top, 4)
                    Spacer()
                }
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

// MARK: - Shared helper

// Calendario italiano: prima settimana = lunedì, simboli in italiano
fileprivate var italianCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "it_IT")
    cal.firstWeekday = 2   // 1=domenica, 2=lunedì
    return cal
}()

fileprivate func calendarDays(for month: Date) -> [Date?] {
    let cal   = italianCalendar
    let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
    let range = cal.range(of: .day, in: .month, for: start)!
    let first = cal.component(.weekday, from: start)
    let offset = (first - cal.firstWeekday + 7) % 7
    
    var days: [Date?] = Array(repeating: nil, count: offset)
    for day in range {
        days.append(cal.date(byAdding: .day, value: day - 1, to: start))
    }
    while days.count % 7 != 0 { days.append(nil) }
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
    
    @State private var title         = ""
    @State private var notes         = ""
    @State private var location      = ""
    @State private var startDate     = Date()
    @State private var endDate       = Date().addingTimeInterval(3600)
    @State private var isAllDay      = false
    @State private var category      = KBEventCategory.family
    @State private var recurrence    = KBEventRecurrence.none
    @State private var hasReminder   = false
    @State private var reminderIndex = 1
    
    // MARK: Theming (identico a LoginView)
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
    private var destructiveBg:   Color { Color.red.opacity(0.12) }
    
    private let reminderOptions: [(label: String, minutes: Int)] = [
        ("Al momento", 0),
        ("15 minuti prima", 15),
        ("30 minuti prima", 30),
        ("1 ora prima", 60),
        ("1 giorno prima", 1440)
    ]
    
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        
                        // ── Titolo ──────────────────────────────────────
                        formCard {
                            VStack(alignment: .leading, spacing: 8) {
                                label("Titolo")
                                TextField("Es. Visita pediatrica", text: $title)
                                    .font(.body)
                            }
                            Divider()
                            // Categoria
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
                        
                        // ── Quando ──────────────────────────────────────
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
                                Picker("", selection: $recurrence) {
                                    ForEach(KBEventRecurrence.allCases) { r in
                                        Text(r.label).tag(r)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        
                        // ── Promemoria ──────────────────────────────────
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
                        
                        // ── Dettagli ─────────────────────────────────────
                        formCard {
                            VStack(alignment: .leading, spacing: 8) {
                                label("Luogo")
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(secondaryText)
                                    TextField("Indirizzo o luogo", text: $location)
                                }
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                label("Note")
                                TextField("Aggiungi note…", text: $notes, axis: .vertical)
                                    .lineLimit(3...)
                            }
                        }
                        
                        // ── Salva ────────────────────────────────────────
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
                        
                        Spacer().frame(height: 20)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
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
            .onAppear { populateFields() }
        }
    }
    
    // MARK: - Helpers
    
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
    
    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(secondaryText)
            .textCase(.uppercase)
            .kerning(0.5)
    }
    
    @ViewBuilder
    private func datePicker(_ title: String, selection: Binding<Date>, components: DatePickerComponents) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(primaryText)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: components)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "it_IT"))
        }
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
                            isSelected
                            ? Color.clear
                            : primaryText.opacity(0.12),
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
            if let mins = e.reminderMinutes {
                hasReminder   = true
                reminderIndex = reminderOptions.firstIndex(where: { $0.minutes == mins }) ?? 1
            }
        } else {
            startDate = Calendar.current.startOfDay(for: initialDate)
            endDate   = startDate.addingTimeInterval(3600)
        }
        
        if event == nil && !prefillTitle.isEmpty {
            title = prefillTitle
        }
    }
    
    private func save() {
        let uid  = Auth.auth().currentUser?.uid ?? ""
        let now  = Date()
        let mins = hasReminder ? reminderOptions[reminderIndex].minutes : nil
        
        if let e = event {
            e.title           = title.trimmingCharacters(in: .whitespaces)
            e.notes           = notes.isEmpty    ? nil : notes
            e.location        = location.isEmpty ? nil : location
            e.startDate       = startDate
            e.endDate         = endDate
            e.isAllDay        = isAllDay
            e.category        = category
            e.recurrence      = recurrence
            e.reminderMinutes = mins
            e.updatedAt       = now
            e.updatedBy       = uid
            e.syncState       = .pendingUpsert
            SyncCenter.shared.enqueueCalendarUpsert(
                eventId: e.id, familyId: familyId, modelContext: modelContext)
        } else {
            let newEvent = KBCalendarEvent(
                familyId:        familyId,
                title:           title.trimmingCharacters(in: .whitespaces),
                notes:           notes.isEmpty    ? nil : notes,
                location:        location.isEmpty ? nil : location,
                startDate:       startDate,
                endDate:         endDate,
                isAllDay:        isAllDay,
                category:        category,
                recurrence:      recurrence,
                reminderMinutes: mins,
                createdAt:       now,
                updatedAt:       now,
                updatedBy:       uid,
                createdBy:       uid
            )
            newEvent.syncState = .pendingUpsert
            modelContext.insert(newEvent)
            SyncCenter.shared.enqueueCalendarUpsert(
                eventId: newEvent.id, familyId: familyId, modelContext: modelContext)
        }
        
        try? modelContext.save()
        
        // Flush immediato verso Firestore senza aspettare il ciclo automatico (30s)
        Task { @MainActor in
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
        }
        
        dismiss()
    }
}

// MARK: - Color hex

private extension Color {
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
