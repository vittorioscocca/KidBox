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
    
    /// Restituisce il KBChild se esiste, altrimenti ne crea uno sintetico dal membro.
    /// Usato per AskAIButton che richiede sempre un KBChild.
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
        .sheet(isPresented: $showEditSheet) {
            if let visit {
                PediatricVisitEditView(
                    familyId: familyId,
                    childId: childId,
                    childName: childName,
                    visitId: visit.id
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
                    VisitAttachmentsSection(visit: v)
                        .padding(.horizontal)
                    if v.nextVisitDate != nil                         { nextVisitCard(v) }
                    if let notes = v.notes, !notes.isEmpty            { notesCard(notes) }
                    
                    // Spazio extra prima dei bottoni
                    Color.clear.frame(height: 8)
                }
                .padding(.vertical, 16)
            }
            
            // ── Bottoni azioni ──
            bottomActions(v)
        }
    }
    
    // MARK: - Header
    
    private func headerCard(_ v: KBMedicalVisit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Icona + titolo
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
                    Text(v.date.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
            }
            
            Divider()
            
            // Medico
            if let doctor = v.doctorName, !doctor.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "person.fill")
                        .frame(width: 20).foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Medico").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(doctor).font(.subheadline.bold())
                            if let spec = v.doctorSpecialization {
                                Text("· \(spec.rawValue)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            
            // Sync state
            if v.syncState == .pendingUpsert {
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
            
            // Al bisogno
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
            
            // Terapie
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
            
            // Esami prescritti
            if !v.prescribedExams.isEmpty {
                if !v.asNeededDrugs.isEmpty || !v.therapyTypes.isEmpty { Divider() }
                prescriptionSection(title: "Esami Prescritti (\(v.prescribedExams.count))", icon: "testtube.2") {
                    ForEach(v.prescribedExams) { exam in
                        HStack(spacing: 8) {
                            Circle().fill(exam.isUrgent ? Color.red.opacity(0.8) : tint.opacity(0.15))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(exam.name).font(.subheadline.bold())
                                    if exam.isUrgent {
                                        Text("Urgente")
                                            .font(.caption2.bold()).foregroundStyle(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(.red))
                                    }
                                }
                                if let d = exam.deadline {
                                    Text("Entro: \(d.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if let p = exam.preparation, !p.isEmpty {
                                    Text(p).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                        .padding(.vertical, 2)
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
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(.green)
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
            
            // ── Chiedi all'AI ──
            if let child = childForAI {
                AskAIButton(visit: v, child: child)
                    .padding(.horizontal)
            }
            
            // ── Modifica / Elimina ──
            HStack(spacing: 12) {
                Button {
                    showEditSheet = true
                } label: {
                    Label("Modifica", systemImage: "pencil")
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(tint))
                        .foregroundStyle(.white).font(.headline)
                }
                .buttonStyle(.plain)
                
                Button {
                    showDeleteAlert = true
                } label: {
                    Label("Elimina", systemImage: "trash")
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.5), lineWidth: 1.5))
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
        !v.asNeededDrugs.isEmpty || !v.therapyTypes.isEmpty || !v.prescribedExams.isEmpty
    }
    
    private func deleteVisit(_ v: KBMedicalVisit) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        v.isDeleted  = true
        v.updatedAt  = Date()
        v.updatedBy  = uid
        v.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        try? modelContext.save()
        SyncCenter.shared.enqueueVisitDelete(
            visitId: v.id, familyId: familyId, modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        if !coordinator.path.isEmpty { coordinator.path.removeLast() }
    }
}

// MARK: - LinkedTreatmentDetailRow

private struct LinkedTreatmentDetailRow: View {
    let treatmentId: String
    let tint: Color
    let colorScheme: ColorScheme
    
    @Query private var treatments: [KBTreatment]
    private var treatment: KBTreatment? { treatments.first }
    
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
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
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
