//
//  PediatricExamDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth
import QuickLook

struct PediatricExamDetailView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    
    let familyId: String
    let childId:  String
    let examId:   String
    
    @Query private var exams:    [KBMedicalExam]
    @Query private var children: [KBChild]
    @Query private var members:  [KBFamilyMember]
    
    // childName derivato dalle @Query — usato solo per la UI.
    // Per le notifiche si usa resolveSubjectName() che legge dal modelContext
    // in modo sincrono e non dipende dal timing del fetch SwiftUI.
    private var childName: String {
        if let name = children.first?.name, !name.isEmpty { return name }
        if let name = members.first?.displayName, !name.isEmpty { return name }
        if let email = members.first?.email, !email.isEmpty { return email }
        return "bambino"
    }
    
    /// Legge il nome del soggetto DIRETTAMENTE dal modelContext (fetch sincrono).
    /// Questo garantisce che il nome sia sempre corretto anche se le @Query
    /// non hanno ancora completato il caricamento quando l'utente tocca il campanellino.
    private func resolveSubjectName() -> String {
        // 1. Prova come KBChild
        let childDesc = FetchDescriptor<KBChild>(
            predicate: #Predicate<KBChild> { $0.id == childId }
        )
        if let child = try? modelContext.fetch(childDesc).first,
           !child.name.isEmpty {
            return child.name
        }
        // 2. Prova come KBFamilyMember (genitori o adulti)
        let fid = familyId
        let cid = childId
        let memberDesc = FetchDescriptor<KBFamilyMember>(
            predicate: #Predicate<KBFamilyMember> {
                $0.userId == cid && $0.familyId == fid && $0.isDeleted == false
            }
        )
        if let member = try? modelContext.fetch(memberDesc).first {
            if let name = member.displayName, !name.isEmpty { return name }
            if let email = member.email,       !email.isEmpty { return email }
        }
        return "bambino"
    }
    
    @State private var showEditSheet      = false
    @State private var showDeleteAlert    = false
    
    // Promemoria
    @State private var reminderScheduled      = false
    @State private var showReminderAlert      = false
    @State private var reminderAlertMsg       = ""
    @State private var showReminderTimePicker = false
    @State private var reminderTime           = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var pendingReminderExam:   KBMedicalExam? = nil
    
    private let tint = Color(red: 0.25, green: 0.65, blue: 0.75)
    
    init(familyId: String, childId: String, examId: String) {
        self.familyId = familyId
        self.childId  = childId
        self.examId   = examId
        let eid = examId
        let cid = childId
        let fid = familyId
        _exams    = Query(filter: #Predicate<KBMedicalExam>  { $0.id == eid })
        _children = Query(filter: #Predicate<KBChild>         { $0.id == cid })
        _members  = Query(filter: #Predicate<KBFamilyMember> {
            $0.userId == cid && $0.familyId == fid && $0.isDeleted == false
        })
    }
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if let exam {
                content(exam)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            if let exam, AISettings.shared.isEnabled {
                ExamsAskAIButton(subjectName: childName, scope: .single(exam))
                    .padding(.trailing, 20)
                    .padding(.bottom, 96)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let exam {
                PediatricExamEditView(
                    familyId:  familyId,
                    childId:   childId,
                    childName: childName,
                    examId:    exam.id
                )
            }
        }
        .alert("Elimina Esame", isPresented: $showDeleteAlert) {
            Button("Elimina", role: .destructive) {
                if let exam { deleteExam(exam) }
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Questa azione non può essere annullata.")
        }
        .alert("Promemoria", isPresented: $showReminderAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(reminderAlertMsg)
        }
        // ── Sheet scelta orario promemoria ───────────────────────────
        .sheet(isPresented: $showReminderTimePicker) {
            if let exam = pendingReminderExam, let dl = exam.deadline {
                NavigationStack {
                    VStack(spacing: 32) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(Color.orange.opacity(0.1)).frame(width: 56, height: 56)
                                Image(systemName: "bell.fill").font(.title2).foregroundStyle(.orange)
                            }
                            Text("Orario promemoria").font(.title3.bold())
                            Text("Scegli a che ora ricevere il promemoria per \"\(exam.name)\"")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top)
                        
                        DatePicker("Orario", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                        
                        Button {
                            showReminderTimePicker = false
                            scheduleReminder(exam: exam, date: dl)
                        } label: {
                            Text("Imposta promemoria")
                                .frame(maxWidth: .infinity).padding()
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange))
                                .foregroundStyle(.white).font(.headline)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                    .background(KBTheme.background(colorScheme).ignoresSafeArea())
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Annulla") { showReminderTimePicker = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
        .task(id: examId) {
            await reloadReminderState()
        }
        .onChange(of: showEditSheet) { _, isShowing in
            if !isShowing {
                Task { await reloadReminderState() }
            }
        }
    }
    
    // MARK: - Main content
    
    private var exam: KBMedicalExam? { exams.first }
    
    private func content(_ e: KBMedicalExam) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard(e)
                    if e.resultText != nil || e.resultDate != nil  { resultCard(e) }
                    if e.preparation != nil || e.location != nil   { detailsCard(e) }
                    if let notes = e.notes, !notes.isEmpty         { notesCard(notes) }
                    if e.prescribingVisitId != nil                 { prescribingVisitCard(e) }
                    ExamAttachmentsSection(examId: e.id, familyId: familyId)
                        .padding(.horizontal)
                    Color.clear.frame(height: 8)
                }
                .padding(.vertical, 16)
            }
            bottomActions(e)
        }
    }
    
    // MARK: - Header card
    
    private func headerCard(_ e: KBMedicalExam) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(statusColor(e.status).opacity(0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: e.status.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(statusColor(e.status))
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(e.name)
                            .font(.title3.bold())
                            .foregroundStyle(KBTheme.primaryText(colorScheme))
                            .multilineTextAlignment(.leading)
                        if e.isUrgent {
                            Text("Urgente")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(.red))
                        }
                    }
                    Label(e.status.rawValue, systemImage: e.status.icon)
                        .font(.caption)
                        .foregroundStyle(statusColor(e.status))
                    Text("Creato: \(e.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                Spacer(minLength: 8)
            }
            
            if let dl = e.deadline {
                Divider()
                let isOverdue = dl < Date() && (e.status == .pending || e.status == .booked)
                HStack(spacing: 10) {
                    Image(systemName: isOverdue ? "calendar.badge.exclamationmark" : "calendar")
                        .frame(width: 20)
                        .foregroundStyle(isOverdue ? .red : tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Da eseguire entro")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(dl.formatted(date: .long, time: .omitted))
                            .font(.subheadline.bold())
                            .foregroundStyle(isOverdue ? .red : KBTheme.primaryText(colorScheme))
                        if isOverdue {
                            Text("Scaduto")
                                .font(.caption2.bold()).foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    // ── Pulsante promemoria ──
                    Button {
                        toggleReminder(exam: e, date: dl)
                    } label: {
                        Image(systemName: reminderScheduled ? "bell.fill" : "bell")
                            .font(.system(size: 18))
                            .foregroundStyle(reminderScheduled ? .orange : .secondary)
                            .symbolEffect(.bounce, value: reminderScheduled)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(reminderScheduled ? "Rimuovi promemoria" : "Aggiungi promemoria")
                }
            }
            
            if e.syncState == .pendingUpsert {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.caption).foregroundStyle(.orange)
                    Text("In sincronizzazione...")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(detailCard)
        .padding(.horizontal)
    }
    
    // MARK: - Risultato
    
    private func resultCard(_ e: KBMedicalExam) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Risultato", systemImage: "doc.text.magnifyingglass")
                .font(.subheadline.bold()).foregroundStyle(tint)
            
            if let rd = e.resultDate {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Data risultato").font(.caption).foregroundStyle(.secondary)
                    Text(rd.formatted(date: .long, time: .omitted)).font(.subheadline.bold())
                }
            }
            
            if let rt = e.resultText, !rt.isEmpty {
                if e.resultDate != nil { Divider() }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Referto").font(.caption).foregroundStyle(.secondary)
                    Text(rt).font(.subheadline)
                }
            }
        }
        .padding(16)
        .background(detailCard)
        .padding(.horizontal)
    }
    
    // MARK: - Dettagli
    
    private func detailsCard(_ e: KBMedicalExam) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Dettagli", systemImage: "list.bullet.clipboard")
                .font(.subheadline.bold()).foregroundStyle(tint)
            
            if let p = e.preparation, !p.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preparazione").font(.caption).foregroundStyle(.secondary)
                    Text(p).font(.subheadline)
                }
            }
            
            if let loc = e.location, !loc.isEmpty {
                if e.preparation != nil { Divider() }
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .frame(width: 20).foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Luogo").font(.caption).foregroundStyle(.secondary)
                        Text(loc).font(.subheadline.bold())
                    }
                }
            }
        }
        .padding(16)
        .background(detailCard)
        .padding(.horizontal)
    }
    
    // MARK: - Note
    
    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Appunti", systemImage: "square.and.pencil")
                .font(.subheadline.bold()).foregroundStyle(tint)
            Text(notes).font(.subheadline)
        }
        .padding(16)
        .background(detailCard)
        .padding(.horizontal)
    }
    
    // MARK: - Visita prescrittrice
    
    private func prescribingVisitCard(_ e: KBMedicalExam) -> some View {
        PrescribingVisitRow(
            visitId:     e.prescribingVisitId!,
            familyId:    familyId,
            childId:     childId,
            tint:        tint,
            colorScheme: colorScheme
        )
        .padding(.horizontal)
    }
    
    // MARK: - Bottom actions
    
    private func bottomActions(_ e: KBMedicalExam) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    showEditSheet = true
                } label: {
                    Label("Modifica", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(tint))
                        .foregroundStyle(.white)
                        .font(.headline)
                }
                .buttonStyle(.plain)
                
                Button {
                    showDeleteAlert = true
                } label: {
                    Label("Elimina", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                        )
                        .foregroundStyle(.red)
                        .font(.headline)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(KBTheme.background(colorScheme))
    }
    
    // MARK: - Helpers
    
    private var detailCard: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(KBTheme.cardBackground(colorScheme))
            .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
    }
    
    private func statusColor(_ s: KBExamStatus) -> Color {
        switch s {
        case .pending:  return .orange
        case .booked:   return tint
        case .done:     return .green
        case .resultIn: return Color(red: 0.4, green: 0.75, blue: 0.65)
        }
    }
    
    // MARK: - Reminder
    
    private func toggleReminder(exam: KBMedicalExam, date: Date) {
        if reminderScheduled {
            KBExamReminderService.shared.cancel(examId: exam.id)
            reminderScheduled = false
            NotificationCenter.default.post(name: .examReminderChanged, object: nil)
            reminderAlertMsg  = "Promemoria rimosso."
            showReminderAlert = true
        } else {
            pendingReminderExam = exam
            showReminderTimePicker = true
        }
    }
    
    private func scheduleReminder(exam: KBMedicalExam, date: Date) {
        // FIX "bambino": usa resolveSubjectName() che fa un fetch sincrono
        // direttamente dal modelContext. Questo bypassa il timing lazy delle
        // @Query SwiftUI e funziona correttamente sia per KBChild che per
        // KBFamilyMember (genitori/adulti).
        let resolvedName = resolveSubjectName()
        
        KBExamReminderService.shared.schedule(
            examId:       exam.id,
            examName:     exam.name,
            childName:    resolvedName,
            familyId:     familyId,
            childId:      childId,
            date:         date,
            reminderTime: reminderTime
        ) { success in
            if success {
                self.reminderScheduled = true
                NotificationCenter.default.post(name: .examReminderChanged, object: nil)
                let cal = Calendar.current
                let h = cal.component(.hour,   from: self.reminderTime)
                let m = cal.component(.minute, from: self.reminderTime)
                self.reminderAlertMsg = "Promemoria impostato per il \(date.formatted(date: .long, time: .omitted)) alle \(String(format: "%02d:%02d", h, m))."
            } else {
                self.reminderAlertMsg = "Impossibile impostare il promemoria. Controlla i permessi in Impostazioni → Notifiche."
            }
            self.showReminderAlert = true
        }
    }
    
    // MARK: - Reminder state reload
    
    @MainActor
    private func reloadReminderState() async {
        let id = KBExamReminderService.shared.notificationId(for: examId)
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        reminderScheduled = requests.contains { $0.identifier == id }
        if let req = requests.first(where: { $0.identifier == id }),
           let cal = req.trigger as? UNCalendarNotificationTrigger,
           let h = cal.dateComponents.hour,
           let m = cal.dateComponents.minute,
           let restored = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) {
            reminderTime = restored
        }
    }
    
    private func deleteExam(_ e: KBMedicalExam) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        e.isDeleted     = true
        e.updatedAt     = Date()
        e.updatedBy     = uid
        e.syncState     = .pendingUpsert
        e.lastSyncError = nil
        try? modelContext.save()
        SyncCenter.shared.enqueueMedicalExamDelete(
            examId: e.id, familyId: familyId, modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        if !coordinator.path.isEmpty { coordinator.path.removeLast() }
    }
}

