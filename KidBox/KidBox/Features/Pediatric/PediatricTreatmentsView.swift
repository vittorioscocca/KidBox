//
//  PediatricTreatmentsView.swift
//  KidBox
//
//  Created by vscocca on 03/03/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import UserNotifications

// MARK: - List

struct PediatricTreatmentsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Query private var treatments: [KBTreatment]
    @Query private var children: [KBChild]
    private var childName: String { children.first?.name ?? "bambino" }
    
    let familyId: String
    let childId: String
    
    @State private var showAddSheet = false
    @State private var editingTreatmentId: String? = nil

    private let tint = Color(red: 0.6, green: 0.45, blue: 0.85)
    
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
            // Lista (anche quando vuota mostra la sezione)
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
            .overlay {
                if treatments.isEmpty {
                    emptyState
                }
            }
            
            // ── Bottone "Nuova Cura" sempre visibile in fondo ──
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
            .background(Color(.systemGroupedBackground))
        }
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
            Text("Nessuna cura aggiunta").font(.title3.bold())
            Text("Cura per \(childName)").font(.subheadline).foregroundStyle(.secondary)
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
                    Text(t.drugName).font(.subheadline.bold())
                    Text("\(t.dosageValue, specifier: "%.0f") \(t.dosageUnit) · \(t.dailyFrequency) volt\(t.dailyFrequency == 1 ? "a" : "e") al giorno")
                        .font(.caption).foregroundStyle(tint)
                    if !t.isLongTerm, let day = t.currentDay {
                        Label("Giorno \(day) di \(t.durationDays)  –  0/\(t.totalDoses)", systemImage: "calendar")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if t.isLongTerm {
                        Label("Cura a lungo termine", systemImage: "infinity")
                            .font(.caption2).foregroundStyle(.secondary)
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
        for i in offsets { list[i].isDeleted = true; list[i].updatedBy = uid; list[i].updatedAt = Date() }
        try? modelContext.save()
    }
}

// MARK: - Scheda Medica

struct PediatricMedicalRecordView: View {
    
    @Environment(\.modelContext) private var modelContext
    let familyId: String
    let childId: String
    
    @State private var profile: KBPediatricProfile? = nil
    @State private var bloodGroup   = ""
    @State private var allergies    = ""
    @State private var medicalNotes = ""
    @State private var doctorName   = ""
    @State private var doctorPhone  = ""
    @State private var isSaving     = false
    
    private let bloodGroups = ["Non specificato", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]
    
    var body: some View {
        Form {
            Section("Gruppo sanguigno") {
                Picker("Gruppo sanguigno", selection: $bloodGroup) {
                    ForEach(bloodGroups, id: \.self) { Text($0).tag($0) }
                }
            }
            Section("Allergie conosciute") {
                TextField("es. Latte, uova, pollini", text: $allergies, axis: .vertical).lineLimit(2...4)
            }
            Section("Pediatra di riferimento") {
                TextField("Dott./Dott.ssa", text: $doctorName)
                TextField("Telefono", text: $doctorPhone).keyboardType(.phonePad)
            }
            Section("Note mediche") {
                TextField("Eventuali condizioni o note importanti", text: $medicalNotes, axis: .vertical).lineLimit(3...6)
            }
            Section {
                Button(isSaving ? "Salvataggio..." : "Salva scheda") { save() }
                    .disabled(isSaving)
            }
        }
        .navigationTitle("Scheda Medica")
        .onAppear { load() }
    }
    
    private func load() {
        let cid = childId
        let desc = FetchDescriptor<KBPediatricProfile>(predicate: #Predicate { $0.childId == cid })
        if let p = try? modelContext.fetch(desc).first {
            profile     = p
            bloodGroup  = p.bloodGroup ?? ""
            allergies   = p.allergies ?? ""
            medicalNotes = p.medicalNotes ?? ""
            doctorName  = p.doctorName ?? ""
            doctorPhone = p.doctorPhone ?? ""
        }
    }
    
    private func save() {
        isSaving = true
        let uid  = Auth.auth().currentUser?.uid ?? "local"
        let now  = Date()
        if let p = profile {
            p.bloodGroup   = bloodGroup.isEmpty   ? nil : bloodGroup
            p.allergies    = allergies.isEmpty     ? nil : allergies
            p.medicalNotes = medicalNotes.isEmpty  ? nil : medicalNotes
            p.doctorName   = doctorName.isEmpty    ? nil : doctorName
            p.doctorPhone  = doctorPhone.isEmpty   ? nil : doctorPhone
            p.updatedAt    = now; p.updatedBy = uid
        } else {
            let p = KBPediatricProfile(
                childId: childId, familyId: familyId,
                bloodGroup: bloodGroup.isEmpty ? nil : bloodGroup,
                allergies: allergies.isEmpty ? nil : allergies,
                medicalNotes: medicalNotes.isEmpty ? nil : medicalNotes,
                doctorName: doctorName.isEmpty ? nil : doctorName,
                doctorPhone: doctorPhone.isEmpty ? nil : doctorPhone,
                updatedAt: now, updatedBy: uid
            )
            modelContext.insert(p)
            profile = p
        }
        try? modelContext.save()
        isSaving = false
    }
}
