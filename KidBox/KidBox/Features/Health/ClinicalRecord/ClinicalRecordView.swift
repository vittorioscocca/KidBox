//
//  ClinicalRecordView.swift
//  KidBox
//

import SwiftUI
import SwiftData

struct ClinicalRecordView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let familyId: String
    let childId: String

    @Query private var children: [KBChild]
    @Query private var members: [KBFamilyMember]
    @Query private var allTreatments: [KBTreatment]
    @Query private var allLogs: [KBDoseLog]
    @Query private var allVaccines: [KBVaccine]
    @Query private var allVisits: [KBMedicalVisit]
    @Query private var allExams: [KBMedicalExam]

    @State private var report: ClinicalRecordReport?
    @State private var snapshot: ClinicalRecordSnapshot?
    @State private var exportLines: [String] = []
    @State private var isRefreshing = false
    @State private var refreshStatusMessage = "Integrazione dati e sintesi…"
    @State private var lastAIUsage: ClinicalRecordAIUsageInfo?
    @State private var pendingAIUnits: Int?
    @State private var isExporting = false
    @State private var pdfURL: URL?
    @State private var showPDF = false
    @State private var selectedSection: ClinicalRecordSection?
    @State private var alertMessage = ""
    @State private var showAlert = false

    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId = childId
        let cid = childId
        let fid = familyId
        _children = Query(filter: #Predicate<KBChild> { $0.id == cid })
        _members = Query(filter: #Predicate<KBFamilyMember> { $0.userId == cid })
        _allTreatments = Query(filter: #Predicate<KBTreatment> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false && $0.isActive == true
        })
        _allLogs = Query(filter: #Predicate<KBDoseLog> {
            $0.familyId == fid && $0.childId == cid && $0.taken == true && $0.isDeleted == false
        })
        _allVaccines = Query(filter: #Predicate<KBVaccine> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
        })
        _allVisits = Query(filter: #Predicate<KBMedicalVisit> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
        })
        _allExams = Query(filter: #Predicate<KBMedicalExam> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
        })
    }

    private var child: KBChild? { children.first }
    private var member: KBFamilyMember? { members.first }
    private var subjectName: String { child?.name ?? member?.displayName ?? "Profilo" }
    private var childEmoji: String { child?.avatarEmoji ?? "🧑" }

    private var activeTreatments: [KBTreatment] {
        let today = Calendar.current.startOfDay(for: Date())
        return allTreatments.filter { t in
            if !t.petId.isEmpty { return false }
            if t.isLongTerm { return true }
            if let end = t.endDate, end < today { return false }
            let total = t.totalDoses
            if total > 0 {
                let taken = allLogs.filter { $0.treatmentId == t.id }.count
                if taken >= total { return false }
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isRefreshing && snapshot == nil {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(refreshStatusMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let snap = snapshot, snap.hasAnyData {
                    contentScroll(snap)
                } else {
                    emptyState
                }
            }
            actionBar
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Cartella clinica")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCachedReportIfNeeded()
        }
        .sheet(item: $selectedSection) { section in
            let areaId = section.reportAreaId ?? section.id
            let area = report?.areas.first { $0.id == areaId }
                ?? report?.areas.first { $0.id == section.id }
            ClinicalRecordSectionDetailSheet(section: section, area: area)
        }
        .sheet(isPresented: $showPDF) {
            if let url = pdfURL {
                QuickLookPreview(urls: [url], initialIndex: 0)
            }
        }
        .alert(alertMessage, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private func contentScroll(_ snap: ClinicalRecordSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard(snap)
                if let usage = lastAIUsage {
                    aiUsageBanner(usage)
                } else if let units = pendingAIUnits, units > 1 {
                    pendingUsageBanner(units: units)
                }
                if let global = snap.globalSummary {
                    globalSummaryCard(global)
                }
                overviewStrip(snap)

                VStack(spacing: 12) {
                    ForEach(snap.sections) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            sectionCard(section)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Ogni argomento (cardiologia, urologia, Apple Salute…) apre andamento nel tempo, visite ed esami correlati.")
                    .font(.caption)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 96)
        }
        .overlay { refreshingOverlay }
        .allowsHitTesting(!isRefreshing)
    }

    @ViewBuilder
    private var refreshingOverlay: some View {
        if isRefreshing, snapshot != nil {
            ZStack {
                Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12)
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text(refreshStatusMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    private func globalSummaryCard(_ global: ClinicalRecordGlobalSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sintesi clinica")
                .font(.subheadline.bold())
            HStack(spacing: 12) {
                summaryMetric("\(global.monitoredSpecialtiesCount)", "aree")
                summaryMetric("\(global.attentionCount)", "da monitorare", alert: global.attentionCount > 0)
                summaryMetric("\(global.activeTherapyNames.count)", "terapie")
            }
            if let next = global.nextAppointmentLine {
                Label(next, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }
            ForEach(global.statusLines.prefix(4)) { row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.status.emoji)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.specialtyTitle)
                            .font(.caption.bold())
                        Text(row.headline)
                            .font(.caption)
                            .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    }
                    Spacer(minLength: 0)
                    Text(row.status.badgeLabel)
                        .font(.caption2.bold())
                        .foregroundStyle(statusColor(row.status))
                }
            }
            Text("Non sostituisce il parere medico.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(cardBackground)
    }

    private func summaryMetric(_ value: String, _ label: LocalizedStringKey, alert: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(alert ? .red : Color(red: 0.45, green: 0.55, blue: 0.9))
            Text(label)
                .font(.caption2)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
        .frame(maxWidth: .infinity)
    }

    private func statusColor(_ status: ClinicalOverallStatus) -> Color {
        switch status {
        case .stabile: return Color(red: 0.18, green: 0.62, blue: 0.42)
        case .migliorato: return Color(red: 0.17, green: 0.49, blue: 0.72)
        case .peggiorato, .attenzione: return .red
        case .daMonitorare: return Color(red: 0.83, green: 0.53, blue: 0.04)
        }
    }

    private func aiUsageBanner(_ usage: ClinicalRecordAIUsageInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color(red: 0.45, green: 0.55, blue: 0.9))
                Text(usage.usageSummary)
                    .font(.caption.bold())
            }
            if let notice = usage.largeContextNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.45, green: 0.55, blue: 0.9).opacity(0.12))
        )
    }

    private func pendingUsageBanner(units: Int) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Contesto ampio: verranno conteggiati circa \(units) messaggi AI…")
                .font(.caption)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardBackground)
    }

    private func headerCard(_ snap: ClinicalRecordSnapshot) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.45, green: 0.55, blue: 0.9).opacity(0.18))
                    .frame(width: 56, height: 56)
                Text(childEmoji).font(.title2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(snap.subjectName)
                    .font(.title3.bold())
                if let age = snap.ageDescription {
                    Text(age).font(.subheadline).foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                Text("Generata \(formattedRefresh(snap.refreshedAt)) — tocca Aggiorna per rigenerare")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(Color(red: 0.45, green: 0.55, blue: 0.9))
        }
        .padding(16)
        .background(cardBackground)
    }

    private func overviewStrip(_ snap: ClinicalRecordSnapshot) -> some View {
        let filled = snap.sections.filter { !$0.isEmpty }.count
        return HStack(spacing: 8) {
            overviewPill(value: "\(filled)", label: "argomenti")
            overviewPill(value: "\(activeTreatments.count)", label: "terapie")
            overviewPill(value: "\(allExams.filter { $0.status == .pending || $0.status == .booked }.count)", label: "in attesa")
            overviewPill(value: "\(allExams.count)", label: "esami arch.")
        }
    }

    private func overviewPill(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundStyle(Color(red: 0.45, green: 0.55, blue: 0.9))
            Text(label).font(.caption2).foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(cardBackground)
    }

    private func sectionCard(_ section: ClinicalRecordSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(section.tintColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: section.systemImage)
                        .foregroundStyle(section.tintColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(section.title).font(.subheadline.bold())
                        if let status = section.overallStatus {
                            Text("\(status.emoji) \(status.badgeLabel)")
                                .font(.caption2)
                                .foregroundStyle(statusColor(status))
                        }
                    }
                    Text(section.summary)
                        .font(.caption)
                        .foregroundStyle(section.isEmpty ? .secondary : section.tintColor)
                }
                Spacer(minLength: 0)
                if let badge = section.badgeCount, badge > 0, !section.isEmpty {
                    Text("\(badge)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(section.tintColor))
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            if !section.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(section.highlights, id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(section.tintColor.opacity(0.5))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(line)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackground)
        .opacity(section.isEmpty ? 0.72 : 1)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(KBTheme.cardBackground(colorScheme))
            .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            if isRefreshing {
                ProgressView()
                Text(refreshStatusMessage)
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(KBTheme.tint.opacity(0.5))
                Text("Cartella vuota")
                    .font(.title3.bold())
                Text("Tocca «Aggiorna» per creare o aggiornare la cartella con visite, esami, referti e dati da Apple Salute (passi, battiti, sport).")
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button { Task { await refreshContent() } } label: {
                HStack(spacing: 8) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label(
                        isRefreshing ? "Aggiornamento…" : "Aggiorna",
                        systemImage: isRefreshing ? "hourglass" : "arrow.clockwise"
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing || isExporting)

            Button { Task { await exportPDF() } } label: {
                Group {
                    if isExporting { ProgressView().controlSize(.small) }
                    else { Label("Esporta PDF", systemImage: "doc.richtext") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.45, green: 0.55, blue: 0.9))
            .disabled(!(snapshot?.hasAnyData ?? false) || isRefreshing || isExporting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func formattedRefresh(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = kbDeviceLocale()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }

    @MainActor
    private func loadCachedReportIfNeeded() {
        guard snapshot == nil, var cached = ClinicalRecordStore.loadReport(childId: childId) else { return }
        cached.areas = cached.areas.filter {
            ClinicalRecordSectionPolicy.shouldGenerateStandaloneSection(id: $0.id)
        }
        applyLoadedReport(cached)
    }

    @MainActor
    private func applyLoadedReport(_ cached: ClinicalRecordReport) {
        report = cached
        exportLines = cached.fullDocumentLines
        let health = KBHealthLinkStore.load(childId: childId)
        snapshot = ClinicalRecordSummaryBuilder.build(
            subjectName: subjectName,
            childBirthDate: child?.birthDate,
            profile: nil,
            healthSnapshot: health,
            healthSourceLabel: "Apple Salute",
            treatments: activeTreatments,
            vaccines: allVaccines,
            visits: allVisits,
            exams: allExams,
            report: cached
        )
    }

    @MainActor
    private func refreshContent() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let useAI = AISettings.shared.isEnabled && KBSubscriptionManager.shared.currentPlan.includesAI
        pendingAIUnits = nil
        lastAIUsage = nil

        if useAI,
           let est = await ClinicalRecordOrchestrator.estimateAIMessageUnits(
               modelContext: modelContext,
               familyId: familyId,
               childId: childId,
               subjectName: subjectName,
               childBirthDate: child?.birthDate,
               treatments: activeTreatments,
               vaccines: allVaccines,
               visits: allVisits,
               exams: allExams
           ) {
            pendingAIUnits = est.messageUnits
            refreshStatusMessage = est.isLargeContext
                ? "Sintesi AI in corso (\(est.messageUnits) messaggi, contesto ampio)…"
                : "Sintesi clinica narrativa in corso (\(est.messageUnits) messaggio\(est.messageUnits == 1 ? "" : "i"))…"
        } else {
            refreshStatusMessage = useAI
                ? "Sintesi clinica narrativa in corso…"
                : "Lettura visite, esami e referti…"
        }
        defer {
            isRefreshing = false
            pendingAIUnits = nil
        }

        let bundle: ClinicalRecordOrchestrator.Bundle
        do {
            bundle = try await ClinicalRecordOrchestrator.build(
                modelContext: modelContext,
                familyId: familyId,
                childId: childId,
                subjectName: subjectName,
                childBirthDate: child?.birthDate,
                treatments: activeTreatments,
                vaccines: allVaccines,
                visits: allVisits,
                exams: allExams,
                useAI: useAI
            )
        } catch {
            alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showAlert = true
            return
        }

        report = bundle.report
        snapshot = bundle.snapshot
        exportLines = bundle.exportLines
        lastAIUsage = bundle.aiUsage

        if snapshot?.hasAnyData != true {
            alertMessage = "Nessun dato da integrare. Aggiungi visite, esami o referti in Salute."
            showAlert = true
        }
    }

    @MainActor
    private func exportPDF() async {
        if exportLines.isEmpty { await refreshContent() }
        guard !exportLines.isEmpty else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            pdfURL = try ClinicalRecordGenerator.exportPDF(report: report, lines: exportLines, childId: childId)
            showPDF = true
        } catch {
            alertMessage = "Impossibile esportare il PDF. Riprova."
            showAlert = true
        }
    }
}