// MARK: - PrescribingVisitRow

private struct PrescribingVisitRow: View {
    let visitId:     String
    let familyId:    String
    let childId:     String
    let tint:        Color
    let colorScheme: ColorScheme
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query private var visits: [KBMedicalVisit]
    private var visit: KBMedicalVisit? { visits.first }
    
    init(visitId: String, familyId: String, childId: String,
         tint: Color, colorScheme: ColorScheme) {
        self.visitId     = visitId
        self.familyId    = familyId
        self.childId     = childId
        self.tint        = tint
        self.colorScheme = colorScheme
        let vid = visitId
        _visits = Query(filter: #Predicate<KBMedicalVisit> { $0.id == vid })
    }
    
    var body: some View {
        Button {
            coordinator.navigate(to: .pediatricVisitDetail(familyId: familyId, childId: childId, visitId: visitId))
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(tint.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "stethoscope").foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Visita prescrittrice")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(visit.flatMap { $0.reason.isEmpty ? nil : $0.reason } ?? "Visita")
                        .font(.subheadline.bold())
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                    if let date = visit?.date {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(KBTheme.cardBackground(colorScheme))
                    .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ExamAttachmentsSection

struct ExamAttachmentsSection: View {
    let examId:   String
    let familyId: String
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    
    @Query private var allDocs: [KBDocument]
    private var docs: [KBDocument] {
        allDocs.filter { ExamAttachmentTag.matches($0, examId: examId) }
    }
    
    @State private var previewURL:  URL? = nil
    @State private var showKeyAlert      = false
    
    private let tint = Color(red: 0.25, green: 0.65, blue: 0.75)
    
    init(examId: String, familyId: String) {
        self.examId   = examId
        self.familyId = familyId
        let fid = familyId
        _allDocs = Query(
            filter: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
    }
    
    var body: some View {
        if !docs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Allegati (\(docs.count))", systemImage: "paperclip")
                    .font(.subheadline.bold()).foregroundStyle(tint)
                ForEach(docs) { doc in
                    docRow(doc)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(KBTheme.cardBackground(colorScheme))
                    .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
            )
            .sheet(isPresented: Binding(
                get: { previewURL != nil },
                set: { if !$0 { previewURL = nil } }
            )) {
                if let url = previewURL {
                    QuickLookPreview(urls: [url], initialIndex: 0)
                }
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
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(0.06)
                      : Color.black.opacity(0.03))
        )
    }
    
    private func docIcon(_ doc: KBDocument) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.1)).frame(width: 36, height: 36)
            Image(systemName: mimeIcon(doc.mimeType))
                .foregroundStyle(tint).font(.subheadline)
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
            ExamAttachmentService.shared.open(
                doc:          doc,
                modelContext: modelContext,
                onURL:        { previewURL = $0 },
                onError:      { _ in },
                onKeyMissing: { showKeyAlert = true }
            )
        } label: {
            Image(systemName: "eye.fill").foregroundStyle(tint)
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
            EmptyView()
        }
    }
    
    private func extractionProgressLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
    
    private func mimeIcon(_ mime: String) -> String {
        if mime.contains("pdf")   { return "doc.fill" }
        if mime.contains("image") { return "photo.fill" }
        return "paperclip"
    }
}
