//
//  WorkHomeView.swift
//  KidBox
//
//  Scheda «Lavoro»: busta paga e contratto di un adulto, letti dall'AI e
//  salvati con i loro valori (ferie, permessi, tasse, scadenza…). L'assistente
//  li ritrova nel quaderno (`lavoro.md`) e risponde alle domande. Privata di
//  default; si può condividere con un altro adulto della famiglia.
//

import SwiftUI
import SwiftData
import PDFKit
import QuickLook
import UniformTypeIdentifiers
import FirebaseAuth

struct WorkHomeView: View {

    let familyId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var subscriptionManager: KBSubscriptionManager

    @Query private var profiles: [KBWorkProfile]
    @Query private var records: [KBWorkRecord]
    @Query private var members: [KBFamilyMember]

    @State private var selectedOwner: String?
    @State private var showUpgrade = false
    @State private var showOwnerOnly = false
    @State private var showShare = false
    @State private var shareScope = KBVisibilityScope.onlyCreator
    @State private var shareMembers = Set<String>()

    // Il «+» è il foglio di sempre (come in Salute): fotocamera, libreria, file, Documenti di KidBox.
    @State private var showSourceSheet = false
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var showFileImporter = false
    @State private var showKidBoxPicker = false
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var draft: WorkDraft?
    @State private var detailRecord: KBWorkRecord?

    private let tint = Color(red: 0.25, green: 0.45, blue: 0.75)

    private var me: String { Auth.auth().currentUser?.uid ?? "" }
    private var isMine: Bool { owner == me }
    private var owner: String { selectedOwner ?? me }
    private var isPaid: Bool { subscriptionManager.currentPlan != .free }

    private var myProfile: KBWorkProfile? { profiles.first { $0.id == me && $0.familyId == familyId } }

    /// Io, e gli adulti che mi hanno condiviso la loro scheda.
    private var owners: [String] {
        let others = profiles
            .filter { $0.familyId == familyId && !$0.isDeleted && $0.id != me && $0.isVisible(to: me) }
            .map(\.id)
        return [me] + others
    }

    private func name(of uid: String) -> String {
        if uid == me { return String(localized: "Io") }
        return members.first { $0.userId == uid }?.displayName ?? String(localized: "Un familiare")
    }

    private var ownerRecords: [KBWorkRecord] {
        records
            .filter { $0.familyId == familyId && $0.ownerUid == owner && !$0.isDeleted }
            .sorted { $0.referenceDate > $1.referenceDate }
    }

    private func fields(_ r: KBWorkRecord) -> WorkFields? { WorkRecordCrypto.open(r, userId: me) }

    private var latestPayslip: (KBWorkRecord, WorkFields)? {
        ownerRecords.first { $0.isPayslip }.flatMap { r in fields(r).map { (r, $0) } }
    }
    private var latestContract: (KBWorkRecord, WorkFields)? {
        ownerRecords.first { $0.isContract }.flatMap { r in fields(r).map { (r, $0) } }
    }

    /// I periodi dei fogli ferie, da oggi in poi.
    private var upcomingLeave: [WorkLeavePeriod] {
        let today = Calendar.current.startOfDay(for: Date())
        return ownerRecords.filter { $0.isLeavePlan }
            .compactMap { fields($0) }
            .flatMap(\.leavePeriods)
            .filter { ($0.endDay ?? .distantPast) >= today }
            .sorted { ($0.startDay ?? .distantPast) < ($1.startDay ?? .distantPast) }
    }

