//
//  PediatricVisitEditView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth
import UniformTypeIdentifiers

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
    
    // Medici recenti (ultimi 5 distinti per nome)
    @Query private var recentVisitsQ: [KBMedicalVisit]
    
    // ── Step 2: Esito ──
    @State private var diagnosis        = ""
    @State private var recommendations  = ""
    
    // ── Step 3: Prescrizioni ──
    @State private var linkedTreatmentIds: [String]        = []   // id KBTreatment creati dal wizard
    @State private var asNeededDrugs:  [KBAsNeededDrug]   = []
    @State private var therapyTypes:   [KBTherapyType]    = []
    @State private var prescribedExams:[KBPrescribedExam] = []
    @State private var prescriptionsTab      = 0
    @State private var showAddExamSheet      = false
    @State private var showAddDrugSheet      = false
    @State private var showAddTreatmentSheet = false
    
    // ── Step 4: Foto & Appunti ──
    @State private var notes = ""
    @State private var pendingAttachmentURLs:  [URL]  = []
    @State private var showAttachmentPicker   = false
    @State private var showAttachmentGallery  = false
    @State private var showAttachmentCamera   = false
    @State private var showAttachmentImporter = false
    
    // ── Step 5: Riepilogo ──
    @State private var hasNextVisit  = false
    @State private var nextVisitDate = Date()
    
    @State private var isSaving = false
    
    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)
    
    init(familyId: String, childId: String, childName: String, visitId: String? = nil) {
        self.familyId  = familyId
        self.childId   = childId
        self.childName = childName
        self.visitId   = visitId
        let fid = familyId
        _recentVisitsQ = Query(
            filter: #Predicate<KBMedicalVisit> {
                $0.familyId == fid
            },
            sort: [SortDescriptor(\KBMedicalVisit.date, order: .reverse)]
        )
    }
    
    // Ultimi medici distinti
    private var recentDoctors: [(name: String, spec: String)] {
        var seen = Set<String>()
        var result: [(String, String)] = []
        for v in recentVisitsQ {
            // filtro childId e isDeleted in memoria — evita crash #Predicate con &&
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
                // Progress bar
                stepProgressBar
                
                // Content
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
                
                // Bottom navigation
                bottomNav
            }
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle(isEditing ? "Modifica Visita" : "Visita Medica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                }
            }
            .onAppear { loadIfEditing() }
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
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    Label("Indietro", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.12)))
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                        .font(.headline)
                }
                .buttonStyle(.plain)
            }
            
            if currentStep < totalSteps - 1 {
                Button {
                    withAnimation { currentStep += 1 }
                } label: {
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
                Button {
                    save()
                } label: {
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
    
    // MARK: ── Step 1: Titolo & Medico & Data ──
    
    private var step1DoctorDate: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // ── Titolo visita (reason) — campo principale ──
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tipo di Visita")
                        .font(.title3.bold()).padding(.horizontal)
                    Text("Es. Visita Urologica, Controllo Pediatrico...")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    TextField("Visita...", text: $reason)
                        .font(.headline)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
                        .padding(.horizontal)
                }
                
                Divider().padding(.horizontal)
                
                // ── Medico (secondario) ──
                VStack(alignment: .leading, spacing: 8) {
                    Label("Medico", systemImage: "person.fill")
                        .font(.headline).padding(.horizontal)
                    
                    // Se medico già selezionato → card con nome + tasto cambia
                    if !selectedDoctorName.isEmpty && !showNewDoctorForm {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(tint.opacity(0.12)).frame(width: 44, height: 44)
                                Image(systemName: "person.fill").foregroundStyle(tint)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedDoctorName).font(.subheadline.bold())
                                if let s = selectedSpec {
                                    Text(s.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                selectedDoctorName = ""
                                selectedSpec = nil
                                doctorSearchText = ""
                            } label: {
                                Text("Cambia")
                                    .font(.caption.bold())
                                    .foregroundStyle(tint)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(tint.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.06)))
                        .padding(.horizontal)
                        
                    } else {
                        // Search bar + lista medici recenti
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Cerca medico...", text: $doctorSearchText)
                                .onChange(of: doctorSearchText) { _, v in
                                    if !v.isEmpty { showNewDoctorForm = false }
                                }
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
                                Text("Medici Recenti")
                                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                                ForEach(filtered, id: \.name) { doc in
                                    Button {
                                        selectedDoctorName = doc.name
                                        selectedSpec = KBDoctorSpecialization(rawValue: doc.spec)
                                        showNewDoctorForm = false
                                        doctorSearchText = ""
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "person.circle.fill")
                                                .font(.title3).foregroundStyle(tint)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(doc.name).font(.subheadline.bold())
                                                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                                                if !doc.spec.isEmpty {
                                                    Text(doc.spec).font(.caption).foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                        }
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        Button {
                            showNewDoctorForm = true
                            selectedDoctorName = doctorSearchText
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Nuovo Medico").font(.subheadline.bold())
                                        .foregroundStyle(showNewDoctorForm ? tint : KBTheme.primaryText(colorScheme))
                                    Text("es. Pediatra, Dermatologo").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if showNewDoctorForm {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(tint)
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(showNewDoctorForm ? tint.opacity(0.08) : Color.secondary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        
                        if showNewDoctorForm {
                            VStack(alignment: .leading, spacing: 12) {
                                Group {
                                    Text("Nome Medico").font(.caption.bold()).foregroundStyle(.secondary)
                                    TextField("es. Dott. Rossi", text: $selectedDoctorName)
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                                }
                                Group {
                                    Text("Specializzazione").font(.caption.bold()).foregroundStyle(.secondary)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack {
                                            ForEach(KBDoctorSpecialization.allCases, id: \.self) { s in
                                                Button { selectedSpec = s } label: {
                                                    Text(s.rawValue)
                                                        .font(.caption)
                                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                                        .background(Capsule().fill(selectedSpec == s ? tint : Color.secondary.opacity(0.12)))
                                                        .foregroundStyle(selectedSpec == s ? .white : KBTheme.primaryText(colorScheme))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                                // Conferma nuovo medico
                                Button {
                                    showNewDoctorForm = false
                                    doctorSearchText = ""
                                } label: {
                                    Text("Conferma")
                                        .font(.subheadline.bold())
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
                
                // ── Data visita ──
                VStack(alignment: .leading, spacing: 8) {
                    Label("Data Visita", systemImage: "calendar")
                        .font(.headline).padding(.horizontal)
                    DatePicker("", selection: $visitDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
    
    // MARK: ── Step 2: Esito ──
    
    private var step2Outcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Esito della Visita")
                    .font(.title3.bold()).padding(.horizontal)
                
                sectionCard(icon: "stethoscope", title: "Diagnosi") {
                    TextField("Diagnosi o conclusioni del medico", text: $diagnosis, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                sectionCard(icon: "lightbulb.fill", title: "Raccomandazioni") {
                    TextField("Consigli generali del medico", text: $recommendations, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .padding(.vertical)
        }
    }
    
    // MARK: ── Step 3: Prescrizioni ──
    
    private var step3Prescriptions: some View {
        VStack(spacing: 0) {
            
            // Titolo + badge totale
            let totalRx = prescribedExams.count + asNeededDrugs.count + therapyTypes.count + linkedTreatmentIds.count
            HStack {
                Text("Prescrizioni")
                    .font(.title3.bold())
                Spacer()
                if totalRx > 0 {
                    Text("\(totalRx)")
                        .font(.caption.bold()).foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(tint))
                }
            }
            .padding(.horizontal).padding(.top, 12)
            
            // Tab bar con badge per tab
            let tabs  = ["Farmaci", "Al bisogno", "Tipo di Terapia", "Esami Prescritti"]
            let icons = ["pills.fill", "cross.vial.fill", "figure.walk", "testtube.2"]
            let counts = [linkedTreatmentIds.count, asNeededDrugs.count, therapyTypes.count, prescribedExams.count]
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs.indices, id: \.self) { i in
                        Button {
                            withAnimation { prescriptionsTab = i }
                        } label: {
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
                                    Text("\(counts[i])")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 16, height: 16)
                                        .background(Circle().fill(prescriptionsTab == i ? Color.white.opacity(0.9) : tint))
                                        .foregroundStyle(prescriptionsTab == i ? tint : .white)
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
            Text("Farmaci Programmati")
                .font(.headline).padding(.horizontal)
            Text("Farmaci con orari programmati da assumere regolarmente")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            
            // Card per ogni cura già aggiunta
            if !linkedTreatmentIds.isEmpty {
                VStack(spacing: 8) {
                    ForEach(linkedTreatmentIds, id: \.self) { tid in
                        LinkedTreatmentCard(
                            treatmentId: tid,
                            tint: tint,
                            colorScheme: colorScheme,
                            onRemove: {
                                linkedTreatmentIds.removeAll { $0 == tid }
                                // Soft-delete dal modelContext
                                let desc = FetchDescriptor<KBTreatment>(
                                    predicate: #Predicate { $0.id == tid }
                                )
                                if let t = try? modelContext.fetch(desc).first {
                                    t.isDeleted = true
                                    try? modelContext.save()
                                }
                            }
                        )
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
                Text("Salta le prescrizioni")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical)
        .sheet(isPresented: $showAddTreatmentSheet) {
            PediatricTreatmentEditView(
                familyId: familyId,
                childId: childId,
                childName: childName,
                treatmentId: nil,
                onSaved: { savedId in
                    linkedTreatmentIds.append(savedId)
                }
            )
        }
    }
    
    private var prescriptionsTabAsNeeded: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Al bisogno").font(.headline).padding(.horizontal)
            if asNeededDrugs.isEmpty {
                emptyPrescriptionState(icon: "cross.vial.fill", text: "Nessun farmaco al bisogno")
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
            AddAsNeededDrugSheet(tint: tint) { drug in
                asNeededDrugs.append(drug)
            }
        }
    }
    
    private var prescriptionsTabTherapy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tipo di Terapia").font(.headline).padding(.horizontal)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(KBTherapyType.allCases, id: \.self) { t in
                    Button {
                        if therapyTypes.contains(t) {
                            therapyTypes.removeAll { $0 == t }
                        } else {
                            therapyTypes.append(t)
                        }
                    } label: {
                        Text(t.rawValue)
                            .font(.subheadline)
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
    
    private var prescriptionsTabExams: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Esami Prescritti").font(.headline)
                Spacer()
                if !prescribedExams.isEmpty {
                    Text("\(prescribedExams.count)")
                        .font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(tint))
                }
            }
            .padding(.horizontal)
            
            Text("Esami del sangue, ecografie e altri controlli prescritti")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            
            ForEach(prescribedExams) { exam in
                HStack {
                    Text(exam.name).font(.subheadline.bold())
                    if exam.isUrgent {
                        Circle().fill(.red).frame(width: 8, height: 8)
                    }
                    Spacer()
                    Button {
                        prescribedExams.removeAll { $0.id == exam.id }
                    } label: {
                        Image(systemName: "trash.fill").foregroundStyle(.red)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
                .padding(.horizontal)
            }
            
            Button { showAddExamSheet = true } label: {
                Label(prescribedExams.isEmpty ? "Aggiungi un esame" : "Aggiungi un altro esame", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity).padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.12)))
                    .foregroundStyle(tint).font(.subheadline.bold())
            }
            .buttonStyle(.plain).padding(.horizontal)
        }
        .padding(.vertical)
        .sheet(isPresented: $showAddExamSheet) {
            AddExamSheet(tint: tint) { exam in
                prescribedExams.append(exam)
            }
        }
    }
    
    // MARK: ── Step 4: Foto & Appunti ──
    
    private var step4PhotoNotes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // In edit mode mostra gli allegati già salvati + picker per nuovi
                if isEditing, let vid = visitId {
                    ExistingVisitAttachmentsInEdit(visitId: vid, familyId: familyId, tint: tint)
                        .padding(.horizontal)
                }
                
                // Nuovi allegati da aggiungere (sempre visibile)
                VisitAttachmentPicker(
                    pendingURLs: $pendingAttachmentURLs,
                    onAddTapped: { showAttachmentPicker = true }
                )
                .padding(.horizontal)
                
                sectionCard(icon: "square.and.pencil", title: "Appunti della Visita") {
                    TextField("Aggiungi note sulla visita...", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
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
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        try? data.write(to: url)
        return url
    }
    
    // MARK: ── Step 5: Riepilogo ──
    
    private var step5Summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Riepilogo Visita")
                    .font(.title3.bold()).padding(.horizontal)
                
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
                    Text(italianDateTime(visitDate))
                        .font(.subheadline.bold())
                }
                
                if !diagnosis.isEmpty {
                    summaryRow(icon: "stethoscope", title: "Diagnosi") {
                        Text(diagnosis).font(.subheadline)
                    }
                }
                
                if !recommendations.isEmpty {
                    summaryRow(icon: "lightbulb.fill", title: "Raccomandazioni") {
                        Text(recommendations).font(.subheadline)
                    }
                }
                
                if !linkedTreatmentIds.isEmpty {
                    summaryRow(icon: "pills.fill", title: "Farmaci Programmati (\(linkedTreatmentIds.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(linkedTreatmentIds, id: \.self) { tid in
                                SummaryLinkedTreatmentRow(treatmentId: tid)
                            }
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
                                    Text("· \(d.dosageValue, specifier: "%.0f") \(d.dosageUnit)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                
                if !therapyTypes.isEmpty {
                    summaryRow(icon: "figure.walk", title: "Terapie (\(therapyTypes.count))") {
                        Text(therapyTypes.map { $0.rawValue }.joined(separator: ", "))
                            .font(.subheadline)
                    }
                }
                
                if !prescribedExams.isEmpty {
                    summaryRow(icon: "testtube.2", title: "Esami Prescritti (\(prescribedExams.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(prescribedExams) { e in
                                HStack(spacing: 6) {
                                    Text(e.name).font(.subheadline)
                                    if e.isUrgent { Circle().fill(.red).frame(width: 8, height: 8) }
                                }
                            }
                        }
                    }
                }
                
                // Allegati pendenti
                if !pendingAttachmentURLs.isEmpty {
                    summaryRow(icon: "paperclip", title: "Allegati (\(pendingAttachmentURLs.count))") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(pendingAttachmentURLs, id: \.absoluteString) { url in
                                    if let img = UIImage(contentsOfFile: url.path) {
                                        Image(uiImage: img)
                                            .resizable().scaledToFill()
                                            .frame(width: 56, height: 56)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(tint.opacity(0.1))
                                                .frame(width: 56, height: 56)
                                            Image(systemName: "doc.fill")
                                                .foregroundStyle(tint)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Prossimo appuntamento
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Prossimo Appuntamento", systemImage: "calendar.badge.plus")
                            .font(.subheadline.bold())
                        Spacer()
                        Toggle("", isOn: $hasNextVisit).labelsHidden()
                    }
                    if hasNextVisit {
                        DatePicker("", selection: $nextVisitDate, displayedComponents: [.date])
                            .datePickerStyle(.compact).labelsHidden()
                        
                        Text(italianDateOnly(nextVisitDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        prescribedExams    = v.prescribedExams
        notes              = v.notes ?? ""
        hasNextVisit       = v.nextVisitDate != nil
        nextVisitDate      = v.nextVisitDate ?? Date()
    }
    
    private func save() {
        isSaving = true
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        // ── Modifica visita esistente ──
        if let vid = visitId {
            let desc = FetchDescriptor<KBMedicalVisit>(predicate: #Predicate { $0.id == vid })
            guard let v = try? modelContext.fetch(desc).first else { isSaving = false; return }
            
            v.reason            = reason
            v.doctorName        = selectedDoctorName.isEmpty ? nil : selectedDoctorName
            v.doctorSpecialization = selectedSpec
            v.date              = visitDate
            v.diagnosis         = diagnosis.isEmpty ? nil : diagnosis
            v.recommendations   = recommendations.isEmpty ? nil : recommendations
            v.linkedTreatmentIds = linkedTreatmentIds
            v.asNeededDrugs     = asNeededDrugs
            v.therapyTypes      = therapyTypes
            v.prescribedExams   = prescribedExams
            v.notes             = notes.isEmpty ? nil : notes
            v.nextVisitDate     = hasNextVisit ? nextVisitDate : nil
            v.updatedAt         = now
            v.updatedBy         = uid
            v.syncState         = .pendingUpsert
            
            try? modelContext.save()
            SyncCenter.shared.enqueueVisitUpsert(visitId: v.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            
            if !pendingAttachmentURLs.isEmpty {
                KBEventBus.shared.emit(KBAppEvent.visitAttachmentPending(
                    urls: pendingAttachmentURLs, visitId: v.id,
                    familyId: familyId, childId: childId
                ))
            }
            isSaving = false
            dismiss()
            return
        }
        
        // ── Nuova visita ──
        let visit = KBMedicalVisit(
            familyId:             familyId,
            childId:              childId,
            date:                 visitDate,
            doctorName:           selectedDoctorName.isEmpty ? nil : selectedDoctorName,
            doctorSpecialization: selectedSpec,
            reason:               reason,
            diagnosis:            diagnosis.isEmpty ? nil : diagnosis,
            recommendations:      recommendations.isEmpty ? nil : recommendations,
            linkedTreatmentIds:   linkedTreatmentIds,
            asNeededDrugs:        asNeededDrugs,
            therapyTypes:         therapyTypes,
            prescribedExams:      prescribedExams,
            notes:                notes.isEmpty ? nil : notes,
            nextVisitDate:        hasNextVisit ? nextVisitDate : nil,
            createdAt:            now,
            updatedAt:            now,
            updatedBy:            uid,
            createdBy:            uid
        )
        
        modelContext.insert(visit)
        try? modelContext.save()
        
        SyncCenter.shared.enqueueVisitUpsert(visitId: visit.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        if !pendingAttachmentURLs.isEmpty {
            KBEventBus.shared.emit(KBAppEvent.visitAttachmentPending(
                urls: pendingAttachmentURLs, visitId: visit.id,
                familyId: familyId, childId: childId
            ))
        }
        
        isSaving = false
        dismiss()
    }
    
    // MARK: - Helpers
    
    @ViewBuilder
    private func sectionCard<Content: View>(
        icon: String,
        title: String,
        badge: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
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
    private func summaryRow<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func italianDateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - LinkedTreatmentCard

/// Card compatta che mostra un KBTreatment aggiunto dal wizard visita.
private struct LinkedTreatmentCard: View {
    let treatmentId: String
    let tint: Color
    let colorScheme: ColorScheme
    let onRemove: () -> Void
    
    @Query private var treatments: [KBTreatment]
    private var treatment: KBTreatment? { treatments.first }
    
    init(treatmentId: String, tint: Color, colorScheme: ColorScheme, onRemove: @escaping () -> Void) {
        self.treatmentId = treatmentId
        self.tint        = tint
        self.colorScheme = colorScheme
        self.onRemove    = onRemove
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
                Text(treatment?.drugName ?? "Farmaco")
                    .font(.subheadline.bold())
                if let t = treatment {
                    Text("\(t.dosageValue, specifier: "%.0f") \(t.dosageUnit) · \(t.dailyFrequency)x/die · \(t.isLongTerm ? "lungo termine" : "\(t.durationDays)gg")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "trash.fill")
                    .foregroundStyle(.red).font(.subheadline)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
        )
    }
}

struct AddExamSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tint: Color
    let onAdd: (KBPrescribedExam) -> Void
    
    @State private var name        = ""
    @State private var isUrgent    = false
    @State private var hasDeadline = false
    @State private var deadline    = Date()
    @State private var preparation = ""
    
    private let common = ["Emocromo", "Esame urine", "Ecografia", "Tampone", "Radiografia"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Nome esame", systemImage: "testtube.2").font(.headline)
                    TextField("Nome esame", text: $name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(common, id: \.self) { c in
                                Button { name = c } label: {
                                    Text(c).font(.caption)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Capsule().fill(name == c ? tint : Color.secondary.opacity(0.12)))
                                        .foregroundStyle(name == c ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: { Text("Esami comuni") }
                
                Section {
                    Toggle(isOn: $hasDeadline) { Label("Da eseguire entro", systemImage: "calendar") }
                    if hasDeadline {
                        DatePicker("", selection: $deadline, displayedComponents: .date).labelsHidden()
                    }
                    Toggle(isOn: $isUrgent) { Label("Urgente", systemImage: "exclamationmark.triangle.fill") }
                }
                
                Section {
                    Label("Preparazione", systemImage: "list.clipboard")
                    TextField("Es: A digiuno da 12 ore", text: $preparation, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle("Aggiungi Esame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") {
                        let exam = KBPrescribedExam(
                            name: name,
                            isUrgent: isUrgent,
                            deadline: hasDeadline ? deadline : nil,
                            preparation: preparation.isEmpty ? nil : preparation
                        )
                        onAdd(exam)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
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
                Section("Farmaco") {
                    TextField("Nome farmaco", text: $drugName)
                }
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
                        let drug = KBAsNeededDrug(
                            drugName: drugName,
                            dosageValue: dosageValue,
                            dosageUnit: dosageUnit,
                            instructions: instructions.isEmpty ? nil : instructions
                        )
                        onAdd(drug)
                        dismiss()
                    }
                    .disabled(drugName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - ExistingVisitAttachmentsInEdit

private struct ExistingVisitAttachmentsInEdit: View {
    let visitId:  String
    let familyId: String
    let tint:     Color
    
    @Environment(\.modelContext) private var modelContext
    @Query private var allDocs: [KBDocument]
    
    private var docs: [KBDocument] {
        let tag = VisitAttachmentTag.make(visitId)
        return allDocs.filter { $0.notes == tag }
    }
    
    init(visitId: String, familyId: String, tint: Color) {
        self.visitId  = visitId
        self.familyId = familyId
        self.tint     = tint
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
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(tint.opacity(0.1)).frame(width: 36, height: 36)
                            Image(systemName: mimeIcon(doc.mimeType))
                                .foregroundStyle(tint).font(.subheadline)
                        }
                        Text(doc.title).font(.subheadline).lineLimit(1)
                        Spacer()
                        Button {
                            VisitAttachmentService.shared.delete(doc, modelContext: modelContext)
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red).font(.subheadline)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.05)))
        }
    }
    
    private func mimeIcon(_ mime: String) -> String {
        if mime.contains("pdf")   { return "doc.fill" }
        if mime.contains("image") { return "photo.fill" }
        return "paperclip"
    }
}


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
            Image(systemName: "pills.fill")
                .font(.caption).foregroundStyle(.blue.opacity(0.6))
            Text(t?.drugName ?? "Farmaco")
                .font(.subheadline)
            if let t {
                Text("· \(t.dosageValue, specifier: "%.0f") \(t.dosageUnit)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
