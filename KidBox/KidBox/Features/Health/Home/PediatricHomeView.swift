//
//  PediatricHomeView.swift
//  KidBox
//
//  Restyled: dynamic light/dark theme matching LoginView.
//  Added: floating HealthAskAIButton (full-health AI overview).
//

import SwiftUI
import SwiftData

// MARK: - Timeline types

enum HealthEventKind: String {
    case visit     = "Visita"
    case exam      = "Esame"
    case treatment = "Cura"
    case vaccine   = "Vaccino"
    
    var icon: String {
        switch self {
        case .visit:     return "stethoscope"
        case .exam:      return "testtube.2"
        case .treatment: return "pills.fill"
        case .vaccine:   return "syringe.fill"
        }
    }
    var color: Color {
        switch self {
        case .visit:     return Color(red: 0.35, green: 0.6,  blue: 0.85)
        case .exam:      return Color(red: 0.25, green: 0.65, blue: 0.75)
        case .treatment: return Color(red: 0.6,  green: 0.45, blue: 0.85)
        case .vaccine:   return Color(red: 0.95, green: 0.55, blue: 0.45)
        }
    }
}

struct HealthTimelineEvent: Identifiable {
    let id:       String
    let sourceId: String   // id reale del record (visitId, examId, treatmentId, vaccineId)
    let date:     Date
    let kind:     HealthEventKind
    let title:    String
    let subtitle: String?
}

struct PediatricHomeView: View {
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    let familyId: String
    let childId: String
    
    @Query private var children: [KBChild]
    @Query private var members:  [KBFamilyMember]
    
    @Query private var allTreatments: [KBTreatment]
    @Query private var allLogs:       [KBDoseLog]
    @Query private var allVaccines:   [KBVaccine]
    @Query private var allVisits:     [KBMedicalVisit]
    @Query private var allExams:      [KBMedicalExam]
    
    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId  = childId
        
        let cid = childId
        let fid = familyId
        
