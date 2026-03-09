//
//  PediatricTreatmentsView.swift
//  KidBox
//
//  Restyled: dynamic light/dark theme matching LoginView.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import UserNotifications

// MARK: - TreatmentTimeFilter

enum TreatmentTimeFilter: String, CaseIterable, Identifiable {
    case all       = "Tutte"
    case months3   = "3 mesi"
    case months6   = "6 mesi"
    case year1     = "Ultimo anno"
    case custom    = "Personalizzato"
    
    var id: String { rawValue }
    
    func cutoff(from customStart: Date?) -> Date? {
        let cal = Calendar.current
        switch self {
        case .all:     return nil
        case .months3: return cal.date(byAdding: .month, value: -3, to: Date())
        case .months6: return cal.date(byAdding: .month, value: -6, to: Date())
        case .year1:   return cal.date(byAdding: .year,  value: -1, to: Date())
        case .custom:  return customStart
        }
    }
}

// MARK: - TreatmentLifecycle

enum TreatmentLifecycle {
    case active
    case completed
    case inactive
}

// MARK: - TreatmentLifecycleRow
//
// Subview con @Query isolata per i log — necessaria perché @Query
// non può dipendere da parametri dinamici dentro un ForEach.

private struct TreatmentLifecycleRow: View {
    let treatment:   KBTreatment
    let familyId:    String
    let childId:     String
    let isSelected:  Bool
    let isSelecting: Bool
    let onTap:       () -> Void
    let onDelete:    () -> Void
    
    @Query private var logs: [KBDoseLog]
    private let tint = KBTheme.tint
    
    init(
        treatment: KBTreatment,
        familyId: String,
        childId: String,
        isSelected: Bool,
        isSelecting: Bool,
        onTap: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.treatment   = treatment
        self.familyId    = familyId
        self.childId     = childId
        self.isSelected  = isSelected
        self.isSelecting = isSelecting
        self.onTap       = onTap
        self.onDelete    = onDelete
        let tid = treatment.id
        _logs = Query(filter: #Predicate<KBDoseLog> { $0.treatmentId == tid && $0.taken == true })
    }
    
    var lifecycle: TreatmentLifecycle {
        guard !treatment.isDeleted  else { return .active }
        guard treatment.isActive    else { return .inactive }
        guard !treatment.isLongTerm else { return .active }
        let total = treatment.totalDoses
        if total > 0 && logs.count >= total { return .completed }
        if let end = treatment.endDate, end < Calendar.current.startOfDay(for: Date()) { return .completed }
        return .active
    }
    
    var body: some View {
        Button { onTap() } label: {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? tint : .secondary)
                        .font(.title3)
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
                ZStack {
                    Circle().fill(tint.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "pills.fill").foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(treatment.drugName).font(.subheadline.bold())
                        if treatment.reminderEnabled && lifecycle == .active {
                            Image(systemName: "bell.fill").font(.caption2).foregroundStyle(tint)
                        }
                    }
                    Text("\(treatment.dosageValue, specifier: "%.0f") \(treatment.dosageUnit) · \(treatment.dailyFrequency) volt\(treatment.dailyFrequency == 1 ? "a" : "e") al giorno")
                        .font(.caption).foregroundStyle(tint)
                    lifecycleLabel
                }
                Spacer()
                if !isSelecting {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Elimina", systemImage: "trash")
            }
        }
    }
    
    @ViewBuilder
    private var lifecycleLabel: some View {
        switch lifecycle {
        case .completed:
            Label("Terminata", systemImage: "checkmark.seal.fill")
                .font(.caption2).foregroundStyle(.green)
        case .inactive:
            Label("Interrotta", systemImage: "stop.circle.fill")
                .font(.caption2).foregroundStyle(.orange)
        case .active:
            if treatment.isLongTerm {
                HStack(spacing: 8) {
                    Label("A lungo termine", systemImage: "infinity")
                        .font(.caption2).foregroundStyle(.secondary)
                    TreatmentDoseCounter(treatment: treatment)
                }
            } else {
                TreatmentProgressLabel(treatment: treatment)
            }
        }
    }
}

