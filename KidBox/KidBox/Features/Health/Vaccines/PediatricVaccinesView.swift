//
//  PediatricVaccinesView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - List

enum VaccineTimeFilter: String, CaseIterable, Identifiable {
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
        case .months3: return cal.date(byAdding: .month, value: -3, to: Date())
        case .months6: return cal.date(byAdding: .month, value: -6, to: Date())
        case .year1:   return cal.date(byAdding: .year,  value: -1, to: Date())
        case .custom:  return customStart
        }
    }
}

struct PediatricVaccinesView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    @Query private var vaccines: [KBVaccine]
    
    let familyId: String
    let childId:  String
    
    @State private var showEditSheet    = false
    @State private var editingVaccineId: String? = nil
    
    // ── Selezione multipla ──
    @State private var isSelecting       = false
    @State private var selectedIds       = Set<String>()
    @State private var showDeleteConfirm = false
    
    // ── Filtro periodo ──
    @State private var timeFilter        = VaccineTimeFilter.all
    @State private var showFilterSheet   = false
    @State private var customFilterStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customFilterEnd   = Date()
    
    private let tint = Color(red: 0.95, green: 0.55, blue: 0.45)
    
    // LoginView-style dynamic theme
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    private var cardBackground: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.07)
        : Color.black.opacity(0.04)
    }
    private var shadowColor: Color {
        colorScheme == .dark ? Color.clear : Color.black.opacity(0.06)
    }
    
    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId  = childId
        let fid = familyId, cid = childId
        _vaccines = Query(
            filter: #Predicate<KBVaccine> {
                $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
            },
            sort: [SortDescriptor(\KBVaccine.administeredDate, order: .reverse)]
        )
    }
    
    private func passesFilter(_ v: KBVaccine) -> Bool {
        guard let cutoff = timeFilter.cutoff(from: customFilterStart) else { return true }
        let ref = v.administeredDate ?? v.scheduledDate ?? v.updatedAt
        if timeFilter == .custom {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: customFilterEnd) ?? customFilterEnd
            return ref >= cutoff && ref < endOfDay
        }
        return ref >= cutoff
    }
    
    private var filtered:    [KBVaccine] { vaccines.filter { passesFilter($0) } }
    private var administered: [KBVaccine] { filtered.filter { $0.status == .administered } }
    private var scheduled:    [KBVaccine] { filtered.filter { $0.status == .scheduled } }
    private var planned:      [KBVaccine] { filtered.filter { $0.status == .planned } }
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                if timeFilter != .all {
                    filterPill.padding(.horizontal).padding(.top, 8)
                }
                Group {
                    if vaccines.isEmpty {
                        emptyState
                    } else if filtered.isEmpty {
                        emptyFilterState
                    } else {
                        ScrollView {
                            VStack(spacing: 24) {
                                if !scheduled.isEmpty {
                                    sectionBlock(
                                        title: "Appuntamento fissato",
                                        icon: "calendar.badge.clock",
                                        iconColor: .blue,
                                        items: scheduled
                                    )
                                }
                                if !administered.isEmpty {
                                    sectionBlock(
                                        title: "Somministrati",
                                        icon: "checkmark.circle.fill",
                                        iconColor: .green,
                                        items: administered
                                    )
                                }
                                if !planned.isEmpty {
                                    sectionBlock(
                                        title: "Da programmare",
                                        icon: "clock.badge.questionmark",
                                        iconColor: .orange,
                                        items: planned
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 40)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if isSelecting { selectionBottomBar } else { addButton }
            }
        }
        .navigationTitle("Vaccini")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarItems }
        .sheet(isPresented: $showEditSheet) {
            PediatricVaccineEditView(
                familyId:  familyId,
                childId:   childId,
                vaccineId: editingVaccineId
            ) { savedId in
                SyncCenter.shared.enqueueVaccineUpsert(
                    vaccineId: savedId, familyId: familyId, modelContext: modelContext
                )
                SyncCenter.shared.flushGlobal(modelContext: modelContext)
            }
        }
        .sheet(isPresented: $showFilterSheet) { filterSheet }
        .onAppear {
            SyncCenter.shared.startVaccinesRealtime(
                familyId: familyId, childId: childId, modelContext: modelContext
            )
        }
        .onDisappear { SyncCenter.shared.stopVaccinesRealtime() }
        .confirmationDialog(
            "Eliminare \(selectedIds.count) vaccin\(selectedIds.count == 1 ? "o" : "i")?",
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) { deleteSelected() }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("I vaccini verranno rimossi da tutti i dispositivi.")
        }
    }
    
    // MARK: - Section block
    
    private func sectionBlock(title: String, icon: String, iconColor: Color, items: [KBVaccine]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(iconColor)
                Text(title.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
                Spacer()
                Text("\(items.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(iconColor.opacity(0.8)))
            }
            
            // Cards
            VStack(spacing: 10) {
                ForEach(items) { vaccineCard($0) }
            }
        }
    }
    
    // MARK: - Vaccine card
    
    private func vaccineCard(_ v: KBVaccine) -> some View {
        Button {
            if isSelecting {
                toggleSelection(v.id)
            } else {
                editingVaccineId = v.id
                showEditSheet = true
            }
        } label: {
            HStack(spacing: 14) {
                // Selection circle
                if isSelecting {
                    Image(systemName: selectedIds.contains(v.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedIds.contains(v.id) ? tint : .secondary)
                        .font(.title3)
                        .animation(.easeInOut(duration: 0.15), value: selectedIds.contains(v.id))
                }
                
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tint.opacity(colorScheme == .dark ? 0.2 : 0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: v.vaccineType.systemImage)
                        .font(.system(size: 18))
                        .foregroundStyle(tint)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(v.vaccineType.displayName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    
                    if let cn = v.commercialName, !cn.isEmpty {
                        Text(cn)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Text("Dose \(v.doseNumber)/\(v.totalDoses)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(tint.opacity(0.85)))
                        
                        if let d = v.administeredDate ?? v.scheduledDate {
                            Text(d.formatted(.dateTime.day().month(.abbreviated).year()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Status dot + chevron
                if !isSelecting {
                    VStack(alignment: .trailing, spacing: 6) {
                        statusDot(v.status)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .shadow(color: shadowColor, radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
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
                    Button {
                        editingVaccineId = nil
                        showEditSheet = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(tint.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(tint)
                        }
                    }
                }
            }
        }
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
                        Text(selectedIds.count == filtered.count ? "Deseleziona" : "Tutti")
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
            .background(backgroundColor)
        }
    }
    
    // MARK: - Add button
    
    private var addButton: some View {
        Button {
            editingVaccineId = nil
            showEditSheet = true
        } label: {
            Label("Aggiungi vaccino", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity).padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(tint))
                .foregroundStyle(.white).font(.headline)
        }
        .buttonStyle(.plain)
        .padding(.horizontal).padding(.vertical, 12)
        .background(backgroundColor)
    }
    
    // MARK: - Delete
    
    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }
    
    private func deleteSelected() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        for v in filtered where selectedIds.contains(v.id) {
            v.isDeleted = true; v.updatedBy = uid; v.updatedAt = now
            v.syncState = .pendingUpsert; v.lastSyncError = nil
            SyncCenter.shared.enqueueVaccineDelete(vaccineId: v.id, familyId: familyId, modelContext: modelContext)
        }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        withAnimation { selectedIds.removeAll(); isSelecting = false }
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
                    ForEach([VaccineTimeFilter.all, .months3, .months6, .year1], id: \.self) { f in
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
    
    // MARK: - Empty filter state
    
    private var emptyFilterState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Nessun vaccino nel periodo selezionato")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Rimuovi filtro") { timeFilter = .all }
                .font(.subheadline).foregroundStyle(tint)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func statusDot(_ status: VaccineStatus) -> some View {
        let color: Color = switch status {
        case .administered: .green
        case .scheduled:    .blue
        case .planned:      .orange
        }
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
    
    // MARK: - Empty state
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(tint.opacity(colorScheme == .dark ? 0.15 : 0.10))
                    .frame(width: 88, height: 88)
                Image(systemName: "syringe.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(tint)
            }
            VStack(spacing: 8) {
                Text("Libretto Vaccinale Vuoto")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(.primary)
                Text("Inizia a registrare i vaccini per tenere\ntraccia del calendario vaccinale")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                editingVaccineId = nil
                showEditSheet = true
            } label: {
                Label("Aggiungi il primo vaccino", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 32)
    }
    
    private func deleteVaccines(offsets: IndexSet, from list: [KBVaccine]) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        for i in offsets {
            let v = list[i]
            v.isDeleted = true; v.updatedBy = uid; v.updatedAt = Date(); v.syncState = .pendingUpsert
            SyncCenter.shared.enqueueVaccineDelete(vaccineId: v.id, familyId: familyId, modelContext: modelContext)
        }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
}

// MARK: - Edit sheet

struct PediatricVaccineEditView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.colorScheme)  private var colorScheme
    
    let familyId:  String
    let childId:   String
    let vaccineId: String?
    let onSaved:   (String) -> Void
    
    @State private var vaccineType:      VaccineType    = .esavalente
    @State private var status:           VaccineStatus  = .administered
    @State private var commercialName    = ""
    @State private var doseNumber        = 1
    @State private var totalDoses        = 1
    @State private var administeredDate  = Date()
    @State private var scheduledDate     = Date()
    @State private var lotNumber         = ""
    @State private var administeredBy    = ""
    @State private var adminSite         = ""
    @State private var notes             = ""
    
    private let sites = ["Braccio sinistro", "Braccio destro", "Coscia sinistra", "Coscia destra", "Orale", "Nasale", "Altro"]
    private let tint  = Color(red: 0.95, green: 0.55, blue: 0.45)
    private var isEditing: Bool { vaccineId != nil }
    
    // LoginView-style
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    private var cardBg: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Status selector
                        formCard {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionLabel("Stato vaccino", icon: "checkmark.seal.fill")
                                HStack(spacing: 10) {
                                    ForEach([VaccineStatus.administered, .scheduled, .planned], id: \.self) { s in
                                        statusChip(s)
                                    }
                                }
                            }
                        }
                        
                        // Vaccine type grid
                        formCard {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionLabel("Tipo di Vaccino", icon: "syringe.fill")
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(VaccineType.allCases, id: \.self) { vaccineTypeCell($0) }
                                }
                                TextField("Nome commerciale (opzionale)", text: $commercialName)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)))
                                    .font(.subheadline)
                            }
                        }
                        
                        // Dose info
                        formCard {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionLabel("Informazioni Dose", icon: "number.circle.fill")
                                HStack(spacing: 16) {
                                    stepperField(label: "Dose N°", value: $doseNumber, range: 1...10)
                                    Divider().frame(height: 40)
                                    stepperField(label: "Dosi totali", value: $totalDoses, range: 1...10)
                                }
                            }
                        }
                        
                        // Date
                        formCard {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionLabel(
                                    status == .administered ? "Data Somministrazione" : "Data Appuntamento",
                                    icon: "calendar"
                                )
                                if status == .administered {
                                    DatePicker("", selection: $administeredDate, displayedComponents: .date)
                                        .datePickerStyle(.graphical)
                                        .tint(tint)
                                } else if status == .scheduled {
                                    DatePicker("", selection: $scheduledDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .tint(tint)
                                } else {
                                    Text("Nessuna data da impostare per vaccini da programmare")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        // Details (only if administered)
                        if status == .administered {
                            formCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    sectionLabel("Dettagli (opzionali)", icon: "info.circle.fill")
                                    editField(placeholder: "Numero lotto", text: $lotNumber)
                                    editField(placeholder: "Somministrato da", text: $administeredBy)
                                    // Site picker inline
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Sito somministrazione").font(.caption).foregroundStyle(.secondary)
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(sites, id: \.self) { site in
                                                    Button { adminSite = (adminSite == site) ? "" : site } label: {
                                                        Text(site).font(.caption)
                                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                                            .background(Capsule().fill(adminSite == site ? tint : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.07))))
                                                            .foregroundStyle(adminSite == site ? .white : .primary)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Notes
                        formCard {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionLabel("Note", icon: "square.and.pencil")
                                TextField("Note aggiuntive", text: $notes, axis: .vertical)
                                    .lineLimit(3...5)
                                    .font(.subheadline)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)))
                            }
                        }
                        
                        // Save button
                        Button { save() } label: {
                            Text(isEditing ? "Salva modifiche" : "Aggiungi vaccino")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Capsule().fill(tint))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(isEditing ? "Modifica Vaccino" : "Nuovo Vaccino")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear { loadIfEditing() }
        }
    }
    
    // MARK: - UI helpers
    
    private func formCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBg)
            )
    }
    
    private func sectionLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.bold())
            .foregroundStyle(.primary)
    }
    
    private func editField(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.subheadline)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)))
    }
    
    private func stepperField(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 } } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3).foregroundStyle(value.wrappedValue > range.lowerBound ? tint : .secondary)
                }
                .buttonStyle(.plain)
                Text("\(value.wrappedValue)").font(.title3.bold()).frame(minWidth: 24)
                Button { if value.wrappedValue < range.upperBound { value.wrappedValue += 1 } } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3).foregroundStyle(value.wrappedValue < range.upperBound ? tint : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func statusChip(_ s: VaccineStatus) -> some View {
        let isSelected = status == s
        let color: Color = switch s {
        case .administered: .green
        case .scheduled:    .blue
        case .planned:      .orange
        }
        return Button { status = s } label: {
            VStack(spacing: 4) {
                statusIconView(s, color: color, isSelected: isSelected)
                Text(s.displayName)
                    .font(.caption2.bold())
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? color.opacity(colorScheme == .dark ? 0.25 : 0.12) : (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func statusIconView(_ s: VaccineStatus, color: Color, isSelected: Bool) -> some View {
        let icon: String = switch s {
        case .administered: "checkmark.circle.fill"
        case .scheduled:    "calendar.badge.clock"
        case .planned:      "clock.badge.questionmark"
        }
        Image(systemName: icon).font(.title3).foregroundStyle(isSelected ? color : .secondary)
    }
    
    @ViewBuilder
    private func vaccineTypeCell(_ t: VaccineType) -> some View {
        let isSelected = vaccineType == t
        Button { vaccineType = t } label: {
            VStack(spacing: 8) {
                Image(systemName: t.systemImage)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : tint)
                Text(t.displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? tint : (colorScheme == .dark ? Color.white.opacity(0.07) : Color(.systemGray6))))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Load & Save
    
    private func loadIfEditing() {
        guard let vid = vaccineId else { return }
        let desc = FetchDescriptor<KBVaccine>(predicate: #Predicate { $0.id == vid })
        guard let v = try? modelContext.fetch(desc).first else { return }
        vaccineType    = v.vaccineType
        status         = v.status
        commercialName = v.commercialName ?? ""
        doseNumber     = v.doseNumber
        totalDoses     = v.totalDoses
        if let d = v.administeredDate { administeredDate = d }
        if let d = v.scheduledDate    { scheduledDate    = d }
        lotNumber      = v.lotNumber ?? ""
        administeredBy = v.administeredBy ?? ""
        adminSite      = v.administrationSiteRaw ?? ""
        notes          = v.notes ?? ""
    }
    
    private func save() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let savedId: String
        
        if let vid = vaccineId {
            let desc = FetchDescriptor<KBVaccine>(predicate: #Predicate { $0.id == vid })
            guard let v = try? modelContext.fetch(desc).first else { return }
            applyFields(to: v, uid: uid, now: now)
            v.syncState = .pendingUpsert
            savedId = v.id
        } else {
            let v = KBVaccine(
                familyId: familyId, childId: childId,
                vaccineType: vaccineType, status: status,
                createdAt: now, updatedAt: now, updatedBy: uid, createdBy: uid
            )
            modelContext.insert(v)
            applyFields(to: v, uid: uid, now: now)
            v.syncState = .pendingUpsert
            savedId = v.id
        }
        try? modelContext.save()
        onSaved(savedId)
        dismiss()
    }
    
    private func applyFields(to v: KBVaccine, uid: String, now: Date) {
        v.vaccineType           = vaccineType
        v.status                = status
        v.commercialName        = commercialName.isEmpty ? nil : commercialName
        v.doseNumber            = doseNumber
        v.totalDoses            = totalDoses
        v.administeredDate      = status == .administered ? administeredDate : nil
        v.scheduledDate         = status == .scheduled    ? scheduledDate    : nil
        v.lotNumber             = lotNumber.isEmpty ? nil : lotNumber
        v.administeredBy        = administeredBy.isEmpty ? nil : administeredBy
        v.administrationSiteRaw = adminSite.isEmpty ? nil : adminSite
        v.notes                 = notes.isEmpty ? nil : notes
        v.updatedBy             = uid
        v.updatedAt             = now
    }
}

extension VaccineStatus {
    var displayName: String {
        switch self {
        case .administered: return "Somministrato"
        case .scheduled:    return "Appuntamento"
        case .planned:      return "Da programmare"
        }
    }
}