    var body: some View {
        Group {
            if !isPaid {
                lockedView
            } else {
                content
            }
        }
        .navigationTitle("Lavoro")
        .navigationBarTitleDisplayMode(.inline)
        .ownerOnlyAlert(isPresented: $showOwnerOnly)
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView(triggerFeature: "work_lock")
                .environmentObject(KBSubscriptionManager.shared)
        }
        .onAppear { AppAnalytics.screenView(name: "lavoro") }
    }

    // MARK: - Free

    private var lockedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "briefcase.fill")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Lavoro")
                .font(.title2.bold())
            Text("Busta paga e contratto, con l'assistente che ti dice ferie, permessi, tasse e scadenze. Disponibile con i piani Pro e Max.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                guard KBSubscriptionManager.shared.isFamilyOwner else { showOwnerOnly = true; return }
                showUpgrade = true
            } label: {
                Text("Scopri i piani")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(tint))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { AppAnalytics.aiPaywallShown(context: "work_locked") }
    }

    // MARK: - Contenuto

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if owners.count > 1 { ownerChips }
                if isMine { sharingRow }
                summary
                if isMine { askChips }
                recordsList
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .background(KBTheme.background(colorScheme))
        .toolbar {
            if isMine {
                ToolbarItem(placement: .topBarTrailing) { addMenu }
            }
        }
        .overlay {
            if isAnalyzing {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Sto leggendo il documento…").font(.footnote.weight(.medium))
                }
                .padding(22)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .sheet(isPresented: $showSourceSheet) {
            AttachmentSourcePickerSheet(
                tint: tint,
                onCamera:   { pick { showCamera = true } },
                onGallery:  { pick { showGallery = true } },
                onDocument: { pick { showFileImporter = true } },
                onKidBoxDocument: { pick { showKidBoxPicker = true } }
            )
        }
        .sheet(isPresented: $showCamera) {
            ImagePickerView(sourceType: .camera) { image in analyzeImage(image) }
        }
        .sheet(isPresented: $showGallery) {
            ImagePickerView(sourceType: .photoLibrary) { image in analyzeImage(image) }
        }
        .sheet(isPresented: $showKidBoxPicker) {
            KidBoxDocumentPickerSheet(familyId: familyId) { url in
                Task { await importFile(url) }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await importFile(url) }
        }
        .sheet(item: $draft) { d in
            WorkConfirmSheet(draft: d) { fields, referenceDate in
                save(draft: d, fields: fields, referenceDate: referenceDate)
            }
        }
        .sheet(item: $detailRecord) { r in
            WorkRecordDetailView(record: r, fields: fields(r), canEdit: r.ownerUid == me) {
                delete(r)
            }
        }
        .sheet(isPresented: $showShare) {
            VisibilityPickerSheet(
                selectedScope: $shareScope,
                selectedMemberIds: $shareMembers,
                members: members.filter { $0.familyId == familyId && !$0.isDeleted },
                currentUid: me,
                scopeSectionTitle: "Chi può vedere la tua scheda Lavoro",
                allowedScopes: [KBVisibilityScope.onlyCreator, KBVisibilityScope.members]
            ) { scope, ids in
                applySharing(scope: scope, ids: ids)
            }
        }
    }

    private var ownerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(owners, id: \.self) { uid in
                    Button { selectedOwner = uid } label: {
                        Text(name(of: uid))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(owner == uid ? tint : KBTheme.inputBackground(colorScheme)))
                            .foregroundStyle(owner == uid ? .white : .primary)
                    }
                }
            }
        }
    }

    private var sharingRow: some View {
        Button {
            let p = ensureProfile()
            shareScope = KBWorkProfile.normalizedScope(p.visibilityScope)
            shareMembers = Set(p.visibilityMemberIds)
            showShare = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: (myProfile?.visibilityScope == KBVisibilityScope.members) ? "person.2.fill" : "lock.fill")
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sharingTitle).font(.subheadline.weight(.semibold))
                    Text("Solo chi scegli può vedere buste paga e contratti.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(KBTheme.inputBackground(colorScheme)))
        }
        .buttonStyle(.plain)
    }

    private var sharingTitle: String {
        guard let p = myProfile, p.visibilityScope == KBVisibilityScope.members, !p.visibilityMemberIds.isEmpty else {
            return String(localized: "Solo io")
        }
        let names = p.visibilityMemberIds.map { name(of: $0) }.joined(separator: ", ")
        return String(format: String(localized: "Condivisa con %@"), names)
    }

    // MARK: - Riepilogo

    @ViewBuilder
    private var summary: some View {
        if let (_, f) = latestPayslip {
            card(title: String(format: String(localized: "Ultima busta paga · %@"), f.period.isEmpty ? f.title : f.period)) {
                row("Ferie residue", f.vacationRemaining.map { Self.days($0) })
                row("Permessi residui", f.permitHoursRemaining.map { Self.hours($0) })
                row("Lordo", f.gross.map(Self.euro))
                row("Imposte trattenute", f.taxes.map(Self.euro))
                row("Netto", f.net.map(Self.euro))
                row("TFR", f.tfr.map(Self.euro))
            }
        }
        if let (_, f) = latestContract {
            card(title: String(localized: "Contratto")) {
                row("Tipo", f.contractType.isEmpty ? nil : f.contractType)
                row("Livello / CCNL", f.level.isEmpty ? nil : f.level)
                row("Retribuzione annua lorda", f.grossAnnual.map(Self.euro))
                row("Inizio", WorkFields.parseDay(f.startDate).map(Self.date))
                row("Scadenza", WorkFields.parseDay(f.endDate).map(Self.date)
                    ?? (f.contractType.lowercased().contains("indeterm") ? String(localized: "Nessuna (tempo indeterminato)") : nil))
                row("Preavviso", f.noticePeriod.isEmpty ? nil : f.noticePeriod)
            }
        }
        if !upcomingLeave.isEmpty {
            card(title: String(localized: "Ferie programmate")) {
                ForEach(upcomingLeave.prefix(6)) { p in
                    HStack {
                        Text(p.label.isEmpty ? String(localized: "Ferie") : p.label)
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(Self.period(p)).font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        if latestPayslip == nil && latestContract == nil && upcomingLeave.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                Text(LocalizedStringKey(isMine ? "Carica una busta paga o un contratto" : "Nessun documento"))
                    .font(.headline)
                if isMine {
                    Text("L'assistente li legge una volta sola, poi puoi chiedergli ferie, permessi, tasse e scadenze.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }

    private func card<C: View>(title: String, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.bold))
            body()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(KBTheme.inputBackground(colorScheme)))
    }

    @ViewBuilder
    private func row(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.subheadline.weight(.semibold))
            }
        }
    }

    // MARK: - Domande all'assistente

    @ViewBuilder
    private var askChips: some View {
        if latestPayslip != nil || latestContract != nil || !upcomingLeave.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Chiedi all'assistente").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedQuestions, id: \.self) { q in
                            Button { ask(q) } label: {
                                Text(q).font(.footnote.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().strokeBorder(tint.opacity(0.5)))
                                    .foregroundStyle(tint)
                            }
                        }
                    }
                }
            }
        }
    }

    private var suggestedQuestions: [String] {
        var q = [String]()
        if latestPayslip != nil {
            q += [String(localized: "Quante ferie e permessi mi restano?"),
                  String(localized: "Quanto ho pagato di tasse finora?")]
        }
        if !upcomingLeave.isEmpty {
            q.append(String(localized: "Quando sono in ferie?"))
        }
        if latestContract != nil {
            q += [String(localized: "Quando scade il mio contratto?"),
                  String(localized: "Qual è il mio lordo annuo?")]
        }
        return q
    }

    private func ask(_ question: String) {
        coordinator.pendingAssistantDraft = question
        coordinator.navigate(to: .askExpert)
    }

    // MARK: - Elenco documenti

    @ViewBuilder
    private var recordsList: some View {
        if !ownerRecords.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Documenti").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(ownerRecords, id: \.id) { r in
                    Button { detailRecord = r } label: {
                        HStack(spacing: 12) {
                            Image(systemName: r.isPayslip ? "banknote" : (r.isLeavePlan ? "calendar" : "doc.text"))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(tint.opacity(0.12)))
                                .foregroundStyle(tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(of: r)).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(Self.date(r.referenceDate)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if r.attachmentDocumentId != nil {
                                Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(KBTheme.inputBackground(colorScheme)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func title(of r: KBWorkRecord) -> String {
        if let f = fields(r), !f.title.isEmpty { return f.title }
        if r.isLeavePlan { return String(localized: "Piano ferie") }
        return r.isPayslip ? String(localized: "Busta paga") : String(localized: "Contratto")
    }

    // MARK: - Aggiunta

    private var addMenu: some View {
        Button { showSourceSheet = true } label: { Image(systemName: "plus") }
            .disabled(isAnalyzing)
            .accessibilityLabel(Text("Carica un documento"))
    }

    /// Chiude il foglio delle sorgenti e apre la sorgente scelta: due sheet
    /// consecutivi chiedono una pausa.
    private func pick(_ open: @escaping () -> Void) {
        showSourceSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: open)
    }

    private func analyzeImage(_ image: UIImage) {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            errorMessage = String(localized: "Impossibile leggere il file.")
            return
        }
        Task { await analyze(data: jpeg, fileName: Self.stampedName(String(localized: "Foto"), "jpg"), mime: "image/jpeg") }
    }

    private static func stampedName(_ base: String, _ ext: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"
        return "\(base) \(f.string(from: Date())).\(ext)"
    }

    private func importFile(_ url: URL) async {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            errorMessage = String(localized: "Impossibile leggere il file.")
            return
        }
        let isPDF = url.pathExtension.lowercased() == "pdf"
        await analyze(data: data, fileName: url.lastPathComponent, mime: isPDF ? "application/pdf" : "image/jpeg")
    }

    private func analyze(data: Data, fileName: String, mime: String) async {
        guard !isAnalyzing else { return }
        errorMessage = nil
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let result = try await WorkDocumentService.analyze(data: data, fileName: fileName, mimeType: mime)
            AppAnalytics.aiMessageSent(agentType: "lavoro", plan: KBSubscriptionManager.shared.currentPlan.rawValue)
            draft = WorkDraft(kind: result.kind, fields: result.fields, referenceDate: result.referenceDate,
                              data: data, fileName: fileName, mimeType: mime)
        } catch WorkDocumentService.AnalyzeError.notAWorkDocument {
            errorMessage = String(localized: "Non sembra una busta paga, un contratto né un foglio ferie.")
        } catch WorkDocumentService.AnalyzeError.unreadable {
            errorMessage = String(localized: "Si leggono solo PDF e immagini.")
        } catch WorkDocumentService.AnalyzeError.badResponse {
            errorMessage = String(localized: "Non sono riuscito a leggere il documento. Riprova con una foto più nitida.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Salvataggio

    @discardableResult
    private func ensureProfile() -> KBWorkProfile {
        if let p = myProfile { return p }
        let p = KBWorkProfile(ownerUid: me, familyId: familyId, ownerName: name(of: me))
        modelContext.insert(p)
        try? modelContext.save()
        SyncCenter.shared.enqueueWorkProfileUpsert(ownerUid: me, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        return p
    }

    private func save(draft d: WorkDraft, fields: WorkFields, referenceDate: Date) {
        guard !me.isEmpty else { return }
        let profile = ensureProfile()
        let displayName = name(of: me)

        let record = KBWorkRecord(familyId: familyId, ownerUid: me, ownerName: displayName,
                                  kind: d.kind, referenceDate: referenceDate)
        do {
            try WorkRecordCrypto.seal(fields, into: record, userId: me)
        } catch {
            errorMessage = String(localized: "Non riesco a cifrare il documento: la chiave di famiglia non è disponibile.")
            return
        }
        var fields = fields
        if d.kind == WorkRecordKind.leavePlan {
            fields.eventIds = createLeaveEvents(fields.leavePeriods, ownerName: displayName)
        }
        do {
            try WorkRecordCrypto.seal(fields, into: record, userId: me)
        } catch {
            errorMessage = String(localized: "Non riesco a cifrare il documento: la chiave di famiglia non è disponibile.")
            return
        }
        record.attachmentDocumentId = WorkAttachmentService.shared.upload(
            data: d.data, fileName: d.fileName, mimeType: d.mimeType,
            title: fields.title.isEmpty ? d.fileName : fields.title,
            ownerUid: me, familyId: familyId, modelContext: modelContext,
            visibilityScope: profile.visibilityScope == KBVisibilityScope.members && !profile.visibilityMemberIds.isEmpty
                ? KBVisibilityScope.members : KBVisibilityScope.onlyCreator,
            visibilityMemberIds: profile.visibilityScope == KBVisibilityScope.members ? profile.visibilityMemberIds : []
        )
        record.syncState = .pendingUpsert
        modelContext.insert(record)

        if profile.employerEnc == nil, !fields.employer.isEmpty {
            try? WorkRecordCrypto.sealEmployer(fields.employer, into: profile, userId: me)
            profile.updatedAt = .now
            profile.syncState = .pendingUpsert
            SyncCenter.shared.enqueueWorkProfileUpsert(ownerUid: me, familyId: familyId, modelContext: modelContext)
        }
        try? modelContext.save()
        SyncCenter.shared.enqueueWorkRecordUpsert(recordId: record.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        draft = nil
    }

    /// Un evento «giornata intera» per periodo, visibile a tutta la famiglia
    /// (il calendario chiude i tutto-il-giorno alle 23:59:59 dell'ultimo giorno).
    private func createLeaveEvents(_ periods: [WorkLeavePeriod], ownerName: String) -> [String] {
        let cal = Calendar.current
        var ids: [String] = []
        for p in periods {
            guard let first = p.startDay else { continue }
            let start = cal.startOfDay(for: first)
            let lastDay = cal.startOfDay(for: max(p.endDay ?? first, first))
            guard let next = cal.date(byAdding: .day, value: 1, to: lastDay) else { continue }
            let label = p.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = "\(label.isEmpty ? String(localized: "Ferie") : label) · \(ownerName)"
            let event = KBCalendarEvent(
                familyId: familyId, childId: nil, title: title,
                startDate: start, endDate: next.addingTimeInterval(-1), isAllDay: true,
                visibilityScope: KBVisibilityScope.family,
                updatedBy: me, createdBy: me
            )
            event.syncState = .pendingUpsert
            modelContext.insert(event)
            SyncCenter.shared.enqueueCalendarUpsert(eventId: event.id, familyId: familyId, modelContext: modelContext)
            ids.append(event.id)
        }
        return ids
    }

    private func delete(_ r: KBWorkRecord) {
        // Gli eventi creati dal foglio ferie se ne vanno con lui.
        if r.isLeavePlan, let f = fields(r) {
            for eid in f.eventIds {
                guard let ev = try? modelContext.fetch(FetchDescriptor<KBCalendarEvent>(predicate: #Predicate { $0.id == eid })).first else { continue }
                ev.isDeleted = true
                ev.updatedAt = Date()
                ev.updatedBy = me
                SyncCenter.shared.enqueueCalendarDelete(eventId: eid, familyId: familyId, modelContext: modelContext)
                modelContext.delete(ev)
            }
        }
        if let docId = r.attachmentDocumentId {
            WorkAttachmentService.shared.delete(documentId: docId, familyId: familyId, modelContext: modelContext)
        }
        r.isDeleted = true
        r.syncState = .pendingDelete
        try? modelContext.save()
        SyncCenter.shared.enqueueWorkRecordDelete(recordId: r.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        detailRecord = nil
    }

    private func applySharing(scope: String, ids: Set<String>) {
        let p = ensureProfile()
        let sharing = scope == KBVisibilityScope.members && !ids.subtracting([me]).isEmpty
        p.visibilityScope = sharing ? KBVisibilityScope.members : KBVisibilityScope.onlyCreator
        p.visibilityMemberIds = sharing ? Array(ids.subtracting([me])).sorted() : []
        p.updatedAt = .now
        p.updatedBy = me
        p.syncState = .pendingUpsert
        try? modelContext.save()
        SyncCenter.shared.enqueueWorkProfileUpsert(ownerUid: me, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        WorkAttachmentService.shared.syncVisibility(ownerUid: me, familyId: familyId,
                                                    sharedWith: p.visibilityMemberIds, modelContext: modelContext)
    }

    // MARK: - Formati

    static func kindTitle(_ kind: String) -> LocalizedStringKey {
        switch kind {
        case WorkRecordKind.payslip: return "Busta paga"
        case WorkRecordKind.leavePlan: return "Piano ferie"
        default: return "Contratto"
        }
    }

    static func euro(_ v: Double) -> String { v.formatted(.currency(code: "EUR")) }
    static func days(_ v: Double) -> String {
        String(format: String(localized: "%@ giorni"), v.formatted(.number.precision(.fractionLength(0...2))))
    }
    static func hours(_ v: Double) -> String {
        String(format: String(localized: "%@ ore"), v.formatted(.number.precision(.fractionLength(0...2))))
    }
    static func date(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .omitted) }
    static func period(_ p: WorkLeavePeriod) -> String {
        guard let s = p.startDay else { return "" }
        guard let e = p.endDay, e > s else { return date(s) }
        return "\(date(s)) – \(date(e))"
    }
}

// MARK: - Bozza e conferma

struct WorkDraft: Identifiable {
    let id = UUID()
    var kind: String
    var fields: WorkFields
    var referenceDate: Date
    let data: Data
    let fileName: String
    let mimeType: String
}

/// La scheda di conferma: i valori letti, correggibili prima di salvarli.
private struct WorkConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: WorkDraft
    let onSave: (WorkFields, Date) -> Void

    init(draft: WorkDraft, onSave: @escaping (WorkFields, Date) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titolo", text: $draft.fields.title)
                    TextField("Datore di lavoro", text: $draft.fields.employer)
                    DatePicker("Data di riferimento", selection: $draft.referenceDate, displayedComponents: .date)
                }
                if draft.kind == WorkRecordKind.leavePlan {
                    Section {
                        ForEach($draft.fields.leavePeriods) { $p in
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("Tipo (ferie, permesso…)", text: $p.label)
                                DatePicker("Dal", selection: day($p.start), displayedComponents: .date)
                                DatePicker("Al", selection: day($p.end), in: (WorkFields.parseDay(p.start) ?? .distantPast)..., displayedComponents: .date)
                            }
                        }
                        .onDelete { draft.fields.leavePeriods.remove(atOffsets: $0) }
                        Button {
                            let today = WorkFields.formatDay(Date())
                            draft.fields.leavePeriods.append(WorkLeavePeriod(start: today, end: today, label: String(localized: "Ferie")))
                        } label: { Label("Aggiungi un periodo", systemImage: "plus.circle") }
                    } header: {
                        Text("Periodi")
                    } footer: {
                        Text("Ogni periodo diventa un evento «giornata intera» nel calendario, visibile a tutta la famiglia. Scorri per togliere un periodo.")
                    }
                } else if draft.kind == WorkRecordKind.payslip {
                    Section("Busta paga") {
                        TextField("Mese di competenza", text: $draft.fields.period)
                        num("Lordo (€)", $draft.fields.gross)
                        num("Netto (€)", $draft.fields.net)
                        num("Imposte trattenute (€)", $draft.fields.taxes)
                        num("Contributi (€)", $draft.fields.contributions)
                        num("TFR (€)", $draft.fields.tfr)
                    }
                    Section("Ferie e permessi") {
                        num("Ferie maturate (giorni)", $draft.fields.vacationAccrued)
                        num("Ferie godute (giorni)", $draft.fields.vacationTaken)
                        num("Ferie residue (giorni)", $draft.fields.vacationRemaining)
                        num("Permessi maturati (ore)", $draft.fields.permitHoursAccrued)
                        num("Permessi residui (ore)", $draft.fields.permitHoursRemaining)
                    }
                } else {
                    Section("Contratto") {
                        TextField("Tipo di contratto", text: $draft.fields.contractType)
                        TextField("Livello / CCNL", text: $draft.fields.level)
                        num("Retribuzione annua lorda (€)", $draft.fields.grossAnnual)
                        num("Ferie annue (giorni)", $draft.fields.vacationDaysPerYear)
                        TextField("Preavviso", text: $draft.fields.noticePeriod)
                        optionalDay("Inizio", $draft.fields.startDate)
                        optionalDay("Scadenza", $draft.fields.endDate)
                    }
                }
                Section("Note") {
                    TextField("Note", text: $draft.fields.notes, axis: .vertical)
                }
                Section {
                    Text("I valori sono quelli letti dall'AI: controllali prima di salvare.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(WorkHomeView.kindTitle(draft.kind))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { onSave(draft.fields, draft.referenceDate) }
                }
            }
        }
    }

    private func day(_ value: Binding<String>) -> Binding<Date> {
        Binding(get: { WorkFields.parseDay(value.wrappedValue) ?? Date() },
                set: { value.wrappedValue = WorkFields.formatDay($0) })
    }

    private func num(_ label: LocalizedStringKey, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
    }

    private func optionalDay(_ label: LocalizedStringKey, _ value: Binding<String?>) -> some View {
        let has = Binding(get: { value.wrappedValue != nil }, set: { on in
            value.wrappedValue = on ? WorkFields.formatDay(Date()) : nil
        })
        let date = Binding(get: { WorkFields.parseDay(value.wrappedValue) ?? Date() },
                           set: { value.wrappedValue = WorkFields.formatDay($0) })
        return VStack(alignment: .leading) {
            Toggle(label, isOn: has)
            if has.wrappedValue {
                DatePicker("", selection: date, displayedComponents: .date).labelsHidden()
            }
        }
    }
}

// MARK: - Dettaglio

private struct WorkRecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let record: KBWorkRecord
    let fields: WorkFields?
    let canEdit: Bool
    let onDelete: () -> Void

    @State private var previewURL: URL?
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                if record.attachmentDocumentId != nil {
                    Section {
                        Button { openFile() } label: { Label("Apri il file originale", systemImage: "doc.richtext") }
                    } footer: {
                        Text("Il documento resta qui, nella scheda Lavoro.")
                    }
                }
                if let f = fields {
                    Section {
                        line("Titolo", f.title)
                        line("Datore di lavoro", f.employer)
                        line("Mese di competenza", f.period)
                    }
                    if !f.leavePeriods.isEmpty {
                        Section("Periodi") {
                            ForEach(f.leavePeriods) { p in
                                HStack {
                                    Text(p.label.isEmpty ? String(localized: "Ferie") : p.label).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(WorkHomeView.period(p)).multilineTextAlignment(.trailing)
                                }
                            }
                        }
                    }
                    Section {
                        line("Lordo", f.gross.map(WorkHomeView.euro))
                        line("Netto", f.net.map(WorkHomeView.euro))
                        line("Imposte trattenute", f.taxes.map(WorkHomeView.euro))
                        line("Contributi", f.contributions.map(WorkHomeView.euro))
                        line("TFR", f.tfr.map(WorkHomeView.euro))
                        line("Ferie maturate", f.vacationAccrued.map(WorkHomeView.days))
                        line("Ferie godute", f.vacationTaken.map(WorkHomeView.days))
                        line("Ferie residue", f.vacationRemaining.map(WorkHomeView.days))
                        line("Permessi maturati", f.permitHoursAccrued.map(WorkHomeView.hours))
                        line("Permessi residui", f.permitHoursRemaining.map(WorkHomeView.hours))
                        line("Tipo di contratto", f.contractType)
                        line("Livello / CCNL", f.level)
                        line("Retribuzione annua lorda", f.grossAnnual.map(WorkHomeView.euro))
                        line("Ferie annue", f.vacationDaysPerYear.map(WorkHomeView.days))
                        line("Inizio", WorkFields.parseDay(f.startDate).map(WorkHomeView.date))
                        line("Scadenza", WorkFields.parseDay(f.endDate).map(WorkHomeView.date))
                        line("Preavviso", f.noticePeriod)
                        line("Note", f.notes)
                    }
                } else {
                    Text("Non riesco ad aprire i valori: la chiave di famiglia non è disponibile su questo dispositivo.")
                        .foregroundStyle(.secondary)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) } }
                if canEdit {
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Elimina", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(WorkHomeView.kindTitle(record.kind))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .confirmationDialog("Eliminare questo documento?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) { onDelete() }
                Button("Annulla", role: .cancel) {}
            }
            .sheet(item: Binding(get: { previewURL.map(WorkPreviewItem.init) }, set: { previewURL = $0?.url })) { item in
                WorkQuickLook(url: item.url)
            }
        }
    }

    @ViewBuilder
    private func line(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(value).multilineTextAlignment(.trailing)
            }
        }
    }

    private func openFile() {
        guard let id = record.attachmentDocumentId else { return }
        WorkAttachmentService.shared.open(documentId: id, modelContext: modelContext,
                                          onURL: { previewURL = $0 }, onError: { errorMessage = $0 })
    }
}

private struct WorkPreviewItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct WorkQuickLook: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