        _children = Query(filter: #Predicate<KBChild> { $0.id == cid })
        _members  = Query(filter: #Predicate<KBFamilyMember> { $0.userId == cid })
        
        _allTreatments = Query(filter: #Predicate<KBTreatment> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false && $0.isActive == true
        })
        _allLogs = Query(filter: #Predicate<KBDoseLog> {
            $0.familyId == fid && $0.childId == cid && $0.taken == true
        })
        _allVaccines = Query(filter: #Predicate<KBVaccine> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
        })
        _allVisits = Query(filter: #Predicate<KBMedicalVisit> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
        })
        _allExams = Query(filter: #Predicate<KBMedicalExam> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
        })
    }
    
    // childId is used as the universal subjectId — valid for both KBChild and KBFamilyMember
    private var child: KBChild?         { children.first }
    private var member: KBFamilyMember? { members.first }
    private var subjectName: String     { child?.name ?? member?.displayName ?? "Profilo" }
    private var childEmoji: String      { child?.avatarEmoji ?? "🧑" }
    
    /// Cure davvero in corso (esclude terminate per dosi/data)
    private var activeTreatments: [KBTreatment] {
        let today = Calendar.current.startOfDay(for: Date())
        return allTreatments.filter { t in
            if t.isLongTerm { return true }
            if let end = t.endDate, end < today { return false }
            let total = t.totalDoses
            if total > 0 {
                let taken = allLogs.filter { $0.treatmentId == t.id }.count
                if taken >= total { return false }
            }
            return true
        }
    }
    
    private var activeTreatmentsCount: Int { activeTreatments.count }
    
    /// Esami in attesa o prenotati (non ancora eseguiti)
    private var pendingExamsCount: Int {
        allExams.filter { $0.status == .pending || $0.status == .booked }.count
    }
    
    // MARK: - Timeline
    
    private var timelineEvents: [HealthTimelineEvent] {
        var events: [HealthTimelineEvent] = []
        
        for v in allVisits {
            events.append(HealthTimelineEvent(
                id:       "visit-\(v.id)",
                sourceId: v.id,
                date:     v.date,
                kind:     .visit,
                title:    v.reason.isEmpty ? "Visita medica" : v.reason,
                subtitle: v.doctorName
            ))
        }
        for e in allExams {
            let ref = e.deadline ?? e.createdAt
            events.append(HealthTimelineEvent(
                id:       "exam-\(e.id)",
                sourceId: e.id,
                date:     ref,
                kind:     .exam,
                title:    e.name,
                subtitle: e.status.rawValue
            ))
        }
        for t in allTreatments {
            events.append(HealthTimelineEvent(
                id:       "treatment-\(t.id)",
                sourceId: t.id,
                date:     t.startDate,
                kind:     .treatment,
                title:    t.drugName,
                subtitle: t.isLongTerm ? "Lungo termine" : (t.durationDays > 0 ? "\(t.durationDays) giorni" : nil)
            ))
        }
        for v in allVaccines {
            let date = v.administeredDate ?? v.scheduledDate ?? v.createdAt
            events.append(HealthTimelineEvent(
                id:       "vaccine-\(v.id)",
                sourceId: v.id,
                date:     date,
                kind:     .vaccine,
                title:    v.commercialName ?? v.vaccineType.displayName,
                subtitle: v.lotNumber.map { "Lotto: \($0)" }
            ))
        }
        
        return events.sorted { $0.date > $1.date }
    }
    
    // Raggruppa per anno, poi per mese
    private var timelineByYear: [(year: Int, months: [(month: Int, events: [HealthTimelineEvent])])] {
        let cal = Calendar.current
        let byYear = Dictionary(grouping: timelineEvents) {
            cal.component(.year, from: $0.date)
        }
        return byYear.keys.sorted(by: >).map { year in
            let yearEvents = byYear[year]!
            let byMonth = Dictionary(grouping: yearEvents) {
                cal.component(.month, from: $0.date)
            }
            let months = byMonth.keys.sorted(by: >).map { month in
                (month: month, events: byMonth[month]!.sorted { $0.date > $1.date })
            }
            return (year: year, months: months)
        }
    }
    
    private func monthName(_ month: Int) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "it_IT")
        return fmt.monthSymbols[month - 1].capitalized
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerView
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    moduleCard(
                        title: "Cure",
                        subtitle: activeTreatmentsCount > 0
                        ? "\(activeTreatmentsCount) attiv\(activeTreatmentsCount == 1 ? "a" : "e")"
                        : "Farmaci attivi",
                        systemImage: "cross.case.fill",
                        tint: Color(red: 0.6, green: 0.45, blue: 0.85),
                        badge: activeTreatmentsCount > 0 ? activeTreatmentsCount : nil
                    ) {
                        coordinator.navigate(to: .pediatricTreatments(familyId: familyId, childId: childId))
                    }
                    moduleCard(
                        title: "Vaccini",
                        subtitle: "\(allVaccines.count) registrati",
                        systemImage: "syringe.fill",
                        tint: Color(red: 0.95, green: 0.55, blue: 0.45)
                    ) {
                        coordinator.navigate(to: .pediatricVaccines(familyId: familyId, childId: childId))
                    }
                    moduleCard(
                        title: "Visite",
                        subtitle: "\(allVisits.count) registrate",
                        systemImage: "stethoscope",
                        tint: Color(red: 0.35, green: 0.6, blue: 0.85)
                    ) {
                        coordinator.navigate(to: .pediatricVisits(familyId: familyId, childId: childId))
                    }
                    moduleCard(
                        title: "Analisi & Esami",
                        subtitle: pendingExamsCount > 0
                        ? "\(pendingExamsCount) in attesa"
                        : "\(allExams.count) registrati",
                        systemImage: "testtube.2",
                        tint: Color(red: 0.25, green: 0.65, blue: 0.75),
                        badge: pendingExamsCount > 0 ? pendingExamsCount : nil
                    ) {
                        coordinator.navigate(to: .pediatricExams(familyId: familyId, childId: childId))
                    }
                    moduleCard(
                        title: "Scheda Medica",
                        subtitle: "Allergie, pediatra",
                        systemImage: "doc.text.fill",
                        tint: Color(red: 0.4, green: 0.75, blue: 0.65)
                    ) {
                        coordinator.navigate(to: .pediatricMedicalRecord(familyId: familyId, childId: childId))
                    }
                    moduleCard(
                        title: "Storico Salute",
                        subtitle: "\(timelineEvents.count) eventi",
                        systemImage: "timeline.selection",
                        tint: Color(red: 0.85, green: 0.55, blue: 0.35)
                    ) {
                        coordinator.navigate(to: .pediatricTimeline(familyId: familyId, childId: childId))
                    }
                }
                .padding(.horizontal)
                
                // Spacer so the last card is never hidden behind the floating button
                Spacer(minLength: 80)
            }
            .padding(.vertical)
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Salute")
        .navigationBarTitleDisplayMode(.large)
        .overlay(alignment: .bottomTrailing) {
            HealthAskAIButton(
                subjectName: subjectName,
                subjectId:   childId,
                exams:       allExams,
                visits:      allVisits,
                treatments:  activeTreatments,
                vaccines:    allVaccines
            )
            .padding(.trailing, 20)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(KBTheme.tint.opacity(0.15))
                    .frame(width: 52, height: 52)
                Text(childEmoji).font(.title2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(subjectName)
                    .font(.title3.bold())
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                Text("Diario di salute")
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }
            Spacer()
        }
        .padding(.horizontal)
    }
    
    // MARK: - Module card
    
    @ViewBuilder
    private func moduleCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        badge: Int? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle().fill(tint.opacity(0.15)).frame(width: 60, height: 60)
                        Image(systemName: systemImage).font(.title2).foregroundStyle(tint)
                    }
                    if let badge, badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(tint))
                            .offset(x: 4, y: -4)
                    }
                }
                VStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(KBTheme.cardBackground(colorScheme))
                    .shadow(color: KBTheme.shadow(colorScheme), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HealthTimelineView

struct HealthTimelineView: View {
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.colorScheme) private var colorScheme
    
    let subjectName: String
    let familyId:    String
    let childId:     String
    let events:      [HealthTimelineEvent]   // tutti gli eventi grezzi, non pre-raggruppati
    let monthName:   (Int) -> String
    
    @State private var activeFilters: Set<String> = []
    @State private var selectedYear: Int? = nil
    @State private var showYearSheet = false
    @State private var searchText = ""
    @State private var isSearchPresented = false
    
    private let allKinds: [HealthEventKind] = [.visit, .exam, .treatment, .vaccine]
    
    // Anni disponibili calcolati dagli eventi grezzi
    private var availableYears: [Int] {
        let cal = Calendar.current
        let years = Set(events.map { cal.component(.year, from: $0.date) })
        return years.sorted(by: >)
    }
    
    // Raggruppa per anno → mese applicando i filtri attivi
    private var filteredByYear: [(year: Int, months: [(month: Int, events: [HealthTimelineEvent])])] {
        let cal = Calendar.current
        
        // 1. Filtra per tipo (se ci sono filtri attivi)
        let kindFiltered: [HealthTimelineEvent]
        if activeFilters.isEmpty {
            kindFiltered = events
        } else {
            kindFiltered = events.filter { activeFilters.contains($0.kind.rawValue) }
        }
        
        // 2. Filtra per anno selezionato
        let yearFiltered: [HealthTimelineEvent]
        if let y = selectedYear {
            yearFiltered = kindFiltered.filter { cal.component(.year, from: $0.date) == y }
        } else {
            yearFiltered = kindFiltered
        }
        
        // 3. Filtro testo
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched: [HealthTimelineEvent] = q.isEmpty ? yearFiltered : yearFiltered.filter {
            $0.title.localizedCaseInsensitiveContains(q)
            || ($0.subtitle ?? "").localizedCaseInsensitiveContains(q)
            || $0.kind.rawValue.localizedCaseInsensitiveContains(q)
        }
        
        // 4. Raggruppa per anno → mese
        let byYear = Dictionary(grouping: searched) { cal.component(.year, from: $0.date) }
        return byYear.keys.sorted(by: >).map { year in
            let byMonth = Dictionary(grouping: byYear[year]!) { cal.component(.month, from: $0.date) }
            let months = byMonth.keys.sorted(by: >).map { month in
                (month: month, events: byMonth[month]!.sorted { $0.date > $1.date })
            }
            return (year: year, months: months)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ── Barra filtri ──
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Pulsante anno → sheet
                    Button { showYearSheet = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: selectedYear == nil ? "calendar" : "calendar.badge.checkmark")
                                .font(.caption.bold())
                            Text(selectedYear.map(String.init) ?? "Anno")
                                .font(.caption.bold())
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(
                            selectedYear == nil
                            ? Color.secondary.opacity(0.12)
                            : Color(red: 0.85, green: 0.55, blue: 0.35).opacity(0.15)
                        ))
                        .foregroundStyle(selectedYear == nil ? .secondary : Color(red: 0.85, green: 0.55, blue: 0.35))
                        .overlay(Capsule().strokeBorder(
                            selectedYear == nil ? Color.clear : Color(red: 0.85, green: 0.55, blue: 0.35).opacity(0.4),
                            lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1, height: 20)
                    
                    // Chip tipi
                    ForEach(allKinds, id: \.rawValue) { kind in
                        let active = activeFilters.contains(kind.rawValue)
                        Button {
                            if active { activeFilters.remove(kind.rawValue) }
                            else      { activeFilters.insert(kind.rawValue) }
                        } label: {
                            Label(kind.rawValue, systemImage: kind.icon)
                                .font(.caption.bold())
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(active ? kind.color : kind.color.opacity(0.12)))
                                .foregroundStyle(active ? .white : kind.color)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal).padding(.vertical, 10)
            }
            Divider()
            
            if filteredByYear.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 44)).foregroundStyle(.secondary.opacity(0.4))
                    Text("Nessun evento trovato")
                        .font(.title3.bold()).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(subjectName)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 2)
                            .padding(.bottom, 12)
                        
                        ForEach(filteredByYear, id: \.year) { yearGroup in
                            HStack {
                                Text(String(yearGroup.year))
                                    .font(.title2.bold())
                                    .foregroundStyle(.primary)
                                let count = yearGroup.months.flatMap { $0.events }.count
                                Text("\(count) eventi")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(KBTheme.background(colorScheme).opacity(0.97))
                            
                            ForEach(yearGroup.months, id: \.month) { monthGroup in
                                HStack(spacing: 6) {
                                    Text(monthName(monthGroup.month).uppercased())
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(height: 1)
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 6)
                                
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(monthGroup.events) { event in
                                        timelineRow(event, isLast: event.id == monthGroup.events.last?.id)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        Color.clear.frame(height: 32)
                    }
                }
                .id(selectedYear.map(String.init) ?? "all")
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Storico")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { isSearchPresented = true } label: {
                    Image(systemName: "magnifyingglass")
                }
                if isSearchPresented {
                    Button {
                        searchText = ""
                        isSearchPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Cerca visite, esami, cure…"
        )
        .sheet(isPresented: $showYearSheet) {
            NavigationStack {
                List {
                    Button {
                        selectedYear = nil; showYearSheet = false
                    } label: {
                        HStack {
                            Label("Tutti gli anni", systemImage: "calendar").foregroundStyle(.primary)
                            Spacer()
                            if selectedYear == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color(red: 0.85, green: 0.55, blue: 0.35))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    ForEach(availableYears, id: \.self) { year in
                        let count = events.filter {
                            Calendar.current.component(.year, from: $0.date) == year
                        }.count
                        Button {
                            selectedYear = year; showYearSheet = false
                        } label: {
                            HStack {
                                Text(String(year)).foregroundStyle(.primary)
                                Spacer()
                                Text("\(count) eventi").font(.caption).foregroundStyle(.secondary)
                                if selectedYear == year {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color(red: 0.85, green: 0.55, blue: 0.35))
                                        .padding(.leading, 6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .navigationTitle("Filtra per anno")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Chiudi") { showYearSheet = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
    
    // MARK: - Row
    
    private func timelineRow(_ event: HealthTimelineEvent, isLast: Bool) -> some View {
        Button {
            navigateTo(event)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Linea verticale + dot
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(event.kind.color.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: event.kind.icon)
                            .font(.caption.bold())
                            .foregroundStyle(event.kind.color)
                    }
                    if !isLast {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: 1.5)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 32)
                
                // Contenuto
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    if let sub = event.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(event.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 6)
                .padding(.bottom, isLast ? 8 : 20)
                
                Spacer()
                
                // Chip tipo + chevron
                HStack(spacing: 6) {
                    Text(event.kind.rawValue)
                        .font(.caption2.bold())
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(event.kind.color.opacity(0.12)))
                        .foregroundStyle(event.kind.color)
                    if event.kind != .vaccine {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .buttonStyle(.plain)
        .disabled(event.kind == .vaccine) // nessuna detail view per i vaccini
    }
    
    // MARK: - Navigation
    
    private func navigateTo(_ event: HealthTimelineEvent) {
        switch event.kind {
        case .visit:
            coordinator.navigate(to: .pediatricVisitDetail(
                familyId: familyId, childId: childId, visitId: event.sourceId
            ))
        case .exam:
            coordinator.navigate(to: .examDetail(
                familyId: familyId, childId: childId, examId: event.sourceId
            ))
        case .treatment:
            coordinator.navigate(to: .pediatricTreatmentDetail(
                familyId: familyId, childId: childId, treatmentId: event.sourceId
            ))
        case .vaccine:
            break // nessuna detail view disponibile
        }
    }
}

// MARK: - PediatricTimelineDestinationView
//
// Wrapper necessario perché HealthTimelineView non fa @Query direttamente
// (riceve gli eventi già pronti). Questa view è la destinazione reale nel
// NavigationStack del coordinator, quindi back da visitDetail/examDetail
// ritorna qui — non alla PediatricHomeView.

struct PediatricTimelineDestinationView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    
    let familyId: String
    let childId:  String
    
    @Query private var children:      [KBChild]
    @Query private var members:       [KBFamilyMember]
    @Query private var allVisits:     [KBMedicalVisit]
    @Query private var allExams:      [KBMedicalExam]
    @Query private var allTreatments: [KBTreatment]
    @Query private var allVaccines:   [KBVaccine]
    
    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId  = childId
        let fid = familyId
        let cid = childId
        _children      = Query(filter: #Predicate<KBChild>         { $0.id == cid })
        _members       = Query(filter: #Predicate<KBFamilyMember>  { $0.userId == cid })
        _allVisits     = Query(filter: #Predicate<KBMedicalVisit>  { $0.familyId == fid && $0.childId == cid && $0.isDeleted == false })
        _allExams      = Query(filter: #Predicate<KBMedicalExam>   { $0.familyId == fid && $0.childId == cid && $0.isDeleted == false })
        _allTreatments = Query(filter: #Predicate<KBTreatment>     { $0.familyId == fid && $0.childId == cid && $0.isDeleted == false })
        _allVaccines   = Query(filter: #Predicate<KBVaccine>       { $0.familyId == fid && $0.childId == cid && $0.isDeleted == false })
    }
    
    private var subjectName: String {
        children.first?.name ?? members.first?.displayName ?? "Profilo"
    }
    
    private var timelineEvents: [HealthTimelineEvent] {
        var events: [HealthTimelineEvent] = []
        for v in allVisits {
            events.append(HealthTimelineEvent(id: "visit-\(v.id)", sourceId: v.id, date: v.date, kind: .visit,
                                              title: v.reason.isEmpty ? "Visita medica" : v.reason, subtitle: v.doctorName))
        }
        for e in allExams {
            events.append(HealthTimelineEvent(id: "exam-\(e.id)", sourceId: e.id,
                                              date: e.deadline ?? e.createdAt, kind: .exam, title: e.name, subtitle: e.status.rawValue))
        }
        for t in allTreatments {
            events.append(HealthTimelineEvent(id: "treatment-\(t.id)", sourceId: t.id, date: t.startDate, kind: .treatment,
                                              title: t.drugName, subtitle: t.isLongTerm ? "Lungo termine" : (t.durationDays > 0 ? "\(t.durationDays) giorni" : nil)))
        }
        for v in allVaccines {
            events.append(HealthTimelineEvent(id: "vaccine-\(v.id)", sourceId: v.id,
                                              date: v.administeredDate ?? v.scheduledDate ?? v.createdAt,
                                              kind: .vaccine, title: v.commercialName ?? v.vaccineType.displayName,
                                              subtitle: v.lotNumber.map { "Lotto: \($0)" }))
        }
        return events.sorted { $0.date > $1.date }
    }
    
    private func monthName(_ month: Int) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "it_IT")
        return fmt.monthSymbols[month - 1].capitalized
    }
    
    var body: some View {
        HealthTimelineView(
            subjectName: subjectName,
            familyId:    familyId,
            childId:     childId,
            events:      timelineEvents,
            monthName:   monthName
        )
    }
}
