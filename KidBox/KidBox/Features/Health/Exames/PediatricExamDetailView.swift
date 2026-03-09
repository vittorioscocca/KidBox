//
//  PediatricExamDetailView.swift
//  KidBox
//
//  Created by vscocca on 09/03/26.
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
    
    private var exam:      KBMedicalExam? { exams.first }
    private var childName: String         { children.first?.name ?? members.first?.displayName ?? "bambino" }
    
    @State private var showEditSheet   = false
    @State private var showDeleteAlert = false
    
    // Stesso tint di PediatricExamsView
    private let tint = Color(red: 0.25, green: 0.65, blue: 0.75)
    
    init(familyId: String, childId: String, examId: String) {
        self.familyId = familyId
        self.childId  = childId
        self.examId   = examId
        let eid = examId
        let cid = childId
        _exams    = Query(filter: #Predicate<KBMedicalExam>  { $0.id == eid })
        _children = Query(filter: #Predicate<KBChild>         { $0.id == cid })
        _members  = Query(filter: #Predicate<KBFamilyMember>  { $0.userId == cid })
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
    }
    
    // MARK: - Main content
    
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
    // Campi: nome, badge urgente, stato, scadenza, sync badge
    
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
            
            // Scadenza — mostrata solo se presente
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
                }
            }
            
            // Sync badge
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
    // Campi: resultDate, resultText
    
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
    // Campi: preparation, location
    
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
// Carica la visita prescrittrice via @Query e mostra un link navigabile verso il detail.

private struct PrescribingVisitRow: View {
    let visitId:    String
    let familyId:   String
    let childId:    String
    let tint:       Color
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
// Mostra i KBDocument allegati all'esame (read-only, con anteprima).
// Segue lo stesso pattern di VisitAttachmentsSection.

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
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark
                                  ? Color.white.opacity(0.06)
                                  : Color.black.opacity(0.03))
                    )
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
    
    private func mimeIcon(_ mime: String) -> String {
        if mime.contains("pdf")   { return "doc.fill" }
        if mime.contains("image") { return "photo.fill" }
        return "paperclip"
    }
}
