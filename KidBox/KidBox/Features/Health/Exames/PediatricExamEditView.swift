//
//  PediatricExamEditView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth
import QuickLook

struct PediatricExamEditView: View {
    
    @Environment(\.dismiss)       private var dismiss
    @Environment(\.modelContext)  private var modelContext
    @Environment(\.colorScheme)   private var colorScheme
    
    let familyId:           String
    let childId:            String
    let childName:          String
    let examId:             String?
    let prescribingVisitId: String?
    let onSaved:            ((String) -> Void)?
    
    private var isEditing: Bool { examId != nil }
    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)
    
    // MARK: - Form state
    
    @State private var name        = ""
    @State private var isUrgent    = false
    @State private var hasDeadline = false
    @State private var deadline    = Date()
    @State private var preparation = ""
    @State private var notes       = ""
    @State private var location    = ""   // ← NUOVO
    @State private var status      = KBExamStatus.pending
    @State private var resultText  = ""
    @State private var hasResult   = false
    @State private var resultDate  = Date()
    
    // Allegati
    @State private var pendingURLs         = [URL]()
    @State private var showSourcePicker    = false
    @State private var showGallery         = false
    @State private var showCamera          = false
    @State private var showImporter        = false
    @State private var previewURL: URL?    = nil
    @State private var showKeyAlert        = false
    
    @State private var isSaving = false
    
    // Allegati esistenti (solo edit)
    @Query private var allDocs: [KBDocument]
    private var existingDocs: [KBDocument] {
        guard let eid = examId else { return [] }
        return allDocs.filter { ExamAttachmentTag.matches($0, examId: eid) }
    }
    
    private let common = ["Emocromo", "Esame urine", "Ecografia", "Tampone",
                          "Radiografia", "Holter", "Spirometria", "TC", "RMN"]
    
    init(
        familyId:           String,
        childId:            String,
        childName:          String,
        examId:             String?        = nil,
        prescribingVisitId: String?        = nil,
        onSaved:            ((String) -> Void)? = nil
    ) {
        self.familyId           = familyId
        self.childId            = childId
        self.childName          = childName
        self.examId             = examId
        self.prescribingVisitId = prescribingVisitId
        self.onSaved            = onSaved
        let fid = familyId
        _allDocs = Query(
            filter: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Form {
                // ── Nome esame ──
                Section {
                    Label("Nome esame", systemImage: "testtube.2").font(.headline)
                    TextField("Es. Emocromo, Ecografia...", text: $name)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
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
                
                // ── Priorità & Scadenza ──
                Section("Dettagli") {
                    Toggle(isOn: $isUrgent) {
                        Label("Urgente", systemImage: "exclamationmark.triangle.fill")
                    }
                    Toggle(isOn: $hasDeadline) {
                        Label("Da eseguire entro", systemImage: "calendar")
                    }
                    if hasDeadline {
                        DatePicker("Scadenza", selection: $deadline, displayedComponents: .date)
                    }
                }
                
                // ── Luogo ── (NUOVO)
                Section("Luogo") {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(tint)
                        TextField("Es: Ospedale Civile, Via Roma 1", text: $location, axis: .vertical)
                            .lineLimit(1...3)
                    }
                }
                
                // ── Preparazione & Note ──
                Section("Preparazione & Note") {
                    TextField("Es: A digiuno da 12 ore", text: $preparation, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Note aggiuntive", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                // ── Stato / Risultato ──
                Section("Stato") {
                    Picker("Stato", selection: $status) {
                        ForEach(KBExamStatus.allCases, id: \.self) { s in
                            Label(s.rawValue, systemImage: s.icon).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Toggle(isOn: $hasResult) {
                        Label("Inserisci risultato", systemImage: "doc.text.magnifyingglass")
                    }
                    if hasResult {
                        TextField("Risultato dell'esame", text: $resultText, axis: .vertical)
                            .lineLimit(2...6)
                        DatePicker("Data risultato", selection: $resultDate, displayedComponents: .date)
                    }
                }
                
                // ── Allegati esistenti (edit) ──
                if !existingDocs.isEmpty {
                    Section("Allegati salvati") {
                        ForEach(existingDocs) { doc in
                            existingDocRow(doc)
                        }
                    }
                }
                
                // ── Nuovi allegati ──
                Section("Allega referti o immagini") {
                    if !pendingURLs.isEmpty {
                        ForEach(pendingURLs, id: \.absoluteString) { url in
                            HStack(spacing: 8) {
                                if let img = UIImage(contentsOfFile: url.path) {
                                    Image(uiImage: img)
                                        .resizable().scaledToFill()
                                        .frame(width: 36, height: 36)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    Image(systemName: fileIcon(url.pathExtension.lowercased()))
                                        .foregroundStyle(tint).frame(width: 36, height: 36)
                                }
                                Text(url.lastPathComponent).font(.caption).lineLimit(1)
                                Spacer()
                                Button { pendingURLs.removeAll { $0 == url } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    if pendingURLs.count < 5 {
                        Button {
                            showSourcePicker = true
                        } label: {
                            Label("Aggiungi allegato", systemImage: "plus.circle.fill")
                                .foregroundStyle(tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(isEditing ? "Modifica Esame" : "Nuovo Esame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Salvataggio..." : "Salva") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .bold()
                }
            }
            // FIX: carica i dati appena la view appare, sia in creazione che in modifica
            .onAppear { loadIfEditing() }
        }
        // Attachment sheets
        .sheet(isPresented: $showSourcePicker) {
            AttachmentSourcePickerSheet(
                tint: tint,
                onCamera: {
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showCamera = true }
                },
                onGallery: {
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showGallery = true }
                },
                onDocument: {
                    showSourcePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showImporter = true }
                }
            )
            .presentationDetents([.height(250)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGallery) {
            ImagePickerView(sourceType: .photoLibrary) { image in
                if let url = saveImageToTemp(image) { pendingURLs.append(url) }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePickerView(sourceType: .camera) { image in
                if let url = saveImageToTemp(image) { pendingURLs.append(url) }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if let urls = try? result.get() {
                let available = 5 - pendingURLs.count
                pendingURLs.append(contentsOf: urls.prefix(available))
            }
        }
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
    
    // MARK: - Existing doc row
    
    private func existingDocRow(_ doc: KBDocument) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1)).frame(width: 36, height: 36)
                    Image(systemName: mimeIcon(doc.mimeType)).foregroundStyle(tint).font(.subheadline)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.title).font(.subheadline).lineLimit(1)
                    extractionStatusLabel(doc)
                }
                Spacer()
                // Riprova — solo se estrazione fallita
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
                    ExamAttachmentService.shared.open(
                        doc: doc, modelContext: modelContext,
                        onURL: { previewURL = $0 },
                        onError: { _ in },
                        onKeyMissing: { showKeyAlert = true }
                    )
                } label: { Image(systemName: "eye.fill").foregroundStyle(tint) }
                    .buttonStyle(.plain)
                Button {
                    ExamAttachmentService.shared.delete(doc, modelContext: modelContext)
                } label: { Image(systemName: "trash").foregroundStyle(.red) }
                    .buttonStyle(.plain)
            }
        }
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
    
    // MARK: - Load / Save
    
    private func loadIfEditing() {
        guard let eid = examId else { return }
        let desc = FetchDescriptor<KBMedicalExam>(predicate: #Predicate { $0.id == eid })
        guard let e = try? modelContext.fetch(desc).first else { return }
        name        = e.name
        isUrgent    = e.isUrgent
        hasDeadline = e.deadline != nil
        deadline    = e.deadline ?? Date()
        preparation = e.preparation ?? ""
        notes       = e.notes ?? ""
        location    = e.location ?? ""   // ← NUOVO
        status      = e.status
        hasResult   = e.resultText != nil
        resultText  = e.resultText ?? ""
        resultDate  = e.resultDate ?? Date()
    }
    
    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        let exam: KBMedicalExam
        
        if let eid = examId,
           let existing = try? modelContext.fetch(
            FetchDescriptor<KBMedicalExam>(predicate: #Predicate { $0.id == eid })
           ).first {
            // ── Edit ──
            existing.name        = name
            existing.isUrgent    = isUrgent
            existing.deadline    = hasDeadline ? deadline : nil
            existing.preparation = preparation.isEmpty ? nil : preparation
            existing.notes       = notes.isEmpty ? nil : notes
            existing.location    = location.isEmpty ? nil : location   // ← NUOVO
            existing.status      = status
            existing.resultText  = hasResult && !resultText.isEmpty ? resultText : nil
            existing.resultDate  = hasResult ? resultDate : nil
            existing.updatedAt   = now
            existing.updatedBy   = uid
            existing.syncState   = .pendingUpsert
            exam = existing
        } else {
            // ── New ──
            let newExam = KBMedicalExam(
                familyId:           familyId,
                childId:            childId,
                name:               name,
                isUrgent:           isUrgent,
                deadline:           hasDeadline ? deadline : nil,
                preparation:        preparation.isEmpty ? nil : preparation,
                notes:              notes.isEmpty ? nil : notes,
                location:           location.isEmpty ? nil : location,  // ← NUOVO
                status:             status,
                resultText:         hasResult && !resultText.isEmpty ? resultText : nil,
                resultDate:         hasResult ? resultDate : nil,
                prescribingVisitId: prescribingVisitId,
                createdAt:          now,
                updatedAt:          now,
                updatedBy:          uid,
                createdBy:          uid
            )
            modelContext.insert(newExam)
            exam = newExam
        }
        
        try? modelContext.save()
        SyncCenter.shared.enqueueMedicalExamUpsert(examId: exam.id, familyId: familyId, modelContext: modelContext)
        
        // Upload allegati pendenti
        if !pendingURLs.isEmpty {
            let eid = exam.id
            let fid = familyId
            let cid = childId
            Task {
                for url in pendingURLs {
                    await _ = ExamAttachmentService.shared.upload(
                        url: url, examId: eid, familyId: fid,
                        childId: cid, modelContext: modelContext
                    )
                }
            }
        }
        
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        onSaved?(exam.id)
        isSaving = false
        dismiss()
    }
    
    // MARK: - Helpers
    
    private func saveImageToTemp(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        try? data.write(to: url)
        return url
    }
    
    private func fileIcon(_ ext: String) -> String {
        switch ext {
        case "pdf": return "doc.fill"
        case "jpg", "jpeg", "png", "heic": return "photo.fill"
        default: return "paperclip"
        }
    }
    
    private func mimeIcon(_ mime: String) -> String {
        if mime.contains("pdf")   { return "doc.fill" }
        if mime.contains("image") { return "photo.fill" }
        return "paperclip"
    }
}
