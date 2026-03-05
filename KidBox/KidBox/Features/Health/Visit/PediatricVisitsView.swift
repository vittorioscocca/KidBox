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
    @Environment(\.colorScheme) private var colorScheme
    @Query private var visits: [KBMedicalVisit]
    @Query private var children: [KBChild]
    private var childName: String { children.first?.name ?? "bambino" }
    
    let familyId: String
    let childId: String
    
    @State private var showAddSheet = false
    @State private var selectedPeriod: PeriodFilter = .thirtyDays
    
    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)
    
    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId  = childId
        let fid = familyId, cid = childId
        _visits = Query(
            filter: #Predicate<KBMedicalVisit> {
                $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
            },
            sort: [SortDescriptor(\KBMedicalVisit.date, order: .reverse)]
        )
        _children = Query(filter: #Predicate<KBChild> { $0.id == cid })
    }
    
    private var filteredVisits: [KBMedicalVisit] {
        guard let cutoff = selectedPeriod.cutoffDate else { return visits }
        return visits.filter { $0.date >= cutoff }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                // ── Filtro periodo ──
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Filtra per periodo")
                                .font(.caption)
                                .foregroundStyle(KBTheme.secondaryText(colorScheme))
                            Text("\(filteredVisits.count) visit\(filteredVisits.count == 1 ? "a" : "e")")
                                .font(.subheadline.bold())
                                .foregroundStyle(KBTheme.primaryText(colorScheme))
                        }
                        Spacer()
                        Menu {
                            ForEach(PeriodFilter.allCases) { p in
                                Button {
                                    selectedPeriod = p
                                } label: {
                                    HStack {
                                        Text(p.label)
                                        if selectedPeriod == p { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                Text(selectedPeriod.label)
                                Image(systemName: "chevron.down")
                            }
                            .font(.subheadline)
                            .foregroundStyle(tint)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1)))
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                
                if filteredVisits.isEmpty {
                    Section {
                        emptyState
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Section {
                        ForEach(filteredVisits) { visitRow($0) }
                            .onDelete { deleteItems(offsets: $0) }
                    } header: {
                        HStack {
                            Label("Visite recenti", systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(tint)
                            Spacer()
                            Text("\(filteredVisits.count)")
                                .font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(tint))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(KBTheme.background(colorScheme))
            
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
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Visita Medica")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button { } label: { Image(systemName: "square.and.arrow.up") }
                    Button { showAddSheet = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            PediatricVisitEditView(familyId: familyId, childId: childId, childName: childName)
        }
    }
    
    // MARK: - Row
    
    private func visitRow(_ v: KBMedicalVisit) -> some View {
        Button {
            coordinator.navigate(to: .pediatricVisitDetail(
                familyId: familyId, childId: childId, visitId: v.id
            ))
        } label: {
            HStack(spacing: 12) {
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
                        Text(doctor)
                            .font(.caption).foregroundStyle(tint).lineLimit(1)
                    }
                    Text(v.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                Spacer()
                if v.diagnosis != nil {
                    Image(systemName: "doc.text.fill")
                        .font(.caption).foregroundStyle(tint.opacity(0.6))
                }
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty state
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 80, height: 80)
                Image(systemName: "stethoscope").font(.system(size: 32)).foregroundStyle(tint)
            }
            Text("Nessuna visita registrata")
                .font(.title3.bold()).foregroundStyle(KBTheme.primaryText(colorScheme))
            Text("Aggiungi la prima visita per \(childName)")
                .font(.subheadline).foregroundStyle(KBTheme.secondaryText(colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding().frame(maxWidth: .infinity).padding(.vertical, 40)
    }
    
    // MARK: - Delete
    
    private func deleteItems(offsets: IndexSet) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        for i in offsets {
            let v = filteredVisits[i]
            v.isDeleted = true; v.updatedBy = uid; v.updatedAt = now
            v.syncState = .pendingUpsert; v.lastSyncError = nil
            try? modelContext.save()
            SyncCenter.shared.enqueueVisitDelete(
                visitId: v.id, familyId: familyId, modelContext: modelContext
            )
        }
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
}

// MARK: - PeriodFilter

enum PeriodFilter: String, CaseIterable, Identifiable {
    case sevenDays = "7 gg", thirtyDays = "30 gg"
    case threeMonths = "3 mesi", sixMonths = "6 mesi"
    case oneYear = "1 anno", all = "Tutto"
    
    var id: String { rawValue }
    var label: String { rawValue }
    
    var cutoffDate: Date? {
        let cal = Calendar.current; let now = Date()
        switch self {
        case .sevenDays:   return cal.date(byAdding: .day,   value: -7,  to: now)
        case .thirtyDays:  return cal.date(byAdding: .day,   value: -30, to: now)
        case .threeMonths: return cal.date(byAdding: .month, value: -3,  to: now)
        case .sixMonths:   return cal.date(byAdding: .month, value: -6,  to: now)
        case .oneYear:     return cal.date(byAdding: .year,  value: -1,  to: now)
        case .all:         return nil
        }
    }
}