// MARK: - PediatricTreatmentsView

struct PediatricTreatmentsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var treatments: [KBTreatment]
    @Query private var allLogs:    [KBDoseLog]
    @Query private var children:   [KBChild]
    private var childName: String { children.first?.name ?? "bambino" }
    
    let familyId: String
    let childId:  String
    
    @State private var isSelecting       = false
    @State private var selectedIds       = Set<String>()
    @State private var showDeleteConfirm = false
    
    @State private var timeFilter        = TreatmentTimeFilter.all
    @State private var showFilterSheet   = false
    @State private var customFilterStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customFilterEnd   = Date()
    
    @State private var showAddSheet        = false
    @State private var editingTreatmentId: String? = nil
    
    private let tint = KBTheme.tint
    
    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId  = childId
        let fid = familyId, cid = childId
        _treatments = Query(
            filter: #Predicate<KBTreatment> { $0.familyId == fid && $0.childId == cid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBTreatment.startDate, order: .reverse)]
        )
        _children = Query(filter: #Predicate<KBChild> { $0.id == cid })
        _allLogs  = Query(filter: #Predicate<KBDoseLog> { $0.familyId == fid && $0.childId == cid && $0.taken == true })
    }
    
    // MARK: - Lifecycle
    
    private func lifecycle(_ t: KBTreatment) -> TreatmentLifecycle {
        guard t.isActive    else { return .inactive }
        guard !t.isLongTerm else { return .active }
        let taken = allLogs.filter { $0.treatmentId == t.id }.count
        let total = t.totalDoses
        if total > 0 && taken >= total { return .completed }
        if let end = t.endDate, end < Calendar.current.startOfDay(for: Date()) { return .completed }
        return .active
    }
    
    // MARK: - Filtro temporale
    // Riferimento: la data più recente tra startDate e endDate
    
    private func passesTimeFilter(_ t: KBTreatment) -> Bool {
        guard let cutoff = timeFilter.cutoff(from: customFilterStart) else { return true }
        let ref = [t.startDate, t.endDate].compactMap { $0 }.max() ?? t.startDate
        if timeFilter == .custom {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: customFilterEnd) ?? customFilterEnd
            return ref >= cutoff && ref < endOfDay
        }
        return ref >= cutoff
    }
    
    private var filtered:    [KBTreatment] { treatments.filter { passesTimeFilter($0) } }
    private var active:      [KBTreatment] { filtered.filter { lifecycle($0) == .active } }
    private var completed:   [KBTreatment] { filtered.filter { lifecycle($0) == .completed } }
    private var inactive:    [KBTreatment] { filtered.filter { lifecycle($0) == .inactive } }
    private var allFiltered: [KBTreatment] { active + completed + inactive }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            if timeFilter != .all {
                filterPill
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            
            List {
                if !active.isEmpty {
                    Section {
                        ForEach(active) { t in rowView(t) }
                    } header: {
                        sectionHeader("Cure Attive", icon: "pills.fill", count: active.count, color: tint)
                    }
                }
                if !completed.isEmpty {
                    Section {
                        ForEach(completed) { t in rowView(t) }
                    } header: {
                        sectionHeader("Terminate", icon: "checkmark.seal.fill", count: completed.count, color: .green)
                    }
                }
                if !inactive.isEmpty {
                    Section {
                        ForEach(inactive) { t in rowView(t) }
                    } header: {
                        sectionHeader("Interrotte", icon: "stop.circle.fill", count: inactive.count, color: .orange)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(KBTheme.background(colorScheme))
            .overlay {
                if treatments.isEmpty { emptyState }
                else if filtered.isEmpty { emptyFilterState }
            }
            
            if isSelecting { selectionBottomBar } else { addButton }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Cure")
        .toolbar { toolbarItems }
        .sheet(isPresented: $showAddSheet) {
            PediatricTreatmentEditView(
                familyId: familyId, childId: childId,
                childName: childName, treatmentId: editingTreatmentId
            )
        }
        .sheet(isPresented: $showFilterSheet) { filterSheet }
        .confirmationDialog(
            "Eliminare \(selectedIds.count) cur\(selectedIds.count == 1 ? "a" : "e")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) { deleteSelected() }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Le cure verranno rimosse da tutti i dispositivi.")
        }
    }
    
    // MARK: - Row
    
    @ViewBuilder
    private func rowView(_ t: KBTreatment) -> some View {
        TreatmentLifecycleRow(
            treatment: t,
            familyId: familyId,
            childId: childId,
            isSelected: selectedIds.contains(t.id),
            isSelecting: isSelecting,
            onTap: {
                if isSelecting { toggleSelection(t.id) }
                else {
                    coordinator.navigate(to: .pediatricTreatmentDetail(
                        familyId: familyId, childId: childId, treatmentId: t.id
                    ))
                }
            },
            onDelete: { deleteSingle(t) }
        )
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 4) {
                Button { showFilterSheet = true } label: {
                    Image(systemName: timeFilter == .all
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(timeFilter == .all ? .primary : tint)
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
                    Button { editingTreatmentId = nil; showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
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
            Button { timeFilter = .all } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.12)))
        .foregroundStyle(tint)
    }
    
    private var filterLabel: String {
        let fmt = DateFormatter(); fmt.dateStyle = .short
        switch timeFilter {
        case .all:     return "Tutte"
        case .months3: return "Ultimi 3 mesi"
        case .months6: return "Ultimi 6 mesi"
        case .year1:   return "Ultimo anno"
        case .custom:  return "\(fmt.string(from: customFilterStart)) – \(fmt.string(from: customFilterEnd))"
        }
    }
    
    // MARK: - Filter sheet
    
    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Periodo rapido") {
                    ForEach([TreatmentTimeFilter.all, .months3, .months6, .year1], id: \.self) { f in
                        HStack {
                            Text(f.rawValue)
                            Spacer()
                            if timeFilter == f {
                                Image(systemName: "checkmark").foregroundStyle(tint)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { timeFilter = f; showFilterSheet = false }
                    }
                }
                Section("Periodo personalizzato") {
                    DatePicker("Da", selection: $customFilterStart, displayedComponents: .date)
                    DatePicker("A",  selection: $customFilterEnd,   displayedComponents: .date)
                    Button("Applica") {
                        if customFilterStart > customFilterEnd {
                            swap(&customFilterStart, &customFilterEnd)
                        }
                        timeFilter = .custom
                        showFilterSheet = false
                    }
                    .foregroundStyle(tint)
                }
            }
            .navigationTitle("Filtra per periodo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { showFilterSheet = false }
                }
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
                    if selectedIds.count == allFiltered.count { selectedIds.removeAll() }
                    else { selectedIds = Set(allFiltered.map { $0.id }) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selectedIds.count == allFiltered.count
                              ? "checkmark.circle.fill" : "circle.grid.3x3").font(.title3)
                        Text(selectedIds.count == allFiltered.count ? "Deseleziona" : "Tutte")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .foregroundStyle(tint).buttonStyle(.plain)
                
                Divider().frame(height: 40)
                
                Button { duplicateSelected() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "doc.on.doc").font(.title3)
                        Text("Duplica").font(.caption2)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .foregroundStyle(selectedIds.isEmpty ? .secondary : tint)
                .disabled(selectedIds.isEmpty).buttonStyle(.plain)
                
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
        Button { editingTreatmentId = nil; showAddSheet = true } label: {
            Label("Nuova Cura", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity).padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(tint))
                .foregroundStyle(.white).font(.headline)
        }
        .buttonStyle(.plain)
        .padding(.horizontal).padding(.vertical, 12)
        .background(KBTheme.background(colorScheme))
    }
    
    // MARK: - Section header
    
    private func sectionHeader(_ title: String, icon: String, count: Int, color: Color) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(color)
            Spacer()
            Text("\(count)")
                .font(.caption.bold()).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(color))
        }
    }
    
    // MARK: - Empty states
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 80, height: 80)
                Image(systemName: "cross.vial.fill").font(.system(size: 32)).foregroundStyle(tint)
            }
            Text("Nessuna cura aggiunta").font(.title3.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text("Cura per \(childName)").font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyFilterState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Nessuna cura nel periodo selezionato")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Rimuovi filtro") { timeFilter = .all }
                .font(.subheadline).foregroundStyle(tint)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helpers
    
    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) { selectedIds.remove(id) }
        else { selectedIds.insert(id) }
    }
    
    private func deleteSingle(_ t: KBTreatment) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        t.isDeleted = true; t.updatedBy = uid; t.updatedAt = Date()
        t.syncState = .pendingUpsert; t.lastSyncError = nil
        try? modelContext.save()
        SyncCenter.shared.enqueueTreatmentDelete(treatmentId: t.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    private func deleteSelected() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        for t in allFiltered where selectedIds.contains(t.id) {
            t.isDeleted = true; t.updatedBy = uid; t.updatedAt = now
            t.syncState = .pendingUpsert; t.lastSyncError = nil
            SyncCenter.shared.enqueueTreatmentDelete(treatmentId: t.id, familyId: familyId, modelContext: modelContext)
        }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        withAnimation { selectedIds.removeAll(); isSelecting = false }
    }
    
    private func duplicateSelected() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        for t in allFiltered where selectedIds.contains(t.id) {
            let endDate = t.isLongTerm ? nil
            : Calendar.current.date(byAdding: .day, value: t.durationDays - 1, to: now)
            let copy = KBTreatment(
                familyId:         t.familyId,
                childId:          t.childId,
                drugName:         t.drugName,
                activeIngredient: t.activeIngredient,
                dosageValue:      t.dosageValue,
                dosageUnit:       t.dosageUnit,
                isLongTerm:       t.isLongTerm,
                durationDays:     t.durationDays,
                startDate:        now,
                endDate:          endDate,
                dailyFrequency:   t.dailyFrequency,
                scheduleTimes:    t.scheduleTimes,
                isActive:         true,
                notes:            t.notes,
                reminderEnabled:  false,
                createdAt:        now,
                updatedAt:        now,
                updatedBy:        uid,
                createdBy:        uid
            )
            copy.syncState = .pendingUpsert
            modelContext.insert(copy)
            SyncCenter.shared.enqueueTreatmentUpsert(treatmentId: copy.id, familyId: familyId, modelContext: modelContext)
        }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        withAnimation { selectedIds.removeAll(); isSelecting = false }
    }
}

