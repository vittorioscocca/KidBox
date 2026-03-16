//
//  PediatricExamsView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth
import QuickLook

// MARK: - Time filter

enum ExamTimeFilter: String, CaseIterable, Identifiable {
    case all     = "Tutti"
    case months3 = "3 mesi"
    case months6 = "6 mesi"
    case year1   = "Ultimo anno"
    case custom  = "Personalizzato"
    
    var id: String { rawValue }
    
    func cutoff(from customStart: Date?) -> Date? {
        let cal = Calendar.current
        switch self {
        case .all:     return nil
        case .months3: return cal.date(byAdding: .month, value: -3,  to: Date())
        case .months6: return cal.date(byAdding: .month, value: -6,  to: Date())
        case .year1:   return cal.date(byAdding: .year,  value: -1,  to: Date())
        case .custom:  return customStart
        }
    }
}

// MARK: - PediatricExamsView

struct PediatricExamsView: View {
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    
    let familyId: String
    let childId:  String
    
    @Query private var exams:    [KBMedicalExam]
    @Query private var children: [KBChild]
    @Query private var members:  [KBFamilyMember]
    private var childName: String {
        if let name = children.first?.name, !name.isEmpty { return name }
        if let name = members.first?.displayName, !name.isEmpty { return name }
        if let email = members.first?.email, !email.isEmpty { return email }
        return "bambino"
    }
    
    // Selection
    @State private var isSelecting       = false
    @State private var selectedIds       = Set<String>()
    @State private var showDeleteConfirm = false
    
    // Filter
    @State private var timeFilter        = ExamTimeFilter.all
    @State private var showFilterSheet   = false
    @State private var customFilterStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customFilterEnd   = Date()
    
    // Add sheet
    @State private var showAddSheet   = false
    @State private var editingExamId: String? = nil
    
    // Badge campanellina:
    // - badgeRefreshTick: incrementato da onAppear E da .examReminderChanged
    // - pendingBadgeRefresh: flag settato quando arriva .examReminderChanged
    //   mentre la view è in background (sotto la DetailView nello stack).
    //   Viene consumato al prossimo onAppear.
    @State private var badgeRefreshTick    = 0
    @State private var pendingBadgeRefresh = false
    
    // Realtime: avviato una sola volta per tutta la vita della view
    @State private var realtimeStarted = false
    
    private let tint = Color(red: 0.25, green: 0.65, blue: 0.75)
    
    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId  = childId
        let fid = familyId, cid = childId
        _exams    = Query(
            filter: #Predicate<KBMedicalExam> { $0.familyId == fid && $0.childId == cid && $0.isDeleted == false },
            sort:   [SortDescriptor(\KBMedicalExam.createdAt, order: .reverse)]
        )
        _children = Query(filter: #Predicate<KBChild> { $0.id == cid })
        _members  = Query(
            filter: #Predicate<KBFamilyMember> { $0.userId == cid && $0.familyId == fid && $0.isDeleted == false }
        )
    }
    
    // MARK: - Filter
    
