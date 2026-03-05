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

// MARK: - List

struct PediatricTreatmentsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var treatments: [KBTreatment]
    @Query private var children: [KBChild]
    private var childName: String { children.first?.name ?? "bambino" }
    
    let familyId: String
    let childId: String
    
    @State private var showAddSheet = false
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
    }
    
    private var active:   [KBTreatment] { treatments.filter {  $0.isActive } }
    private var inactive: [KBTreatment] { treatments.filter { !$0.isActive } }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                if !active.isEmpty {
                    Section {
                        ForEach(active) { row($0) }
                            .onDelete { deleteItems(offsets: $0, from: active) }
                    } header: {
                        HStack {
                            Label("Cure Attive", systemImage: "pills.fill")
                                .foregroundStyle(tint)
                            Spacer()
                            Text("\(active.count)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(tint))
                        }
                    }
                }
                if !inactive.isEmpty {
                    Section("Storico") {
                        ForEach(inactive) { row($0) }
                            .onDelete { deleteItems(offsets: $0, from: inactive) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(KBTheme.background(colorScheme))
            .overlay {
                if treatments.isEmpty { emptyState }
            }
            
            // ── Bottone "Nuova Cura" sempre visibile ──
            Button {
                editingTreatmentId = nil
                showAddSheet = true
            } label: {
                Label("Nuova Cura", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(tint))
                    .foregroundStyle(.white)
                    .font(.headline)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(KBTheme.background(colorScheme))
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Cura")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingTreatmentId = nil
                    showAddSheet = true
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            PediatricTreatmentEditView(
                familyId: familyId,
                childId: childId,
                childName: childName,
                treatmentId: editingTreatmentId
            )
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 80, height: 80)
                Image(systemName: "cross.vial.fill").font(.system(size: 32)).foregroundStyle(tint)
            }
            Text("Nessuna cura aggiunta")
                .font(.title3.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text("Cura per \(childName)")
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func row(_ t: KBTreatment) -> some View {
        Button {
            coordinator.navigate(to: .pediatricTreatmentDetail(
                familyId: familyId,
                childId: childId,
                treatmentId: t.id
            ))
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "pills.fill").foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(t.drugName).font(.subheadline.bold())
                        if t.reminderEnabled && t.isActive {
                            Image(systemName: "bell.fill").font(.caption2).foregroundStyle(tint)
                        }
                    }
                    Text("\(t.dosageValue, specifier: "%.0f") \(t.dosageUnit) · \(t.dailyFrequency) volt\(t.dailyFrequency == 1 ? "a" : "e") al giorno")
                        .font(.caption).foregroundStyle(tint)
                    if !t.isActive {
                        Label("Interrotta", systemImage: "stop.circle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    } else if t.isLongTerm {
                        HStack(spacing: 8) {
                            Label("A lungo termine", systemImage: "infinity")
                                .font(.caption2).foregroundStyle(.secondary)
                            TreatmentDoseCounter(treatment: t)
                        }
                    } else {
                        TreatmentProgressLabel(treatment: t)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private func deleteItems(offsets: IndexSet, from list: [KBTreatment]) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        for i in offsets {
            let t = list[i]
            t.isDeleted = true; t.updatedBy = uid; t.updatedAt = now
            t.syncState = .pendingUpsert; t.lastSyncError = nil
            try? modelContext.save()
            SyncCenter.shared.enqueueTreatmentDelete(
                treatmentId: t.id, familyId: familyId, modelContext: modelContext
            )
        }
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
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
