//
//  PediatricVisitsView.swift
//  KidBox
//
//  Created by vscocca on 03/03/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - List

struct PediatricVisitsView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query private var visits: [KBMedicalVisit]
    
    let familyId: String
    let childId: String
    
    @State private var showEditSheet = false
    @State private var editingVisitId: String? = nil
    
    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId  = childId
        let fid = familyId, cid = childId
        _visits = Query(
            filter: #Predicate<KBMedicalVisit> { $0.familyId == fid && $0.childId == cid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBMedicalVisit.date, order: .reverse)]
        )
    }
    
    var body: some View {
        Group {
            if visits.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(visits) { visit in
                        visitRow(visit)
                    }
                    .onDelete(perform: deleteVisits)
                }
            }
        }
        .navigationTitle("Visite Mediche")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editingVisitId = nil; showEditSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            PediatricVisitEditView(familyId: familyId, childId: childId, visitId: editingVisitId)
        }
    }
    
    private func visitRow(_ visit: KBMedicalVisit) -> some View {
        Button {
            editingVisitId = visit.id
            showEditSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(visit.date.formatted(.dateTime.day().month(.wide).year()))
                        .font(.subheadline.bold())
                    Spacer()
                    if let doc = visit.doctorName {
                        Text(doc).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(visit.reason)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let dx = visit.diagnosis {
                    Text(dx).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "stethoscope")
                .font(.system(size: 52))
                .foregroundStyle(Color(red: 0.35, green: 0.6, blue: 0.85).opacity(0.5))
            Text("Nessuna visita registrata")
                .font(.title3.bold())
            Text("Registra le visite mediche per tenere traccia della salute del tuo bambino")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button { editingVisitId = nil; showEditSheet = true } label: {
                Label("Aggiungi prima visita", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Capsule().fill(Color(red: 0.35, green: 0.6, blue: 0.85)))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showEditSheet) {
            PediatricVisitEditView(familyId: familyId, childId: childId, visitId: nil)
        }
    }
    
    private func deleteVisits(offsets: IndexSet) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        for i in offsets {
            let v = visits[i]
            v.isDeleted = true; v.updatedBy = uid; v.updatedAt = now
        }
        try? modelContext.save()
    }
}

// MARK: - Edit sheet

struct PediatricVisitEditView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let familyId: String
    let childId: String
    let visitId: String?
    
    @State private var date = Date()
    @State private var doctorName = ""
    @State private var reason = ""
    @State private var diagnosis = ""
    @State private var notes = ""
    @State private var nextVisitDate: Date? = nil
    @State private var showNextVisit = false
    
    private var isEditing: Bool { visitId != nil }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Visita") {
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                    TextField("Dottore (opzionale)", text: $doctorName)
                    TextField("Motivo della visita", text: $reason)
                }
                Section("Esito") {
                    TextField("Diagnosi (opzionale)", text: $diagnosis)
                    TextField("Note", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    Toggle("Prossima visita", isOn: $showNextVisit)
                    if showNextVisit {
                        DatePicker("Data prossima visita",
                                   selection: Binding(get: { nextVisitDate ?? Date() }, set: { nextVisitDate = $0 }),
                                   displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(isEditing ? "Modifica visita" : "Nuova visita")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") { save() }
                        .bold()
                        .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadIfEditing() }
        }
    }
    
    private func loadIfEditing() {
        guard let vid = visitId else { return }
        let desc = FetchDescriptor<KBMedicalVisit>(predicate: #Predicate { $0.id == vid })
        guard let v = try? modelContext.fetch(desc).first else { return }
        date       = v.date
        doctorName = v.doctorName ?? ""
        reason     = v.reason
        diagnosis  = v.diagnosis ?? ""
        notes      = v.notes ?? ""
        nextVisitDate = v.nextVisitDate
        showNextVisit = v.nextVisitDate != nil
    }
    
    private func save() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        if let vid = visitId {
            let desc = FetchDescriptor<KBMedicalVisit>(predicate: #Predicate { $0.id == vid })
            guard let v = try? modelContext.fetch(desc).first else { return }
            v.date = date; v.doctorName = doctorName.isEmpty ? nil : doctorName
            v.reason = reason; v.diagnosis = diagnosis.isEmpty ? nil : diagnosis
            v.notes = notes.isEmpty ? nil : notes
            v.nextVisitDate = showNextVisit ? nextVisitDate : nil
            v.updatedBy = uid; v.updatedAt = now
        } else {
            let v = KBMedicalVisit(
                familyId: familyId, childId: childId,
                date: date, doctorName: doctorName.isEmpty ? nil : doctorName,
                reason: reason, diagnosis: diagnosis.isEmpty ? nil : diagnosis,
                notes: notes.isEmpty ? nil : notes,
                nextVisitDate: showNextVisit ? nextVisitDate : nil,
                createdAt: now, updatedAt: now, updatedBy: uid, createdBy: uid
            )
            modelContext.insert(v)
        }
        try? modelContext.save()
        dismiss()
    }
}
