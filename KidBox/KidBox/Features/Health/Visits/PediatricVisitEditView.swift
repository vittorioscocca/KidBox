//
//  PediatricVisitEditView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Wizard root

struct PediatricVisitEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    let familyId: String
    let childId: String
    let childName: String
    let visitId: String?   // nil = nuova visita, non-nil = modifica esistente
    
    private var isEditing: Bool { visitId != nil }
    
    // Step state
    @State private var currentStep = 0
    private let totalSteps = 5
    
    // ── Step 1: Medico & Data ──
    @State private var doctorSearchText   = ""
    @State private var selectedDoctorName = ""
    @State private var selectedSpec: KBDoctorSpecialization? = nil
    @State private var customSpecText     = ""
    @State private var visitDate          = Date()
    @State private var reason             = ""
    @State private var showNewDoctorForm  = false
    @State private var visitStatus: KBVisitStatus = .pending
    @State private var visitReminderOn    = false
    
    @Query private var recentVisitsQ: [KBMedicalVisit]
    
    // ── Step 2: Esito ──
    @State private var diagnosis        = ""
    @State private var recommendations  = ""
    
    // ── Step 3: Prescrizioni ──
    @State private var linkedTreatmentIds: [String]      = []
    @State private var asNeededDrugs:  [KBAsNeededDrug]  = []
    @State private var therapyTypes:   [KBTherapyType]   = []
    @State private var linkedExamIds:  [String]          = []   // ← esami standalone KBMedicalExam
    @State private var prescriptionsTab      = 0
    @State private var showAddExamSheet      = false
    @State private var showAddDrugSheet      = false
    @State private var showAddTreatmentSheet = false
    @State private var editingDrug: KBAsNeededDrug? = nil
    
    // ── Step 4: Foto & Appunti ──
    @State private var notes = ""
    @State private var pendingAttachmentURLs:  [URL]  = []
    @State private var showAttachmentPicker   = false
    @State private var showAttachmentGallery  = false
    @State private var showAttachmentCamera   = false
    @State private var showAttachmentImporter = false
    
    // ── Step 5: Riepilogo ──
    @State private var hasNextVisit      = false
    @State private var nextVisitDate     = Date()
    @State private var nextVisitReminder = true   // promemoria giorno prima, default on
    
    @State private var isSaving = false
    
    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)
    
    init(familyId: String, childId: String, childName: String, visitId: String? = nil) {
        self.familyId  = familyId
        self.childId   = childId
        self.childName = childName
        self.visitId   = visitId
        let fid = familyId
        _recentVisitsQ = Query(
            filter: #Predicate<KBMedicalVisit> { $0.familyId == fid },
            sort: [SortDescriptor(\KBMedicalVisit.date, order: .reverse)]
        )
    }
    
    private var recentDoctors: [(name: String, spec: String)] {
        var seen = Set<String>()
        var result: [(String, String)] = []
        for v in recentVisitsQ {
            guard v.childId == childId, !v.isDeleted else { continue }
            guard let name = v.doctorName, !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            result.append((name, v.doctorSpecializationRaw ?? ""))
            if result.count == 5 { break }
        }
        return result
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepProgressBar
                Group {
                    switch currentStep {
                    case 0: step1DoctorDate
                    case 1: step2Outcome
                    case 2: step3Prescriptions
                    case 3: step4PhotoNotes
                    case 4: step5Summary
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomNav
            }
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle(isEditing ? "Modifica Visita" : "Visita Medica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
            }
            .onAppear { loadIfEditing() }
            // FIX BUG 1: sheet agganciato al NavigationStack root (non alla computed var
            // prescriptionsTabExams che viene smontata quando si avanza allo step 5).
            // In questo modo onSaved aggiorna linkedExamIds anche dopo aver cambiato step.
            //
            // FIX BUG 2: usiamo PediatricExamEditView invece di AddExamSheet.
            // PediatricExamEditView chiama onSaved DOPO aver fatto modelContext.save(),
            // quindi quando linkedExamIds riceve il nuovo id il record esiste già nella
            // @Query di LinkedExamCard e SummaryLinkedExamRow — nessun race condition.
            .sheet(isPresented: $showAddExamSheet) {
                PediatricExamEditView(
                    familyId: familyId,
                    childId: childId,
                    childName: childName,
                    examId: nil,
                    prescribingVisitId: visitId,
                    onSaved: { newExamId in
                        if !linkedExamIds.contains(newExamId) {
                            linkedExamIds.append(newExamId)
                        }
                    }
                )
            }
        }
        .environment(\.locale, Locale(identifier: "it_IT"))
    }
    
    // MARK: - Progress bar
    
    private var stepProgressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= currentStep ? tint : Color.secondary.opacity(0.25))
                    .frame(height: 3)
                    .animation(.easeInOut, value: currentStep)
            }
        }
        .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)
    }
    
    // MARK: - Bottom nav
    
    private var bottomNav: some View {
        HStack(spacing: 12) {
            if currentStep > 0 {
                Button { withAnimation { currentStep -= 1 } } label: {
                    Label("Indietro", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.12)))
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                        .font(.headline)
                }
                .buttonStyle(.plain)
            }
            if currentStep < totalSteps - 1 {
                Button { withAnimation { currentStep += 1 } } label: {
                    HStack {
                        Text("Avanti")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(canAdvance ? tint : tint.opacity(0.4)))
                    .foregroundStyle(.white).font(.headline)
                }
                .buttonStyle(.plain)
                .disabled(!canAdvance)
            } else {
                Button { save() } label: {
                    HStack {
                        Text(isSaving ? "Salvataggio..." : "Salva")
                        Image(systemName: "checkmark")
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(tint))
                    .foregroundStyle(.white).font(.headline)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
        .padding(.horizontal).padding(.vertical, 12)
        .background(KBTheme.background(colorScheme))
    }
    
    private var canAdvance: Bool {
        switch currentStep {
        case 0: return !reason.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }
    
    // MARK: ── Step 1 ──
    
    private var step1DoctorDate: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tipo di Visita").font(.title3.bold()).padding(.horizontal)
                    Text("Es. Visita Urologica, Controllo Pediatrico...")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    TextField("Visita...", text: $reason)
                        .font(.headline).padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
                        .padding(.horizontal)
                }
                Divider().padding(.horizontal)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Medico", systemImage: "person.fill").font(.headline).padding(.horizontal)
                    if !selectedDoctorName.isEmpty && !showNewDoctorForm {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(tint.opacity(0.12)).frame(width: 44, height: 44)
                                Image(systemName: "person.fill").foregroundStyle(tint)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedDoctorName).font(.subheadline.bold())
                                if let s = selectedSpec { Text(s.rawValue).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button {
                                selectedDoctorName = ""; selectedSpec = nil; doctorSearchText = ""
                            } label: {
                                Text("Cambia").font(.caption.bold()).foregroundStyle(tint)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(tint.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.06)))
                        .padding(.horizontal)
                    } else {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Cerca medico...", text: $doctorSearchText)
                                .onChange(of: doctorSearchText) { _, v in if !v.isEmpty { showNewDoctorForm = false } }
                            if !doctorSearchText.isEmpty {
                                Button { doctorSearchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
                        .padding(.horizontal)
                        
                        let filtered = recentDoctors.filter {
                            doctorSearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(doctorSearchText)
                        }
                        if !filtered.isEmpty && !showNewDoctorForm {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Medici Recenti").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                                ForEach(filtered, id: \.name) { doc in
                                    Button {
                                        selectedDoctorName = doc.name
                                        selectedSpec = KBDoctorSpecialization(rawValue: doc.spec)
                                        showNewDoctorForm = false; doctorSearchText = ""
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "person.circle.fill").font(.title3).foregroundStyle(tint)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(doc.name).font(.subheadline.bold()).foregroundStyle(KBTheme.primaryText(colorScheme))
                                                if !doc.spec.isEmpty { Text(doc.spec).font(.caption).foregroundStyle(.secondary) }
                                            }
                                            Spacer()
                                        }
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
                                    }
                                    .buttonStyle(.plain).padding(.horizontal)
                                }
                            }
                        }
                        Button {
                            showNewDoctorForm = true; selectedDoctorName = doctorSearchText
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Nuovo Medico").font(.subheadline.bold())
                                        .foregroundStyle(showNewDoctorForm ? tint : KBTheme.primaryText(colorScheme))
                                    Text("es. Pediatra, Dermatologo").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if showNewDoctorForm { Image(systemName: "checkmark.circle.fill").foregroundStyle(tint) }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(showNewDoctorForm ? tint.opacity(0.08) : Color.secondary.opacity(0.06)))
                        }
                        .buttonStyle(.plain).padding(.horizontal)
                        
                        if showNewDoctorForm {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Nome Medico").font(.caption.bold()).foregroundStyle(.secondary)
                                TextField("es. Dott. Rossi", text: $selectedDoctorName)
                                    .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                                Text("Specializzazione").font(.caption.bold()).foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(KBDoctorSpecialization.allCases, id: \.self) { s in
                                            Button { selectedSpec = s } label: {
                                                Text(s.rawValue).font(.caption)
                                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                                    .background(Capsule().fill(selectedSpec == s ? tint : Color.secondary.opacity(0.12)))
                                                    .foregroundStyle(selectedSpec == s ? .white : KBTheme.primaryText(colorScheme))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                Button {
                                    showNewDoctorForm = false; doctorSearchText = ""
                                } label: {
                                    Text("Conferma").font(.subheadline.bold())
                                        .frame(maxWidth: .infinity).padding(10)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(tint))
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                                .disabled(selectedDoctorName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                Divider().padding(.horizontal)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Data Visita", systemImage: "calendar").font(.headline).padding(.horizontal)
                    DatePicker("", selection: $visitDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact).labelsHidden().padding(.horizontal)
                    // ── Promemoria visita ──
                    HStack(spacing: 12) {
                        Image(systemName: visitReminderOn ? "bell.fill" : "bell")
                            .foregroundStyle(visitReminderOn ? tint : .secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Promemoria il giorno prima")
                                .font(.subheadline)
                            Text("Notifica alle 09:00")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $visitReminderOn)
                            .labelsHidden()
                            .tint(tint)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }
                Divider().padding(.horizontal)
                // ── Stato visita ──
                VStack(alignment: .leading, spacing: 8) {
                    Label("Stato Visita", systemImage: "flag.fill").font(.headline).padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(KBVisitStatus.allCases, id: \.self) { s in
                                Button { visitStatus = s } label: {
                                    Label(s.rawValue, systemImage: s.icon)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(
                                            Capsule().fill(visitStatus == s ? tint : Color.secondary.opacity(0.1))
                                        )
                                        .foregroundStyle(visitStatus == s ? .white : KBTheme.primaryText(colorScheme))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }
    
    // MARK: ── Step 2 ──
    
    private var step2Outcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Esito della Visita").font(.title3.bold()).padding(.horizontal)
                sectionCard(icon: "stethoscope", title: "Diagnosi") {
                    TextField("Diagnosi o conclusioni del medico", text: $diagnosis, axis: .vertical).lineLimit(3...6)
                }
                sectionCard(icon: "lightbulb.fill", title: "Raccomandazioni") {
                    TextField("Consigli generali del medico", text: $recommendations, axis: .vertical).lineLimit(3...6)
                }
            }
            .padding(.vertical)
        }
    }
    
    // MARK: ── Step 3 ──
    
    private var step3Prescriptions: some View {
        VStack(spacing: 0) {
            let totalRx = linkedExamIds.count + asNeededDrugs.count + therapyTypes.count + linkedTreatmentIds.count
            HStack {
                Text("Prescrizioni").font(.title3.bold())
                Spacer()
                if totalRx > 0 {
                    Text("\(totalRx)").font(.caption.bold()).foregroundStyle(.white)
                        .frame(width: 24, height: 24).background(Circle().fill(tint))
                }
            }
            .padding(.horizontal).padding(.top, 12)
            
            let tabs   = ["Farmaci", "Al bisogno", "Tipo di Terapia", "Esami Prescritti"]
            let icons  = ["pills.fill", "cross.vial.fill", "figure.walk", "testtube.2"]
            let counts = [linkedTreatmentIds.count, asNeededDrugs.count, therapyTypes.count, linkedExamIds.count]
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs.indices, id: \.self) { i in
                        Button { withAnimation { prescriptionsTab = i } } label: {
                            ZStack(alignment: .topTrailing) {
                                VStack(spacing: 4) {
                                    Image(systemName: icons[i]).font(.system(size: 18))
                                    Text(tabs[i]).font(.caption2)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(prescriptionsTab == i ? tint : Color.clear)
                                .foregroundStyle(prescriptionsTab == i ? .white : KBTheme.secondaryText(colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                if counts[i] > 0 {
                                    Text("\(counts[i])").font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white).frame(width: 16, height: 16)
                                        .background(Circle().fill(prescriptionsTab == i ? Color.white.opacity(0.9) : tint))
                                        .offset(x: -4, y: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                switch prescriptionsTab {
                case 0: prescriptionsTabFarmaci
                case 1: prescriptionsTabAsNeeded
                case 2: prescriptionsTabTherapy
                case 3: prescriptionsTabExams
                default: EmptyView()
                }
            }
        }
    }
    
    private var prescriptionsTabFarmaci: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Farmaci Programmati").font(.headline).padding(.horizontal)
            Text("Farmaci con orari programmati da assumere regolarmente")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            if !linkedTreatmentIds.isEmpty {
                VStack(spacing: 8) {
                    ForEach(linkedTreatmentIds, id: \.self) { tid in
                        LinkedTreatmentCard(treatmentId: tid, tint: tint, colorScheme: colorScheme) {
                            linkedTreatmentIds.removeAll { $0 == tid }
                            let desc = FetchDescriptor<KBTreatment>(predicate: #Predicate { $0.id == tid })
                            if let t = try? modelContext.fetch(desc).first {
                                t.isDeleted = true; try? modelContext.save()
                            }
                        }
                    }
                }
                .padding(.horizontal)
            } else {
                emptyPrescriptionState(icon: "pills", text: "Nessun farmaco programmato")
            }
            Button { showAddTreatmentSheet = true } label: {
                Label("Aggiungi Cura", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity).padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.12)))
                    .foregroundStyle(tint).font(.subheadline.bold())
            }
            .buttonStyle(.plain).padding(.horizontal)
            Button { withAnimation { currentStep += 1 } } label: {
                Text("Salta le prescrizioni").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical)
        .sheet(isPresented: $showAddTreatmentSheet) {
            PediatricTreatmentEditView(
                familyId: familyId, childId: childId, childName: childName, treatmentId: nil,
                onSaved: { savedId in linkedTreatmentIds.append(savedId) }
            )
        }
    }
    
    private var prescriptionsTabAsNeeded: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Al bisogno").font(.headline).padding(.horizontal)
            if asNeededDrugs.isEmpty {
                emptyPrescriptionState(icon: "cross.vial.fill", text: "Nessun farmaco al bisogno")
            } else {
                VStack(spacing: 8) {
                    ForEach(asNeededDrugs) { d in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(tint.opacity(0.12)).frame(width: 40, height: 40)
                                Image(systemName: "cross.vial.fill").foregroundStyle(tint).font(.subheadline)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(d.drugName).font(.subheadline.bold())
                                Text("\(d.dosageValue, specifier: "%.0f") \(d.dosageUnit)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let instr = d.instructions, !instr.isEmpty {
                                    Text(instr).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Button { editingDrug = d } label: {
                                Image(systemName: "pencil.circle.fill").foregroundStyle(tint).font(.title3)
                            }
                            .buttonStyle(.plain)
                            Button { asNeededDrugs.removeAll { $0.id == d.id } } label: {
                                Image(systemName: "trash.fill").foregroundStyle(.red).font(.subheadline)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04)))
                    }
                }
                .padding(.horizontal)
            }
            Button { showAddDrugSheet = true } label: {
                Label("Aggiungi Farmaco", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity).padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.12)))
                    .foregroundStyle(tint).font(.subheadline.bold())
            }
            .buttonStyle(.plain).padding(.horizontal)
        }
        .padding(.vertical)
        .sheet(isPresented: $showAddDrugSheet) {
            AddAsNeededDrugSheet(tint: tint) { drug in asNeededDrugs.append(drug) }
        }
        .sheet(item: $editingDrug) { drug in
            EditAsNeededDrugSheet(tint: tint, drug: drug) { updated in
                if let idx = asNeededDrugs.firstIndex(where: { $0.id == updated.id }) {
                    asNeededDrugs[idx] = updated
                }
            }
        }
    }
    
    private var prescriptionsTabTherapy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tipo di Terapia").font(.headline).padding(.horizontal)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(KBTherapyType.allCases, id: \.self) { t in
                    Button {
                        if therapyTypes.contains(t) { therapyTypes.removeAll { $0 == t } }
                        else { therapyTypes.append(t) }
                    } label: {
                        Text(t.rawValue).font(.subheadline)
                            .frame(maxWidth: .infinity).padding(10)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(therapyTypes.contains(t) ? tint : Color.secondary.opacity(0.1)))
                            .foregroundStyle(therapyTypes.contains(t) ? .white : KBTheme.primaryText(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
    
    // ── Esami: usa KBMedicalExam standalone ──
    private var prescriptionsTabExams: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Esami Prescritti").font(.headline)
                Spacer()
                if !linkedExamIds.isEmpty {
                    Text("\(linkedExamIds.count)").font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(tint))
                }
            }
            .padding(.horizontal)
            Text("Esami del sangue, ecografie e altri controlli prescritti")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            
            if linkedExamIds.isEmpty {
                emptyPrescriptionState(icon: "testtube.2", text: "Nessun esame prescritto")
            } else {
                VStack(spacing: 8) {
                    ForEach(linkedExamIds, id: \.self) { eid in
                        LinkedExamCard(
                            examId: eid,
                            familyId: familyId,
                            childId: childId,
                            childName: childName,
                            tint: tint,
                            colorScheme: colorScheme
                        ) {
                            linkedExamIds.removeAll { $0 == eid }
                            let desc = FetchDescriptor<KBMedicalExam>(predicate: #Predicate { $0.id == eid })
                            if let e = try? modelContext.fetch(desc).first {
                                e.isDeleted = true; try? modelContext.save()
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            Button { showAddExamSheet = true } label: {
                Label(linkedExamIds.isEmpty ? "Aggiungi un esame" : "Aggiungi un altro esame",
                      systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity).padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.12)))
                .foregroundStyle(tint).font(.subheadline.bold())
            }
            .buttonStyle(.plain).padding(.horizontal)
        }
        .padding(.vertical)
    }
    
    // MARK: ── Step 4 ──
    
    private var step4PhotoNotes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isEditing, let vid = visitId {
                    ExistingVisitAttachmentsInEdit(visitId: vid, familyId: familyId, tint: tint)
                        .padding(.horizontal)
                }
                VisitAttachmentPicker(
                    pendingURLs: $pendingAttachmentURLs,
                    onAddTapped: { showAttachmentPicker = true }
                )
                .padding(.horizontal)
                sectionCard(icon: "square.and.pencil", title: "Appunti della Visita") {
                    TextField("Aggiungi note sulla visita...", text: $notes, axis: .vertical).lineLimit(4...8)
                }
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showAttachmentPicker) {
            AttachmentSourcePickerSheet(
                tint: tint,
                onCamera: {
                    showAttachmentPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showAttachmentCamera = true }
                },
                onGallery: {
                    showAttachmentPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showAttachmentGallery = true }
                },
                onDocument: {
                    showAttachmentPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showAttachmentImporter = true }
                }
            )
            .presentationDetents([.height(250)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAttachmentGallery) {
            ImagePickerView(sourceType: .photoLibrary) { image in
                if let url = saveImageToTemp(image) { pendingAttachmentURLs.append(url) }
            }
        }
        .sheet(isPresented: $showAttachmentCamera) {
            ImagePickerView(sourceType: .camera) { image in
                if let url = saveImageToTemp(image) { pendingAttachmentURLs.append(url) }
            }
        }
        .fileImporter(
            isPresented: $showAttachmentImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if let urls = try? result.get() {
                let available = 5 - pendingAttachmentURLs.count
                pendingAttachmentURLs.append(contentsOf: urls.prefix(available))
            }
        }
    }
    
    private func saveImageToTemp(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try? data.write(to: url)
        return url
    }
    
    // MARK: ── Step 5: Riepilogo ──
    
    private var step5Summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Riepilogo Visita").font(.title3.bold()).padding(.horizontal)
                
                summaryRow(icon: "stethoscope", title: "Tipo di Visita") {
                    Text(reason).font(.subheadline.bold())
                }
                if !selectedDoctorName.isEmpty {
                    summaryRow(icon: "person.fill", title: "Nome Medico") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedDoctorName).font(.subheadline.bold())
                            if let s = selectedSpec { Text(s.rawValue).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                summaryRow(icon: "calendar", title: "Data e Ora Visita") {
                    Text(italianDateTime(visitDate)).font(.subheadline.bold())
                }
                if !diagnosis.isEmpty {
                    summaryRow(icon: "stethoscope", title: "Diagnosi") { Text(diagnosis).font(.subheadline) }
                }
                if !recommendations.isEmpty {
                    summaryRow(icon: "lightbulb.fill", title: "Raccomandazioni") { Text(recommendations).font(.subheadline) }
                }
                if !linkedTreatmentIds.isEmpty {
                    summaryRow(icon: "pills.fill", title: "Farmaci Programmati (\(linkedTreatmentIds.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(linkedTreatmentIds, id: \.self) { tid in SummaryLinkedTreatmentRow(treatmentId: tid) }
                        }
                    }
                }
                if !asNeededDrugs.isEmpty {
                    summaryRow(icon: "cross.vial.fill", title: "Al Bisogno (\(asNeededDrugs.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(asNeededDrugs) { d in
                                HStack(spacing: 6) {
                                    Circle().fill(tint.opacity(0.4)).frame(width: 6, height: 6)
                                    Text(d.drugName).font(.subheadline)
                                    Text("· \(d.dosageValue, specifier: "%.0f") \(d.dosageUnit)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !therapyTypes.isEmpty {
                    summaryRow(icon: "figure.walk", title: "Terapie (\(therapyTypes.count))") {
                        Text(therapyTypes.map { $0.rawValue }.joined(separator: ", ")).font(.subheadline)
                    }
                }
                // ← Esami: linkedExamIds con SummaryLinkedExamRow
                if !linkedExamIds.isEmpty {
                    summaryRow(icon: "testtube.2", title: "Esami Prescritti (\(linkedExamIds.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(linkedExamIds, id: \.self) { eid in SummaryLinkedExamRow(examId: eid) }
                        }
                    }
                }
                if !pendingAttachmentURLs.isEmpty {
                    summaryRow(icon: "paperclip", title: "Allegati (\(pendingAttachmentURLs.count))") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(pendingAttachmentURLs, id: \.absoluteString) { url in
                                    if let img = UIImage(contentsOfFile: url.path) {
                                        Image(uiImage: img).resizable().scaledToFill()
                                            .frame(width: 56, height: 56)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1)).frame(width: 56, height: 56)
                                            Image(systemName: "doc.fill").foregroundStyle(tint)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Prossimo Appuntamento", systemImage: "calendar.badge.plus").font(.subheadline.bold())
                        Spacer()
                        Toggle("", isOn: $hasNextVisit).labelsHidden()
                    }
                    if hasNextVisit {
                        DatePicker("", selection: $nextVisitDate, in: Date()..., displayedComponents: [.date])
                            .datePickerStyle(.compact).labelsHidden()
                        Text(italianDateOnly(nextVisitDate)).font(.caption).foregroundStyle(.secondary)
                        Divider()
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: nextVisitReminder ? "bell.fill" : "bell.slash.fill")
                                    .foregroundStyle(nextVisitReminder ? tint : .secondary)
                                    .font(.subheadline)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Promemoria il giorno prima")
                                        .font(.subheadline)
                                    Text("Notifica alle 09:00")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: $nextVisitReminder).labelsHidden().tint(tint)
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Load & Save
    
    private func loadIfEditing() {
        guard let vid = visitId else { return }
        let desc = FetchDescriptor<KBMedicalVisit>(predicate: #Predicate { $0.id == vid })
        guard let v = try? modelContext.fetch(desc).first else { return }
        reason             = v.reason
        selectedDoctorName = v.doctorName ?? ""
        selectedSpec       = v.doctorSpecialization
        visitDate          = v.date
        diagnosis          = v.diagnosis ?? ""
        recommendations    = v.recommendations ?? ""
        linkedTreatmentIds = v.linkedTreatmentIds
        asNeededDrugs      = v.asNeededDrugs
        therapyTypes       = v.therapyTypes
        linkedExamIds      = v.linkedExamIds   // ← legge linkedExamIds da KBMedicalVisit
        notes              = v.notes ?? ""
        hasNextVisit       = v.nextVisitDate != nil
        nextVisitDate      = v.nextVisitDate ?? Date()
        visitStatus        = v.visitStatus ?? .pending
        visitReminderOn    = v.reminderOn
        nextVisitReminder  = v.nextVisitReminderOn
    }
    
    private func save() {
        isSaving = true
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        // Collega prescribingVisitId sugli esami creati prima di avere l'id visita
        func linkExamsToVisit(_ vid: String) {
            for eid in linkedExamIds {
                let desc = FetchDescriptor<KBMedicalExam>(predicate: #Predicate { $0.id == eid })
                if let e = try? modelContext.fetch(desc).first, e.prescribingVisitId == nil {
                    e.prescribingVisitId = vid
                    e.updatedAt = now; e.updatedBy = uid; e.syncState = .pendingUpsert
                    SyncCenter.shared.enqueueMedicalExamUpsert(examId: e.id, familyId: familyId, modelContext: modelContext)
                }
            }
        }
        
        // ── Modifica visita esistente ──
        if let vid = visitId {
            let desc = FetchDescriptor<KBMedicalVisit>(predicate: #Predicate { $0.id == vid })
            guard let v = try? modelContext.fetch(desc).first else { isSaving = false; return }
            v.reason             = reason
            v.doctorName         = selectedDoctorName.isEmpty ? nil : selectedDoctorName
            v.doctorSpecialization = selectedSpec
            v.date               = visitDate
            v.diagnosis          = diagnosis.isEmpty ? nil : diagnosis
            v.recommendations    = recommendations.isEmpty ? nil : recommendations
            v.linkedTreatmentIds = linkedTreatmentIds
            v.asNeededDrugs      = asNeededDrugs
            v.therapyTypes       = therapyTypes
            v.linkedExamIds      = linkedExamIds
            v.notes              = notes.isEmpty ? nil : notes
            v.nextVisitDate      = hasNextVisit ? nextVisitDate : nil
            v.visitStatus        = visitStatus
            v.reminderOn         = visitReminderOn
            v.nextVisitReminderOn = hasNextVisit && nextVisitReminder
            v.updatedAt          = now; v.updatedBy = uid; v.syncState = .pendingUpsert
            linkExamsToVisit(vid)
            try? modelContext.save()
            SyncCenter.shared.enqueueVisitUpsert(visitId: v.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            // Promemoria data visita — usa KBVisitReminderService (stesso pattern di KBExamReminderService)
            if visitReminderOn {
                KBVisitReminderService.shared.scheduleVisitReminder(
                    visitId: v.id, date: visitDate, reason: v.reason,
                    childName: childName, familyId: familyId, childId: childId
                )
            } else {
                KBVisitReminderService.shared.cancelVisitReminder(visitId: v.id)
            }
            if hasNextVisit && nextVisitReminder {
                KBVisitReminderService.shared.scheduleNextVisitReminder(
                    visitId: v.id, date: nextVisitDate, reason: v.reason,
                    childName: childName, familyId: familyId, childId: childId
                )
            } else {
                KBVisitReminderService.shared.cancelNextVisitReminder(visitId: v.id)
            }
            if !pendingAttachmentURLs.isEmpty {
                KBEventBus.shared.emit(KBAppEvent.visitAttachmentPending(
                    urls: pendingAttachmentURLs, visitId: v.id, familyId: familyId, childId: childId
                ))
            }
            isSaving = false; dismiss(); return
        }
        
        // ── Nuova visita ──
        let visit = KBMedicalVisit(
            familyId:            familyId,
            childId:             childId,
            date:                visitDate,
            doctorName:          selectedDoctorName.isEmpty ? nil : selectedDoctorName,
            doctorSpecialization: selectedSpec,
            reason:              reason,
            diagnosis:           diagnosis.isEmpty ? nil : diagnosis,
            recommendations:     recommendations.isEmpty ? nil : recommendations,
            linkedTreatmentIds:  linkedTreatmentIds,
            linkedExamIds:       linkedExamIds, asNeededDrugs:       asNeededDrugs,
            therapyTypes:        therapyTypes,
            notes:               notes.isEmpty ? nil : notes,
            nextVisitDate:       hasNextVisit ? nextVisitDate : nil,
            visitStatus:         visitStatus,
            reminderOn:          visitReminderOn,
            nextVisitReminderOn: hasNextVisit && nextVisitReminder,
            createdAt:           now, updatedAt: now, updatedBy: uid, createdBy: uid
        )
        modelContext.insert(visit)
        linkExamsToVisit(visit.id)
        try? modelContext.save()
        SyncCenter.shared.enqueueVisitUpsert(visitId: visit.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        if visitReminderOn {
            KBVisitReminderService.shared.scheduleVisitReminder(
                visitId: visit.id, date: visitDate, reason: reason,
                childName: childName, familyId: familyId, childId: childId
            )
        }
        if hasNextVisit && nextVisitReminder {
            KBVisitReminderService.shared.scheduleNextVisitReminder(
                visitId: visit.id, date: nextVisitDate, reason: reason,
                childName: childName, familyId: familyId, childId: childId
            )
        }
        if !pendingAttachmentURLs.isEmpty {
            KBEventBus.shared.emit(KBAppEvent.visitAttachmentPending(
                urls: pendingAttachmentURLs, visitId: visit.id, familyId: familyId, childId: childId
            ))
        }
        isSaving = false; dismiss()
    }
    
    // MARK: - View helpers
    
    @ViewBuilder
    private func sectionCard<Content: View>(icon: String, title: String, badge: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon).font(.headline)
                Spacer()
                if let badge { Text(badge).font(.caption).foregroundStyle(.secondary) }
            }
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func summaryRow<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
        .padding(.horizontal)
    }
    
    private func emptyPrescriptionState(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(.secondary.opacity(0.5))
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }
    
    private func italianDateTime(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT")
        f.calendar = Calendar(identifier: .gregorian); f.dateStyle = .long; f.timeStyle = .short
        return f.string(from: date)
    }
    
    private func italianDateOnly(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT")
        f.calendar = Calendar(identifier: .gregorian); f.dateStyle = .long; f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - LinkedTreatmentCard

private struct LinkedTreatmentCard: View {
    let treatmentId: String; let tint: Color; let colorScheme: ColorScheme; let onRemove: () -> Void
    @Query private var treatments: [KBTreatment]
    private var treatment: KBTreatment? { treatments.first }
    
    init(treatmentId: String, tint: Color, colorScheme: ColorScheme, onRemove: @escaping () -> Void) {
        self.treatmentId = treatmentId; self.tint = tint; self.colorScheme = colorScheme; self.onRemove = onRemove
        let tid = treatmentId
        _treatments = Query(filter: #Predicate<KBTreatment> { $0.id == tid })
    }
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: "pills.fill").foregroundStyle(tint).font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(treatment?.drugName ?? "Farmaco").font(.subheadline.bold())
                if let t = treatment {
                    Text("\(t.dosageValue, specifier: "%.0f") \(t.dosageUnit) · \(t.dailyFrequency)x/die · \(t.isLongTerm ? "lungo termine" : "\(t.durationDays)gg")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onRemove) { Image(systemName: "trash.fill").foregroundStyle(.red).font(.subheadline) }
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04)))
    }
}

// MARK: - LinkedExamCard

private struct LinkedExamCard: View {
    let examId:    String
    let familyId:  String
    let childId:   String
    let childName: String
    let tint:      Color
    let colorScheme: ColorScheme
    let onRemove:  () -> Void
    
    @Query private var exams: [KBMedicalExam]
    private var exam: KBMedicalExam? { exams.first }
    
    // FIX: sheet(item:) con ExamSheetItem elimina il race condition —
    // il contenuto dello sheet viene costruito DOPO che l'item è impostato,
    // quindi loadIfEditing() riceve sempre l'examId corretto.
    @State private var editItem: ExamSheetItem? = nil
    
    init(examId: String, familyId: String, childId: String, childName: String,
         tint: Color, colorScheme: ColorScheme, onRemove: @escaping () -> Void) {
        self.examId    = examId
        self.familyId  = familyId
        self.childId   = childId
        self.childName = childName
        self.tint      = tint
        self.colorScheme = colorScheme
        self.onRemove  = onRemove
        let eid = examId
        _exams = Query(filter: #Predicate<KBMedicalExam> { $0.id == eid })
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: "testtube.2").foregroundStyle(tint).font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 3) {
                // Mostra il nome dell'esame: se @Query non ha ancora il record usa examId
                // come fallback leggibile, non "Esame" generico
                Text(exam?.name ?? "Caricamento...").font(.subheadline.bold())
                if let e = exam {
                    if let dl = e.deadline {
                        Text("Entro \(dl.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if e.isUrgent {
                        Label("Urgente", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.red)
                    }
                }
            }
            Spacer()
            // Bottone modifica — apre l'esame in edit con sheet(item:)
            Button { editItem = ExamSheetItem(examId: examId) } label: {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(tint).font(.title3)
            }
            .buttonStyle(.plain)
            Button(action: onRemove) {
                Image(systemName: "trash.fill").foregroundStyle(.red).font(.subheadline)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04)))
        .sheet(item: $editItem) { item in
            PediatricExamEditView(
                familyId:  familyId,
                childId:   childId,
                childName: childName,
                examId:    item.examId
            )
        }
    }
}

// ExamSheetItem: wrapper Identifiable per sheet(item:)
private struct ExamSheetItem: Identifiable {
    let examId: String?
    var id: String { examId ?? "__new__" }
}

// MARK: - AddAsNeededDrugSheet

struct AddAsNeededDrugSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tint: Color
    let onAdd: (KBAsNeededDrug) -> Void
    
    @State private var drugName     = ""
    @State private var dosageValue  = 0.0
    @State private var dosageUnit   = "ml"
    @State private var instructions = ""
    
    private let units = ["ml", "mg", "gocce", "cp", "bustina"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Farmaco") { TextField("Nome farmaco", text: $drugName) }
                Section("Dosaggio") {
                    HStack {
                        TextField("Quantità", value: $dosageValue, format: .number).keyboardType(.decimalPad)
                        Picker("Unità", selection: $dosageUnit) {
                            ForEach(units, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("Istruzioni") {
                    TextField("Es: In caso di febbre > 38°", text: $instructions, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle("Farmaco Al Bisogno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") {
                        onAdd(KBAsNeededDrug(
                            drugName: drugName, dosageValue: dosageValue, dosageUnit: dosageUnit,
                            instructions: instructions.isEmpty ? nil : instructions
                        ))
                        dismiss()
                    }
                    .disabled(drugName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - EditAsNeededDrugSheet

struct EditAsNeededDrugSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tint:    Color
    let drug:    KBAsNeededDrug
    let onSave:  (KBAsNeededDrug) -> Void
    
    @State private var drugName     = ""
    @State private var dosageValue  = 0.0
    @State private var dosageUnit   = "ml"
    @State private var instructions = ""
    
    private let units = ["ml", "mg", "gocce", "cp", "bustina"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Farmaco") { TextField("Nome farmaco", text: $drugName) }
                Section("Dosaggio") {
                    HStack {
                        TextField("Quantità", value: $dosageValue, format: .number).keyboardType(.decimalPad)
                        Picker("Unità", selection: $dosageUnit) {
                            ForEach(units, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("Istruzioni") {
                    TextField("Es: In caso di febbre > 38°", text: $instructions, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle("Modifica Farmaco")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") {
                        var updated = drug
                        updated.drugName     = drugName
                        updated.dosageValue  = dosageValue
                        updated.dosageUnit   = dosageUnit
                        updated.instructions = instructions.isEmpty ? nil : instructions
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(drugName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                drugName     = drug.drugName
                dosageValue  = drug.dosageValue
                dosageUnit   = drug.dosageUnit
                instructions = drug.instructions ?? ""
            }
        }
    }
}

// MARK: - ExistingVisitAttachmentsInEdit

private struct ExistingVisitAttachmentsInEdit: View {
    let visitId: String; let familyId: String; let tint: Color
    @Environment(\.modelContext) private var modelContext
    @Query private var allDocs: [KBDocument]
    @State private var previewURL:  URL?  = nil
    @State private var showKeyAlert: Bool = false
    
    private var docs: [KBDocument] {
        let tag = VisitAttachmentTag.make(visitId)
        return allDocs.filter { $0.notes == tag }
    }
    init(visitId: String, familyId: String, tint: Color) {
        self.visitId = visitId; self.familyId = familyId; self.tint = tint
        let fid = familyId
        _allDocs = Query(
            filter: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
    }
    var body: some View {
        if !docs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Allegati salvati (\(docs.count))", systemImage: "paperclip")
                    .font(.subheadline.bold()).foregroundStyle(tint)
                ForEach(docs) { doc in
                    docRow(doc)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.05)))
            .sheet(isPresented: Binding(
                get: { previewURL != nil },
                set: { if !$0 { previewURL = nil } }
            )) {
                if let url = previewURL { QuickLookPreview(urls: [url], initialIndex: 0) }
            }
            .alert("Chiave mancante", isPresented: $showKeyAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Chiave di crittografia non disponibile.")
            }
        }
    }
    
    private func docRow(_ doc: KBDocument) -> some View {
        HStack(spacing: 10) {
            docIcon(doc)
            docInfo(doc)
            Spacer()
            docActions(doc)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
    }
    
    private func docIcon(_ doc: KBDocument) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1)).frame(width: 36, height: 36)
            Image(systemName: mimeIcon(doc.mimeType)).foregroundStyle(tint).font(.subheadline)
        }
    }
    
    private func docInfo(_ doc: KBDocument) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(doc.title).font(.subheadline).lineLimit(1)
            extractionStatusLabel(doc)
        }
    }
    
    @ViewBuilder
    private func docActions(_ doc: KBDocument) -> some View {
        if doc.extractionStatus == .failed {
            Button {
                let uid = Auth.auth().currentUser?.uid ?? "local"
                DocumentTextExtractionCoordinator.shared.enqueueExtraction(
                    for: doc, updatedBy: uid, modelContext: modelContext
                )
            } label: {
                Label("Riprova", systemImage: "arrow.clockwise")
                    .font(.caption.bold()).foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
        Button {
            VisitAttachmentService.shared.open(
                doc: doc, modelContext: modelContext,
                onURL: { previewURL = $0 },
                onError: { _ in },
                onKeyMissing: { showKeyAlert = true }
            )
        } label: {
            Image(systemName: "eye.fill").foregroundStyle(tint).font(.subheadline)
        }
        .buttonStyle(.plain)
        Button {
            VisitAttachmentService.shared.delete(doc, modelContext: modelContext)
        } label: {
            Image(systemName: "trash").foregroundStyle(.red).font(.subheadline)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func extractionStatusLabel(_ doc: KBDocument) -> some View {
        let status = doc.extractionStatus
        if status == .completed {
            if doc.hasExtractedText {
                Label("Leggibile dall'AI ✓", systemImage: "checkmark.circle.fill")
                    .font(.caption2).foregroundStyle(.green)
            } else {
                Label("Nessun testo rilevato", systemImage: "minus.circle")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } else if status == .processing {
            extractionProgressLabel("Lettura in corso…")
        } else if status == .pending {
            extractionProgressLabel("In attesa di lettura…")
        } else if status == .failed {
            Label("Lettura fallita — tocca Riprova", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2).foregroundStyle(.orange)
        } else {
            Label("Stato sconosciuto", systemImage: "questionmark.circle")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    
    private func extractionProgressLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
    
    private func mimeIcon(_ mime: String) -> String {
        if mime.contains("pdf") { return "doc.fill" }
        if mime.contains("image") { return "photo.fill" }
        return "paperclip"
    }
}

// MARK: - SummaryLinkedTreatmentRow

private struct SummaryLinkedTreatmentRow: View {
    let treatmentId: String
    @Query private var treatments: [KBTreatment]
    private var t: KBTreatment? { treatments.first }
    init(treatmentId: String) {
        self.treatmentId = treatmentId
        let tid = treatmentId
        _treatments = Query(filter: #Predicate<KBTreatment> { $0.id == tid })
    }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "pills.fill").font(.caption).foregroundStyle(.blue.opacity(0.6))
            Text(t?.drugName ?? "Farmaco").font(.subheadline)
            if let t { Text("· \(t.dosageValue, specifier: "%.0f") \(t.dosageUnit)").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

// MARK: - SummaryLinkedExamRow

private struct SummaryLinkedExamRow: View {
    let examId: String
    @Query private var exams: [KBMedicalExam]
    private var e: KBMedicalExam? { exams.first }
    init(examId: String) {
        self.examId = examId
        let eid = examId
        _exams = Query(filter: #Predicate<KBMedicalExam> { $0.id == eid })
    }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "testtube.2").font(.caption).foregroundStyle(.teal.opacity(0.7))
            Text(e?.name ?? "Esame").font(.subheadline)
            if e?.isUrgent == true {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.red)
            }
        }
    }
}
