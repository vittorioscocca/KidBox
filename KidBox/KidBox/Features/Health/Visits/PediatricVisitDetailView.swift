//
//  PediatricVisitDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct PediatricVisitDetailView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    
    let familyId: String
    let childId:  String
    let visitId:  String
    
    @Query private var visits:   [KBMedicalVisit]
    @Query private var children: [KBChild]
    @Query private var members:  [KBFamilyMember]
    
    private var visit:     KBMedicalVisit? { visits.first }
    private var childName: String          { children.first?.name ?? members.first?.displayName ?? "bambino" }
    
    private var childForAI: KBChild? {
        if let child = children.first { return child }
        guard let member = members.first else { return nil }
        let now = Date()
        return KBChild(
            id:        childId,
            familyId:  familyId,
            name:      member.displayName ?? "Membro",
            birthDate: nil,
            createdBy: member.userId,
            createdAt: now,
            updatedBy: nil,
            updatedAt: now
        )
    }
    
    @State private var showEditSheet   = false
    @State private var showDeleteAlert = false
    
    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)
    
    init(familyId: String, childId: String, visitId: String) {
        self.familyId = familyId
        self.childId  = childId
        self.visitId  = visitId
        let vid = visitId
        let cid = childId
        _visits   = Query(filter: #Predicate<KBMedicalVisit>  { $0.id == vid })
        _children = Query(filter: #Predicate<KBChild>          { $0.id == cid })
        _members  = Query(filter: #Predicate<KBFamilyMember>   { $0.userId == cid })
    }
    
    var body: some View {
        Group {
            if let visit {
                content(visit)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            if let visit, let child = childForAI, AISettings.shared.isEnabled {
                AskAIButton(visit: visit, child: child)
                    .padding(.trailing, 20)
                    .padding(.bottom, 96)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let visit {
                PediatricVisitEditView(
                    familyId:  familyId,
                    childId:   childId,
                    childName: childName,
                    visitId:   visit.id
                )
            }
        }
        .alert("Elimina Visita", isPresented: $showDeleteAlert) {
            Button("Elimina", role: .destructive) {
                if let visit { deleteVisit(visit) }
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Questa azione non può essere annullata.")
        }
    }
    
    // MARK: - Main content
    
    private func content(_ v: KBMedicalVisit) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard(v)
                    if v.diagnosis != nil || v.recommendations != nil { outcomeCard(v) }
                    if !v.linkedTreatmentIds.isEmpty                  { treatmentsCard(v) }
                    if hasPrescriptions(v)                            { prescriptionsCard(v) }
                    VisitAttachmentsSectionReadOnly(visit: v)
                        .padding(.horizontal)
                    if v.nextVisitDate != nil                         { nextVisitCard(v) }
                    if let notes = v.notes, !notes.isEmpty            { notesCard(notes) }
                    Color.clear.frame(height: 8)
                }
                .padding(.vertical, 16)
            }
            bottomActions(v)
        }
    }
    
    // MARK: - Header
    
    private func headerCard(_ v: KBMedicalVisit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(0.12))
                            .frame(width: 56, height: 56)
                        Image(systemName: "stethoscope")
                            .font(.system(size: 24))
                            .foregroundStyle(tint)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(v.reason.isEmpty ? "Visita" : v.reason)
                            .font(.title3.bold())
                            .foregroundStyle(KBTheme.primaryText(colorScheme))
                            .multilineTextAlignment(.leading)
                        Text(v.date.formatted(date: .long, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(KBTheme.secondaryText(colorScheme))
                        // ── Stato visita ──
                        if let status = v.visitStatus {
                            Label(status.rawValue, systemImage: status.icon)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(statusColor(status).opacity(0.15)))
                                .foregroundStyle(statusColor(status))
                        }
                    }
                }
                Spacer(minLength: 8)
            }
            
            Divider()
            
            if let doctor = v.doctorName, !doctor.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "person.fill")
                        .frame(width: 20)
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Medico")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(doctor).font(.subheadline.bold())
                            if let spec = v.doctorSpecialization {
                                Text("· \(spec.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            
            if v.syncState == .pendingUpsert {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("In sincronizzazione...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(detailCard)
        .padding(.horizontal)
    }
    
    // MARK: - Diagnosi & Raccomandazioni
    
    private func outcomeCard(_ v: KBMedicalVisit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Esito della Visita", systemImage: "stethoscope")
                .font(.subheadline.bold()).foregroundStyle(tint)
            if let d = v.diagnosis, !d.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diagnosi").font(.caption).foregroundStyle(.secondary)
                    Text(d).font(.subheadline)
                }
            }
            if let r = v.recommendations, !r.isEmpty {
                if v.diagnosis != nil { Divider() }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Raccomandazioni").font(.caption).foregroundStyle(.secondary)
                    Text(r).font(.subheadline)
                }
            }
        }
        .padding(16)
        .background(detailCard)
        .padding(.horizontal)
    }
    
    // MARK: - Farmaci Programmati
    
    private func treatmentsCard(_ v: KBMedicalVisit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Farmaci Programmati (\(v.linkedTreatmentIds.count))", systemImage: "pills.fill")
                .font(.subheadline.bold()).foregroundStyle(tint)
            ForEach(v.linkedTreatmentIds, id: \.self) { tid in
                LinkedTreatmentDetailRow(treatmentId: tid, tint: tint, colorScheme: colorScheme)
            }
        }
        .padding(16)
        .background(detailCard)
        .padding(.horizontal)
    }
    
    // MARK: - Prescrizioni
    
    private func prescriptionsCard(_ v: KBMedicalVisit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Prescrizioni", systemImage: "cross.vial.fill")
                .font(.subheadline.bold()).foregroundStyle(tint)
            
            if !v.asNeededDrugs.isEmpty {
                prescriptionSection(title: "Al Bisogno", icon: "cross.vial.fill") {
                    ForEach(v.asNeededDrugs) { drug in
                        HStack(spacing: 8) {
                            Circle().fill(tint.opacity(0.15)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(drug.drugName).font(.subheadline.bold())
                                Text("\(drug.dosageValue, specifier: "%.0f") \(drug.dosageUnit) · \(drug.instructions ?? "")")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            
            if !v.therapyTypes.isEmpty {
                if !v.asNeededDrugs.isEmpty { Divider() }
                prescriptionSection(title: "Terapie", icon: "figure.walk") {
                    FlowLayout(spacing: 6) {
                        ForEach(v.therapyTypes, id: \.self) { t in
                            Text(t.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(tint.opacity(0.1)))
                                .foregroundStyle(tint)
                        }
                    }
                }
            }
            
            if !v.linkedExamIds.isEmpty {
                if !v.asNeededDrugs.isEmpty || !v.therapyTypes.isEmpty { Divider() }
                prescriptionSection(title: "Esami Prescritti (\(v.linkedExamIds.count))", icon: "testtube.2") {
                    ForEach(v.linkedExamIds, id: \.self) { eid in
                        LinkedExamDetailRow(
                            examId:      eid,
                            tint:        tint,
                            colorScheme: colorScheme,
                            familyId:    familyId,
                            childId:     childId
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(detailCard)
        .padding(.horizontal)
    }
    
    // MARK: - Prossimo Appuntamento
    
    private func nextVisitCard(_ v: KBMedicalVisit) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.green.opacity(0.12)).frame(width: 44, height: 44)
                Image(systemName: "calendar.badge.plus").foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Prossimo Appuntamento")
                    .font(.caption).foregroundStyle(.secondary)
                Text(v.nextVisitDate!.formatted(date: .long, time: .omitted))
                    .font(.subheadline.bold())
                if let r = v.nextVisitReason, !r.isEmpty {
                    Text(r).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
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
    
    // MARK: - Bottom actions
    
    private func bottomActions(_ v: KBMedicalVisit) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { showEditSheet = true } label: {
                    Label("Modifica", systemImage: "pencil")
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(tint))
                        .foregroundStyle(.white).font(.headline)
                }
                .buttonStyle(.plain)
                Button { showDeleteAlert = true } label: {
                    Label("Elimina", systemImage: "trash")
                        .frame(maxWidth: .infinity).padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                        )
                        .foregroundStyle(.red).font(.headline)
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
    
    private func prescriptionSection<C: View>(title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
    }
    
    private func hasPrescriptions(_ v: KBMedicalVisit) -> Bool {
        !v.asNeededDrugs.isEmpty || !v.therapyTypes.isEmpty || !v.linkedExamIds.isEmpty
    }
    
    private func statusColor(_ status: KBVisitStatus) -> Color {
        switch status {
        case .pending:         return .gray
        case .booked:          return .blue
        case .completed:       return .green
        case .resultAvailable: return .purple
        }
    }
    
    private func deleteVisit(_ v: KBMedicalVisit) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        v.isDeleted    = true
        v.updatedAt    = Date()
        v.updatedBy    = uid
        v.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        try? modelContext.save()
        SyncCenter.shared.enqueueVisitDelete(visitId: v.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        if !coordinator.path.isEmpty { coordinator.path.removeLast() }
    }
}

// MARK: - LinkedTreatmentDetailRow
// Tappabile → apre TreatmentDetailView in sheet

private struct LinkedTreatmentDetailRow: View {
    let treatmentId: String
    let tint:        Color
    let colorScheme: ColorScheme
    
    @Query private var treatments: [KBTreatment]
    private var treatment: KBTreatment? { treatments.first }
    @State private var showDetail = false
    
    init(treatmentId: String, tint: Color, colorScheme: ColorScheme) {
        self.treatmentId = treatmentId
        self.tint        = tint
        self.colorScheme = colorScheme
        let tid = treatmentId
        _treatments = Query(filter: #Predicate<KBTreatment> { $0.id == tid })
    }
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.1)).frame(width: 36, height: 36)
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
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            NavigationStack {
                VisitDetailTreatmentWrapper(treatmentId: treatmentId)
            }
        }
    }
}

// MARK: - LinkedExamDetailRow
// Tappabile → apre PediatricExamDetailView in sheet

private struct LinkedExamDetailRow: View {
    let examId:      String
    let tint:        Color
    let colorScheme: ColorScheme
    let familyId:    String
    let childId:     String
    
    @Query private var exams: [KBMedicalExam]
    private var exam: KBMedicalExam? { exams.first }
    @State private var showDetail = false
    
    init(examId: String, tint: Color, colorScheme: ColorScheme, familyId: String, childId: String) {
        self.examId      = examId
        self.tint        = tint
        self.colorScheme = colorScheme
        self.familyId    = familyId
        self.childId     = childId
        let eid = examId
        _exams = Query(filter: #Predicate<KBMedicalExam> { $0.id == eid })
    }
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(exam?.isUrgent == true ? Color.red.opacity(0.12) : tint.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "testtube.2")
                    .foregroundStyle(exam?.isUrgent == true ? .red : tint)
                    .font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(exam?.name ?? "Caricamento...").font(.subheadline.bold())
                    if exam?.isUrgent == true {
                        Text("Urgente")
                            .font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.red))
                    }
                }
                if let d = exam?.deadline {
                    Text("Entro: \(d.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let p = exam?.preparation, !p.isEmpty {
                    Text(p).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let s = exam?.status {
                    Label(s.rawValue, systemImage: s.icon)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            NavigationStack {
                PediatricExamDetailView(
                    familyId: familyId,
                    childId:  childId,
                    examId:   examId
                )
            }
        }
    }
}

// MARK: - VisitDetailTreatmentWrapper
// Fetcha KBTreatment per id e lo passa a TreatmentDetailView (@Bindable)

private struct VisitDetailTreatmentWrapper: View {
    let treatmentId: String
    @Query private var treatments: [KBTreatment]
    private var treatment: KBTreatment? { treatments.first }
    
    init(treatmentId: String) {
        self.treatmentId = treatmentId
        let tid = treatmentId
        _treatments = Query(filter: #Predicate<KBTreatment> { $0.id == tid })
    }
    
    var body: some View {
        if let treatment {
            TreatmentDetailView(treatment: treatment)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - VisitAttachmentsSectionReadOnly
// Versione sola lettura: niente +, niente cestino. Solo occhio.

private struct VisitAttachmentsSectionReadOnly: View {
    
    let visit: KBMedicalVisit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    
    @Query private var attachments: [KBDocument]
    @State private var previewURL:  URL?   = nil
    @State private var showKeyAlert: Bool  = false
    @State private var errorText:   String? = nil
    
    private let tint    = Color(red: 0.35, green: 0.6, blue: 0.85)
    private let service = VisitAttachmentService.shared
    
    init(visit: KBMedicalVisit) {
        self.visit = visit
        let fid = visit.familyId
        _attachments = Query(
            filter: #Predicate<KBDocument> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBDocument.createdAt, order: .reverse)]
        )
    }
    
    private var visitAttachments: [KBDocument] {
        let tag = VisitAttachmentTag.make(visit.id)
        return attachments.filter { $0.notes == tag }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Allegati", systemImage: "paperclip")
                .font(.subheadline.bold())
                .foregroundStyle(tint)
            
            if let err = errorText {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            
            if visitAttachments.isEmpty {
                Text("Nessun allegato")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(visitAttachments) { doc in
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(tint.opacity(0.1))
                                    .frame(width: 36, height: 36)
                                Image(systemName: mimeIcon(doc.mimeType))
                                    .foregroundStyle(tint).font(.subheadline)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(doc.title).font(.subheadline).lineLimit(1)
                                Text(sizeLabel(doc.fileSize))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                errorText = nil
                                service.open(
                                    doc: doc,
                                    modelContext: modelContext,
                                    onURL: { previewURL = $0 },
                                    onError: { errorText = $0 },
                                    onKeyMissing: { showKeyAlert = true }
                                )
                            } label: {
                                Image(systemName: "eye.fill")
                                    .foregroundStyle(tint).font(.subheadline)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(KBTheme.inputBackground(colorScheme))
                        )
                    }
                }
            }
            
            Text("Visibili anche in Documenti › Salute › Referti")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(KBTheme.cardBackground(colorScheme))
                .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
        )
        .sheet(isPresented: Binding(get: { previewURL != nil }, set: { if !$0 { previewURL = nil } })) {
            if let url = previewURL { QuickLookPreview(urls: [url], initialIndex: 0) }
        }
        .alert("Chiave mancante", isPresented: $showKeyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Chiave di crittografia non trovata. Verifica le impostazioni famiglia.")
        }
    }
    
    private func mimeIcon(_ mime: String) -> String {
        if mime.contains("pdf")   { return "doc.fill" }
        if mime.contains("image") { return "photo.fill" }
        if mime.contains("word")  { return "doc.text.fill" }
        return "paperclip"
    }
    
    private func sizeLabel(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}

// MARK: - FlowLayout (chip wrap)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
