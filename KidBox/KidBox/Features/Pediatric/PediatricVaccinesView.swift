//
//  PediatricVaccinesView.swift
//  KidBox
//
//  Created by vscocca on 03/03/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - List

struct PediatricVaccinesView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query private var vaccines: [KBVaccine]
    
    let familyId: String
    let childId: String
    
    @State private var showEditSheet = false
    @State private var editingVaccineId: String? = nil
    
    private let tint = Color(red: 0.95, green: 0.55, blue: 0.45)
    
    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId  = childId
        let fid = familyId, cid = childId
        _vaccines = Query(
            filter: #Predicate<KBVaccine> { $0.familyId == fid && $0.childId == cid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBVaccine.administeredDate, order: .reverse)]
        )
    }
    
    // Raggruppati per stato
    private var administered: [KBVaccine] { vaccines.filter { $0.status == .administered } }
    private var scheduled:    [KBVaccine] { vaccines.filter { $0.status == .scheduled } }
    private var planned:      [KBVaccine] { vaccines.filter { $0.status == .planned } }
    
    var body: some View {
        Group {
            if vaccines.isEmpty {
                emptyState
            } else {
                List {
                    if !scheduled.isEmpty {
                        Section("Appuntamento fissato") {
                            ForEach(scheduled) { row($0) }
                        }
                    }
                    if !administered.isEmpty {
                        Section("Somministrati") {
                            ForEach(administered) { row($0) }
                                .onDelete { deleteVaccines(offsets: $0, from: administered) }
                        }
                    }
                    if !planned.isEmpty {
                        Section("Da programmare") {
                            ForEach(planned) { row($0) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Vaccini")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editingVaccineId = nil; showEditSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            PediatricVaccineEditView(familyId: familyId, childId: childId, vaccineId: editingVaccineId)
        }
    }
    
    private func row(_ v: KBVaccine) -> some View {
        Button {
            editingVaccineId = v.id
            showEditSheet = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.12)).frame(width: 40, height: 40)
                    Image(systemName: v.vaccineType.systemImage)
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(v.vaccineType.displayName)
                        .font(.subheadline.bold())
                    if let cn = v.commercialName, !cn.isEmpty {
                        Text(cn).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Dose \(v.doseNumber) di \(v.totalDoses)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let d = v.administeredDate ?? v.scheduledDate {
                    Text(d.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 80, height: 80)
                Image(systemName: "syringe.fill").font(.system(size: 32)).foregroundStyle(tint)
            }
            Text("Libretto Vaccinale Vuoto").font(.title3.bold())
            Text("Inizia a registrare i vaccini per tenere traccia del calendario vaccinale del tuo bambino")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button { editingVaccineId = nil; showEditSheet = true } label: {
                Label("Aggiungi il primo vaccino", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Capsule().fill(tint))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showEditSheet) {
            PediatricVaccineEditView(familyId: familyId, childId: childId, vaccineId: nil)
        }
    }
    
    private func deleteVaccines(offsets: IndexSet, from list: [KBVaccine]) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        for i in offsets { list[i].isDeleted = true; list[i].updatedBy = uid; list[i].updatedAt = Date() }
        try? modelContext.save()
    }
}

// MARK: - Edit sheet

struct PediatricVaccineEditView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let familyId: String
    let childId: String
    let vaccineId: String?
    
    @State private var vaccineType: VaccineType = .esavalente
    @State private var status: VaccineStatus   = .administered
    @State private var commercialName = ""
    @State private var doseNumber = 1
    @State private var totalDoses = 1
    @State private var administeredDate = Date()
    @State private var scheduledDate    = Date()
    @State private var lotNumber        = ""
    @State private var administeredBy   = ""
    @State private var adminSite        = ""
    @State private var notes            = ""
    
    private let sites = ["Braccio sinistro", "Braccio destro", "Coscia sinistra", "Coscia destra", "Orale", "Nasale", "Altro"]
    private let tint  = Color(red: 0.95, green: 0.55, blue: 0.45)
    
    private var isEditing: Bool { vaccineId != nil }
    
    var body: some View {
        NavigationStack {
            Form {
                // ── Stato ──
                Section("Stato vaccino") {
                    ForEach([VaccineStatus.administered, .scheduled, .planned], id: \.self) { s in
                        HStack {
                            statusIcon(s)
                            Text(s.displayName)
                            Spacer()
                            if status == s { Image(systemName: "checkmark").foregroundStyle(tint) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { status = s }
                    }
                }
                
                // ── Tipo ──
                Section("Tipo di Vaccino") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(VaccineType.allCases, id: \.self) { t in
                            vaccineTypeCell(t)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    
                    TextField("Nome commerciale (opzionale)", text: $commercialName)
                }
                
                // ── Dose ──
                Section("Informazioni Dose") {
                    Stepper("Dose N° \(doseNumber)", value: $doseNumber, in: 1...10)
                    Stepper("Dosi Totali \(totalDoses)", value: $totalDoses, in: 1...10)
                }
                
                // ── Data ──
                Section(status == .administered ? "Data Somministrazione" : "Data Appuntamento") {
                    if status == .administered {
                        DatePicker("Data", selection: $administeredDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                    } else if status == .scheduled {
                        DatePicker("Data appuntamento", selection: $scheduledDate, displayedComponents: .date)
                    }
                }
                
                // ── Dettagli ──
                if status == .administered {
                    Section("Dettagli (opzionali)") {
                        TextField("Numero lotto", text: $lotNumber)
                        TextField("Somministrato da", text: $administeredBy)
                        Picker("Sito di somministrazione", selection: $adminSite) {
                            Text("Non specificato").tag("")
                            ForEach(sites, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
                
                Section("Note") {
                    TextField("Note aggiuntive", text: $notes, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle(isEditing ? "Modifica vaccino" : "Nuovo Vaccino")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Salva") { save() }.bold() }
            }
            .onAppear { loadIfEditing() }
        }
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
            .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? tint : Color(.systemGray6)))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func statusIcon(_ s: VaccineStatus) -> some View {
        switch s {
        case .administered: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .scheduled:    Image(systemName: "calendar.badge.clock").foregroundStyle(.blue)
        case .planned:      Image(systemName: "clock.badge.questionmark").foregroundStyle(.orange)
        }
    }
    
    private func loadIfEditing() {
        guard let vid = vaccineId else { return }
        let desc = FetchDescriptor<KBVaccine>(predicate: #Predicate { $0.id == vid })
        guard let v = try? modelContext.fetch(desc).first else { return }
        vaccineType      = v.vaccineType
        status           = v.status
        commercialName   = v.commercialName ?? ""
        doseNumber       = v.doseNumber
        totalDoses       = v.totalDoses
        if let d = v.administeredDate { administeredDate = d }
        if let d = v.scheduledDate    { scheduledDate    = d }
        lotNumber        = v.lotNumber ?? ""
        administeredBy   = v.administeredBy ?? ""
        adminSite        = v.administrationSiteRaw ?? ""
        notes            = v.notes ?? ""
    }
    
    private func save() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        if let vid = vaccineId {
            let desc = FetchDescriptor<KBVaccine>(predicate: #Predicate { $0.id == vid })
            guard let v = try? modelContext.fetch(desc).first else { return }
            applyFields(to: v, uid: uid, now: now)
        } else {
            let v = KBVaccine(familyId: familyId, childId: childId,
                              vaccineType: vaccineType, status: status,
                              createdAt: now, updatedAt: now, updatedBy: uid, createdBy: uid)
            modelContext.insert(v)
            applyFields(to: v, uid: uid, now: now)
        }
        try? modelContext.save()
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
        case .scheduled:    return "Appuntamento fissato"
        case .planned:      return "Da programmare"
        }
    }
}