// MARK: - TreatmentDoseCounter

private struct TreatmentDoseCounter: View {
    let treatment: KBTreatment
    @Query private var logs: [KBDoseLog]
    
    init(treatment: KBTreatment) {
        self.treatment = treatment
        let tid = treatment.id
        _logs = Query(filter: #Predicate<KBDoseLog> { $0.treatmentId == tid && $0.taken == true })
    }
    
    var body: some View {
        let total = treatment.isLongTerm ? "∞" : "\(treatment.totalDoses)"
        Label("\(logs.count)/\(total) Dosi", systemImage: "calendar")
            .font(.caption2).foregroundStyle(.secondary)
    }
}

// MARK: - TreatmentProgressLabel

private struct TreatmentProgressLabel: View {
    let treatment: KBTreatment
    @Query private var logs: [KBDoseLog]
    
    init(treatment: KBTreatment) {
        self.treatment = treatment
        let tid = treatment.id
        _logs = Query(filter: #Predicate<KBDoseLog> { $0.treatmentId == tid && $0.taken == true })
    }
    
    private var currentDay: Int {
        let cal      = Calendar.current
        let startDay = cal.startOfDay(for: treatment.startDate)
        let today    = cal.startOfDay(for: Date())
        let days     = cal.dateComponents([.day], from: startDay, to: today).day ?? 0
        return min(days + 1, treatment.durationDays)
    }
    
    var body: some View {
        Label(
            "Giorno \(currentDay) di \(treatment.durationDays)  –  \(logs.count)/\(treatment.totalDoses)",
            systemImage: "calendar"
        )
        .font(.caption2).foregroundStyle(.secondary)
    }
}