    private func passesFilter(_ e: KBMedicalExam) -> Bool {
        guard let cutoff = timeFilter.cutoff(from: customFilterStart) else { return true }
        let ref = e.deadline ?? e.createdAt
        if timeFilter == .custom {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: customFilterEnd) ?? customFilterEnd
            return ref >= cutoff && ref < endOfDay
        }
        return ref >= cutoff
    }
    
    private var filtered: [KBMedicalExam] { exams.filter { passesFilter($0) } }
    private var pending:  [KBMedicalExam] { filtered.filter { $0.status == .pending } }
    private var booked:   [KBMedicalExam] { filtered.filter { $0.status == .booked } }
    private var done:     [KBMedicalExam] { filtered.filter { $0.status == .done || $0.status == .resultIn } }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            if timeFilter != .all { filterPill.padding(.horizontal).padding(.top, 8) }
            
            List {
                if !pending.isEmpty {
                    Section {
                        ForEach(pending) { e in rowView(e) }
                    } header: {
                        sectionHeader("In attesa", icon: "clock", count: pending.count, color: .orange)
                    }
                }
                if !booked.isEmpty {
                    Section {
                        ForEach(booked) { e in rowView(e) }
                    } header: {
                        sectionHeader("Prenotati", icon: "calendar.badge.checkmark", count: booked.count, color: tint)
                    }
                }
                if !done.isEmpty {
                    Section {
                        ForEach(done) { e in rowView(e) }
                    } header: {
                        sectionHeader("Eseguiti", icon: "checkmark.circle.fill", count: done.count, color: .green)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(KBTheme.background(colorScheme))
            .overlay {
                if exams.isEmpty         { emptyState }
                else if filtered.isEmpty { emptyFilterState }
            }
            
            if isSelecting { selectionBottomBar } else { addButton }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Analisi & Esami")
        .toolbar { toolbarItems }
        .overlay(alignment: .bottomTrailing) {
            if !isSelecting && AISettings.shared.isEnabled {
                ExamsAskAIButton(subjectName: childName, scope: .all(filtered))
                    .padding(.trailing, 20)
                    .padding(.bottom, 96)
            }
        }
        // Avvia il realtime UNA SOLA VOLTA (non si riavvia al pop dalla Detail)
        .task {
            guard !realtimeStarted else { return }
            realtimeStarted = true
            SyncCenter.shared.startMedicalExamsRealtime(
                familyId: familyId, childId: childId, modelContext: modelContext
            )
        }
        // onAppear: scatta sia al mount iniziale sia al pop dalla DetailView.
        // È IL POSTO GIUSTO per aggiornare le badge perché la view è tornata visibile.
        // Se era arrivata una .examReminderChanged mentre eravamo in background
        // (pendingBadgeRefresh == true), forziamo comunque il refresh.
        .onAppear {
            badgeRefreshTick += 1
            pendingBadgeRefresh = false
        }
        // .examReminderChanged arriva dalla DetailView subito dopo set/cancel reminder.
        // Se la ExamsView è in background (sotto la Detail nello stack), SwiftUI
        // potrebbe sospendere il .task(id:) nelle badge prima che venga rieseguito.
        // Solviamo su due livelli:
        // 1. Incrementiamo subito badgeRefreshTick (funziona se la view è attiva)
        // 2. Settiamo pendingBadgeRefresh = true (viene consumato al prossimo onAppear)
        .onReceive(NotificationCenter.default.publisher(for: .examReminderChanged)) { _ in
            badgeRefreshTick += 1
            pendingBadgeRefresh = true
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { editingExamId = nil }) {
            PediatricExamEditView(
                familyId:  familyId,
                childId:   childId,
                childName: childName,
                examId:    nil
            )
        }
        .sheet(isPresented: $showFilterSheet) { filterSheet }
        .confirmationDialog(
            "Eliminare \(selectedIds.count) esam\(selectedIds.count == 1 ? "e" : "i")?",
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) { deleteSelected() }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Gli esami verranno rimossi da tutti i dispositivi.")
        }
    }
    
    // MARK: - Row
    
    @ViewBuilder
    private func rowView(_ e: KBMedicalExam) -> some View {
        Button {
            if isSelecting {
                toggleSelection(e.id)
            } else {
                coordinator.navigate(to: .examDetail(familyId: familyId, childId: childId, examId: e.id))
            }
        } label: {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: selectedIds.contains(e.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedIds.contains(e.id) ? tint : .secondary)
                        .font(.title3)
                        .animation(.easeInOut(duration: 0.15), value: selectedIds.contains(e.id))
                }
                ZStack {
                    Circle().fill(statusColor(e.status).opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: e.status.icon).foregroundStyle(statusColor(e.status))
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(e.name).font(.subheadline.bold())
                        if e.isUrgent {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(.red)
                        }
                    }
                    Label(e.status.rawValue, systemImage: e.status.icon)
                        .font(.caption2).foregroundStyle(statusColor(e.status))
                    if let dl = e.deadline {
                        let isOverdue = dl < Date() && e.status == .pending
                        Label(deadlineLabel(dl), systemImage: "calendar")
                            .font(.caption2).foregroundStyle(isOverdue ? .red : .secondary)
                    }
                    if e.status == .resultIn, let res = e.resultText, !res.isEmpty {
                        Text(res).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if !isSelecting {
                    HStack(spacing: 6) {
                        ExamReminderBadge(examId: e.id, refreshTick: badgeRefreshTick)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleteSingle(e) } label: {
                Label("Elimina", systemImage: "trash")
            }
        }
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
                    Button { editingExamId = nil; showAddSheet = true } label: {
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
        case .all:     return "Tutti"
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
                    ForEach([ExamTimeFilter.all, .months3, .months6, .year1], id: \.self) { f in
                        HStack {
                            Text(f.rawValue)
                            Spacer()
                            if timeFilter == f { Image(systemName: "checkmark").foregroundStyle(tint) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { timeFilter = f; showFilterSheet = false }
                    }
                }
                Section("Personalizzato") {
                    DatePicker("Da", selection: $customFilterStart, displayedComponents: .date)
                    DatePicker("A",  selection: $customFilterEnd,   displayedComponents: .date)
                    Button("Applica") {
                        if customFilterStart > customFilterEnd { swap(&customFilterStart, &customFilterEnd) }
                        timeFilter = .custom; showFilterSheet = false
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
                    let all = filtered.map { $0.id }
                    if selectedIds.count == all.count { selectedIds.removeAll() }
                    else { selectedIds = Set(all) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selectedIds.count == filtered.count
                              ? "checkmark.circle.fill" : "circle.grid.3x3").font(.title3)
                        Text(selectedIds.count == filtered.count ? "Deseleziona" : "Tutte")
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
        Button { editingExamId = nil; showAddSheet = true } label: {
            Label("Nuovo Esame", systemImage: "plus.circle.fill")
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
            Text("\(count)").font(.caption.bold()).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(color))
        }
    }
    
    // MARK: - Empty states
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 80, height: 80)
                Image(systemName: "testtube.2").font(.system(size: 32)).foregroundStyle(tint)
            }
            Text("Nessun esame registrato").font(.title3.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text("Esami di \(childName)").font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyFilterState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Nessun esame nel periodo selezionato")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Rimuovi filtro") { timeFilter = .all }
                .font(.subheadline).foregroundStyle(tint)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }
    
    private func deleteSingle(_ e: KBMedicalExam) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        e.isDeleted = true; e.updatedBy = uid; e.updatedAt = Date()
        e.syncState = .pendingUpsert; e.lastSyncError = nil
        try? modelContext.save()
        SyncCenter.shared.enqueueMedicalExamDelete(examId: e.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    private func deleteSelected() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        for e in filtered where selectedIds.contains(e.id) {
            e.isDeleted = true; e.updatedBy = uid; e.updatedAt = now
            e.syncState = .pendingUpsert; e.lastSyncError = nil
            SyncCenter.shared.enqueueMedicalExamDelete(examId: e.id, familyId: familyId, modelContext: modelContext)
        }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        withAnimation { selectedIds.removeAll(); isSelecting = false }
    }
    
    private func statusColor(_ s: KBExamStatus) -> Color {
        switch s {
        case .pending:  return .orange
        case .booked:   return tint
        case .done:     return .green
        case .resultIn: return Color(red: 0.4, green: 0.75, blue: 0.65)
        }
    }
    
    private func deadlineLabel(_ date: Date) -> String {
        let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.locale = Locale(identifier: "it_IT")
        return "Entro \(fmt.string(from: date))"
    }
}

// MARK: - ExamReminderBadge

/// Mostra la campanellina arancione se l'esame ha un promemoria attivo.
///
/// Il controllo avviene tramite `.task(id: refreshTick)`:
/// ogni volta che `refreshTick` cambia (onAppear della lista o .examReminderChanged)
/// il task si ri-esegue e verifica le pending notifications.
private struct ExamReminderBadge: View {
    let examId:      String
    let refreshTick: Int
    
    @State private var isScheduled = false
    
    var body: some View {
        Group {
            if isScheduled {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                // Placeholder trasparente per mantenere la larghezza costante
                // ed evitare layout shift quando la badge appare/sparisce.
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(.clear)
            }
        }
        .task(id: refreshTick) {
            let notifId  = KBExamReminderService.shared.notificationId(for: examId)
            let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
            let found    = requests.contains { $0.identifier == notifId }
            await MainActor.run { isScheduled = found }
        }
    }
}
