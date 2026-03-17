//
//  PediatricVisitsView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct PediatricVisitsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    
    @Query private var visits:   [KBMedicalVisit]
    @Query private var children: [KBChild]
    @Query private var members:  [KBFamilyMember]
    
    let familyId: String
    let childId:  String
    
    // ── Add ──
    @State private var showAddSheet = false
    
    // ── Selezione multipla ──
    @State private var isSelecting       = false
    @State private var selectedIds       = Set<String>()
    @State private var showDeleteConfirm = false
    
    // ── Filtro ──
    @State private var selectedPeriod: PeriodFilter = .all
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate:   Date = Date()
    @State private var showFilterSheet  = false
    
    // ── Ricerca ──
    @State private var searchText = ""
    
    // ── AI ──
    @State private var showAIConsent     = false
    @State private var showAIChat        = false
    @State private var aiSelectedVisits: [KBMedicalVisit] = []
    @State private var aiSelectedPeriod: PeriodFilter = .all
    @State private var aiSubjectName     = ""
    @State private var aiScopeId_        = ""
    
    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)
    
    // MARK: - Init
    
    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId  = childId
        let fid = familyId, cid = childId
        _visits   = Query(
            filter: #Predicate<KBMedicalVisit> { $0.familyId == fid && $0.childId == cid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBMedicalVisit.date, order: .reverse)]
        )
        _children = Query(filter: #Predicate<KBChild> { $0.id == cid })
        _members  = Query(filter: #Predicate<KBFamilyMember> { $0.familyId == fid && $0.userId == cid })
    }
    
    // MARK: - Computed
    
    private var selectedPerson: PediatricPerson? {
        if let c = children.first { return .child(c) }
        if let m = members.first  { return .member(m) }
        return nil
    }
    
    private var childName: String {
        switch selectedPerson {
        case .child(let c):  return c.name
        case .member(let m): return m.displayName ?? "membro famiglia"
        case nil:            return "bambino"
        }
    }
    
    private struct VisitSection {
        let status: KBVisitStatus
        let visits: [KBMedicalVisit]
    }
    
    // Ordine di visualizzazione delle sezioni
    private let sectionOrder: [KBVisitStatus] = [.booked, .pending, .completed, .resultAvailable]
    
    private var visitSections: [VisitSection] {
        // Visite senza stato → trattate come .pending
        let grouped = Dictionary(grouping: filteredVisits) { v in
            v.visitStatus ?? .pending
        }
        return sectionOrder.compactMap { status in
            guard let visits = grouped[status], !visits.isEmpty else { return nil }
            return VisitSection(status: status, visits: visits)
        }
    }
    
    private var filteredVisits: [KBMedicalVisit] {
        let periodFiltered: [KBMedicalVisit]
        switch selectedPeriod {
        case .all:
            periodFiltered = visits
        case .custom:
            let start  = min(customStartDate, customEndDate)
            let endDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59,
                                               of: max(customStartDate, customEndDate)) ?? customEndDate
            periodFiltered = visits.filter { $0.date >= start && $0.date <= endDay }
        default:
            if let cutoff = selectedPeriod.cutoffDate {
                periodFiltered = visits.filter { $0.date >= cutoff }
            } else {
                periodFiltered = visits
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return periodFiltered }
        return periodFiltered.filter { v in
            v.reason.localizedCaseInsensitiveContains(query)
            || (v.doctorName      ?? "").localizedCaseInsensitiveContains(query)
            || (v.diagnosis       ?? "").localizedCaseInsensitiveContains(query)
            || (v.recommendations ?? "").localizedCaseInsensitiveContains(query)
            || (v.notes           ?? "").localizedCaseInsensitiveContains(query)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            if selectedPeriod != .all { filterPill.padding(.horizontal).padding(.top, 8) }
            
            List {
                if filteredVisits.isEmpty {
                    Section {
                        emptyState
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    // ── Sezioni per stato ──
                    ForEach(visitSections, id: \.status) { section in
                        Section {
                            ForEach(section.visits) { visitRow($0) }
                                .onDelete(perform: isSelecting ? nil : { offsets in
                                    deleteItems(offsets: offsets, in: section.visits)
                                })
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: section.status.icon)
                                    .foregroundStyle(section.status.color)
                                Text(section.status.rawValue)
                                    .foregroundStyle(section.status.color)
                                    .font(.caption.bold().uppercaseSmallCaps())
                                Spacer()
                                Text("\(section.visits.count)")
                                    .font(.caption.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(section.status.color))
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(KBTheme.background(colorScheme))
            
            // ── Bottom bar ──
            if isSelecting { selectionBottomBar } else { addButton }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Visita Medica")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Cerca visita"
        )
        .toolbar { toolbarItems }
        .sheet(isPresented: $showAddSheet) {
            PediatricVisitEditView(familyId: familyId, childId: childId, childName: childName)
        }
        .sheet(isPresented: $showFilterSheet) { filterSheet }
        .sheet(isPresented: $showAIConsent) {
            AIConsentSheet { showAIChat = true }
        }
        .sheet(isPresented: $showAIChat) {
            PediatricVisitsAIChatView(
                subjectName:     aiSubjectName,
                visibleVisits:   aiSelectedVisits,
                selectedPeriod:  aiSelectedPeriod,
                customStartDate: aiSelectedPeriod == .custom ? customStartDate : nil,
                customEndDate:   aiSelectedPeriod == .custom ? customEndDate   : nil,
                scopeId:         aiScopeId_
            )
        }
        .confirmationDialog(
            "Eliminare \(selectedIds.count) visit\(selectedIds.count == 1 ? "a" : "e")?",
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) { deleteSelected() }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Le visite verranno rimosse da tutti i dispositivi.")
        }
        .overlay(alignment: .bottomTrailing) {
            if let selectedPerson, !filteredVisits.isEmpty, !isSelecting, AISettings.shared.isEnabled {
                PediatricVisitsAskAIButton(
                    person: selectedPerson,
                    visits: filteredVisits,
                    selectedPeriod: selectedPeriod
                ) { person, visits, period in
                    handleAskAI(person: person, visits: visits, period: period)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 96)
            }
        }
        .environment(\.locale, Locale(identifier: "it_IT"))
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 4) {
                Button { showFilterSheet = true } label: {
                    Image(systemName: selectedPeriod == .all
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(selectedPeriod == .all ? .primary : tint)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSelecting.toggle()
                        if !isSelecting { selectedIds.removeAll() }
                    }
                } label: {
                    Text(isSelecting ? "Fine" : "Seleziona").font(.subheadline)
                }
                if !isSelecting {
                    Button { showAddSheet = true } label: { Image(systemName: "plus") }
                }
            }
        }
    }
    
    // MARK: - Row
    
    private func visitRow(_ v: KBMedicalVisit) -> some View {
        Button {
            if isSelecting {
                toggleSelection(v.id)
            } else {
                coordinator.navigate(to: .pediatricVisitDetail(
                    familyId: familyId, childId: childId, visitId: v.id
                ))
            }
        } label: {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: selectedIds.contains(v.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedIds.contains(v.id) ? tint : .secondary)
                        .font(.title3)
                        .animation(.easeInOut(duration: 0.15), value: selectedIds.contains(v.id))
                }
                ZStack {
                    Circle().fill(tint.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "stethoscope").foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(v.reason.isEmpty ? "Visita" : v.reason)
                        .font(.subheadline.bold())
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                        .lineLimit(1)
                    if let doctor = v.doctorName, !doctor.isEmpty {
                        Text(doctor).font(.caption).foregroundStyle(tint).lineLimit(1)
                    }
                    Text(v.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(KBTheme.secondaryText(colorScheme))
                    if let status = v.visitStatus {
                        Label(status.rawValue, systemImage: status.icon)
                            .font(.caption2.bold())
                            .foregroundStyle(status.color)
                    }
                }
                Spacer()
                if !isSelecting {
                    if v.diagnosis != nil {
                        Image(systemName: "doc.text.fill").font(.caption).foregroundStyle(tint.opacity(0.6))
                    }
                    if v.reminderOn || v.nextVisitReminderOn {
                        Image(systemName: "bell.fill")
                            .font(.caption)
                            .foregroundStyle(tint)
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isSelecting {
                Button(role: .destructive) { deleteSingle(v) } label: {
                    Label("Elimina", systemImage: "trash")
                }
            }
        }
    }
    
    // MARK: - Filter pill
    
    private var filterPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar").font(.caption)
            Text(filterLabel).font(.caption.bold())
            Spacer()
            Button { selectedPeriod = .all } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.12)))
        .foregroundStyle(tint)
    }
    
    private var filterLabel: String {
        let fmt = DateFormatter(); fmt.dateStyle = .short
        switch selectedPeriod {
        case .all:        return "Tutti"
        case .thirtyDays: return "Ultimi 30 giorni"
        case .custom:     return "\(fmt.string(from: customStartDate)) – \(fmt.string(from: customEndDate))"
        default:          return selectedPeriod.label
        }
    }
    
    // MARK: - Filter sheet
    
    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Periodo rapido") {
                    ForEach([PeriodFilter.all, .threeMonths, .sixMonths, .oneYear], id: \.self) { f in
                        HStack {
                            Text(f.label)
                            Spacer()
                            if selectedPeriod == f { Image(systemName: "checkmark").foregroundStyle(tint) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedPeriod = f; showFilterSheet = false }
                    }
                }
                Section("Personalizzato") {
                    DatePicker("Da", selection: $customStartDate, displayedComponents: .date)
                    DatePicker("A",  selection: $customEndDate,   displayedComponents: .date)
                    Button("Applica") {
                        if customStartDate > customEndDate { swap(&customStartDate, &customEndDate) }
                        selectedPeriod = .custom; showFilterSheet = false
                    }
                    .foregroundStyle(tint)
                }
            }
            .navigationTitle("Filtra per periodo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Chiudi") { showFilterSheet = false } }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Selection bottom bar
    
    private var selectionBottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Button {
                    let all = filteredVisits.map { $0.id }
                    if selectedIds.count == all.count { selectedIds.removeAll() }
                    else { selectedIds = Set(all) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selectedIds.count == filteredVisits.count
                              ? "checkmark.circle.fill" : "circle.grid.3x3").font(.title3)
                        Text(selectedIds.count == filteredVisits.count ? "Deseleziona" : "Tutte")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .foregroundStyle(tint).buttonStyle(.plain)
                
                Divider().frame(height: 40)
                
                Button { showDeleteConfirm = true } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash").font(.title3)
                        Text("Elimina").font(.caption2)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .foregroundStyle(selectedIds.isEmpty ? .secondary : Color.red)
                .disabled(selectedIds.isEmpty).buttonStyle(.plain)
            }
            .background(KBTheme.background(colorScheme))
        }
    }
    
    // MARK: - Add button
    
    private var addButton: some View {
        Button { showAddSheet = true } label: {
            Label("Aggiungi nuova visita", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity).padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(tint))
                .foregroundStyle(.white).font(.headline)
        }
        .buttonStyle(.plain)
        .padding(.horizontal).padding(.vertical, 12)
        .background(KBTheme.background(colorScheme))
    }
    
    // MARK: - Empty state
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 80, height: 80)
                Image(systemName: "stethoscope").font(.system(size: 32)).foregroundStyle(tint)
            }
            Text("Nessuna visita registrata").font(.title3.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text("Aggiungi la prima visita per \(childName)")
                .font(.subheadline).foregroundStyle(KBTheme.secondaryText(colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding().frame(maxWidth: .infinity).padding(.vertical, 40)
    }
    
    // MARK: - Delete
    
    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }
    
    private func deleteSingle(_ v: KBMedicalVisit) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        v.isDeleted = true; v.updatedBy = uid; v.updatedAt = Date()
        v.syncState = .pendingUpsert; v.lastSyncError = nil
        try? modelContext.save()
        SyncCenter.shared.enqueueVisitDelete(visitId: v.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    private func deleteSelected() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        for v in filteredVisits where selectedIds.contains(v.id) {
            v.isDeleted = true; v.updatedBy = uid; v.updatedAt = now
            v.syncState = .pendingUpsert; v.lastSyncError = nil
            SyncCenter.shared.enqueueVisitDelete(visitId: v.id, familyId: familyId, modelContext: modelContext)
        }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        withAnimation { selectedIds.removeAll(); isSelecting = false }
    }
    
    private func deleteItems(offsets: IndexSet, in source: [KBMedicalVisit]) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        for i in offsets {
            let v = source[i]
            v.isDeleted = true; v.updatedBy = uid; v.updatedAt = now
            v.syncState = .pendingUpsert; v.lastSyncError = nil
            SyncCenter.shared.enqueueVisitDelete(visitId: v.id, familyId: familyId, modelContext: modelContext)
        }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    // MARK: - AI
    
    private func buildAiScopeId(for person: PediatricPerson, period: PeriodFilter) -> String {
        let base: String
        switch person {
        case .child(let c):  base = "visits-child-\(c.id)"
        case .member(let m): base = "visits-member-\(m.id)"
        }
        if period == .custom {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.dateFormat = "yyyyMMdd"
            return "\(base)-custom-\(fmt.string(from: min(customStartDate, customEndDate)))-\(fmt.string(from: max(customStartDate, customEndDate)))"
        }
        return "\(base)-\(period.rawValue)"
    }
    
    private func handleAskAI(person: PediatricPerson, visits _: [KBMedicalVisit], period: PeriodFilter) {
        KBLog.ai.kbInfo("handleAskAI START period=\(period.rawValue) filteredVisits=\(filteredVisits.count)")
        guard !filteredVisits.isEmpty else { return }
        switch person {
        case .child(let c):  aiSubjectName = c.name
        case .member(let m): aiSubjectName = m.displayName ?? "Membro della famiglia"
        }
        aiScopeId_       = buildAiScopeId(for: person, period: period)
        aiSelectedVisits = filteredVisits
        aiSelectedPeriod = period
        if !AISettings.shared.consentGiven { showAIConsent = true; return }
        showAIChat = true
    }
    
    private func italianShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
    }
}
