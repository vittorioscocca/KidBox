//
//  PediatricVisitsView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct PediatricVisitsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @Query private var visits: [KBMedicalVisit]
    @Query private var children: [KBChild]
    @Query private var members: [KBFamilyMember]
    
    let familyId: String
    let childId: String
    
    @State private var showAddSheet = false
    @State private var selectedPeriod: PeriodFilter = .thirtyDays
    @State private var searchText = ""
    @State private var showAIConsent = false
    @State private var showAIChat = false
    @State private var aiSelectedVisits: [KBMedicalVisit] = []
    @State private var aiSelectedPeriod: PeriodFilter = .thirtyDays
    @State private var aiSubjectName: String = ""
    @State private var aiScopeId: String = ""
    
    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)
    
    private var childName: String {
        switch selectedPerson {
        case .child(let child):
            return child.name
        case .member(let member):
            return member.displayName ?? "membro famiglia"
        case nil:
            return "bambino"
        }
    }
    
    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId  = childId
        
        let fid = familyId
        let cid = childId
        
        _visits = Query(
            filter: #Predicate<KBMedicalVisit> {
                $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
            },
            sort: [SortDescriptor(\KBMedicalVisit.date, order: .reverse)]
        )
        
        _children = Query(
            filter: #Predicate<KBChild> { $0.id == cid }
        )
        
        _members = Query(
            filter: #Predicate<KBFamilyMember> {
                $0.familyId == fid && $0.userId == cid
            }
        )
    }
    
    private var filteredVisits: [KBMedicalVisit] {
        let periodFiltered: [KBMedicalVisit]
        
        if let cutoff = selectedPeriod.cutoffDate {
            periodFiltered = visits.filter { $0.date >= cutoff }
        } else {
            periodFiltered = visits
        }
        
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return periodFiltered }
        
        return periodFiltered.filter { visit in
            let reason = visit.reason
            let doctor = visit.doctorName ?? ""
            let diagnosis = visit.diagnosis ?? ""
            
            return reason.localizedCaseInsensitiveContains(query)
            || doctor.localizedCaseInsensitiveContains(query)
            || diagnosis.localizedCaseInsensitiveContains(query)
        }
    }
    
    private var selectedPerson: PediatricPerson? {
        if let child = children.first {
            return .child(child)
        }
        
        if let member = members.first {
            return .member(member)
        }
        
        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Filtra per periodo")
                                .font(.caption)
                                .foregroundStyle(KBTheme.secondaryText(colorScheme))
                            
                            Text("\(filteredVisits.count) visit\(filteredVisits.count == 1 ? "a" : "e")")
                                .font(.subheadline.bold())
                                .foregroundStyle(KBTheme.primaryText(colorScheme))
                        }
                        
                        Spacer()
                        
                        Menu {
                            ForEach(PeriodFilter.allCases) { p in
                                Button {
                                    selectedPeriod = p
                                } label: {
                                    HStack {
                                        Text(p.label)
                                        if selectedPeriod == p {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                Text(selectedPeriod.label)
                                Image(systemName: "chevron.down")
                            }
                            .font(.subheadline)
                            .foregroundStyle(tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(tint.opacity(0.1))
                            )
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                
                if filteredVisits.isEmpty {
                    Section {
                        emptyState
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Section {
                        ForEach(filteredVisits) { visitRow($0) }
                            .onDelete { deleteItems(offsets: $0) }
                    } header: {
                        HStack {
                            Label("Visite recenti", systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(tint)
                            
                            Spacer()
                            
                            Text("\(filteredVisits.count)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(tint))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(KBTheme.background(colorScheme))
            
            Button {
                showAddSheet = true
            } label: {
                Label("Aggiungi nuova visita", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(tint))
                    .foregroundStyle(.white)
                    .font(.headline)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(KBTheme.background(colorScheme))
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Visita Medica")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Cerca visita"
        )
        .sheet(isPresented: $showAIConsent) {
            AIConsentSheet {
                KBLog.ai.kbInfo("AI consent accepted -> opening AI chat")
                showAIChat = true
            }
        }
        .sheet(isPresented: $showAIChat) {
            KBLog.ai.kbInfo("Presenting PediatricVisitsAIChatView subject=\(aiSubjectName)")
            KBLog.ai.kbInfo("Presenting PediatricVisitsAIChatView visits.count=\(aiSelectedVisits.count)")
            KBLog.ai.kbDebug("Presenting PediatricVisitsAIChatView visitIds=\(aiSelectedVisits.map(\.id).joined(separator: ","))")
            KBLog.ai.kbInfo("Presenting PediatricVisitsAIChatView scopeId=\(aiScopeId)")
            
            return PediatricVisitsAIChatView(
                subjectName: aiSubjectName,
                visibleVisits: aiSelectedVisits,
                selectedPeriod: aiSelectedPeriod,
                scopeId: aiScopeId
            )
        }
        .onChange(of: showAIChat) { _, newValue in
            KBLog.ai.kbInfo("showAIChat changed -> \(newValue)")
        }
        .onChange(of: filteredVisits.count) { _, newValue in
            KBLog.ai.kbInfo("filteredVisits.count changed -> \(newValue)")
        }
        .overlay(alignment: .bottomTrailing) {
            if let selectedPerson, !filteredVisits.isEmpty {
                PediatricVisitsAskAIButton(
                    person: selectedPerson,
                    visits: filteredVisits,
                    selectedPeriod: selectedPeriod
                ) { person, visits, period in
                    KBLog.ai.kbInfo("AskAI button tapped period=\(period.rawValue) passedVisits.count=\(visits.count)")
                    KBLog.ai.kbDebug("AskAI button tapped passedVisitIds=\(visits.map(\.id).joined(separator: ","))")
                    handleAskAI(person: person, visits: visits, period: period)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 96)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button { } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            PediatricVisitEditView(
                familyId: familyId,
                childId: childId,
                childName: childName
            )
        }
    }
    
    private func visitRow(_ v: KBMedicalVisit) -> some View {
        Button {
            coordinator.navigate(to: .pediatricVisitDetail(
                familyId: familyId,
                childId: childId,
                visitId: v.id
            ))
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "stethoscope")
                        .foregroundStyle(tint)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(v.reason.isEmpty ? "Visita" : v.reason)
                        .font(.subheadline.bold())
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                        .lineLimit(1)
                    
                    if let doctor = v.doctorName, !doctor.isEmpty {
                        Text(doctor)
                            .font(.caption)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                    }
                    
                    Text(v.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                
                Spacer()
                
                if v.diagnosis != nil {
                    Image(systemName: "doc.text.fill")
                        .font(.caption)
                        .foregroundStyle(tint.opacity(0.6))
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "stethoscope")
                    .font(.system(size: 32))
                    .foregroundStyle(tint)
            }
            
            Text("Nessuna visita registrata")
                .font(.title3.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            
            Text("Aggiungi la prima visita per \(childName)")
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private func deleteItems(offsets: IndexSet) {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        for i in offsets {
            let v = filteredVisits[i]
            v.isDeleted = true
            v.updatedBy = uid
            v.updatedAt = now
            v.syncState = .pendingUpsert
            v.lastSyncError = nil
            
            try? modelContext.save()
            
            SyncCenter.shared.enqueueVisitDelete(
                visitId: v.id,
                familyId: familyId,
                modelContext: modelContext
            )
        }
        
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    private func handleAskAI(
        person: PediatricPerson,
        visits _: [KBMedicalVisit],
        period: PeriodFilter
    ) {
        KBLog.ai.kbInfo("handleAskAI START period=\(period.rawValue)")
        KBLog.ai.kbInfo("handleAskAI current filteredVisits.count=\(filteredVisits.count)")
        KBLog.ai.kbDebug("handleAskAI current filteredVisitIds=\(filteredVisits.map(\.id).joined(separator: ","))")
        
        let currentVisits = filteredVisits
        
        guard !currentVisits.isEmpty else {
            KBLog.ai.kbError("handleAskAI aborted: filteredVisits is empty")
            return
        }
        
        switch person {
        case .child(let child):
            aiSubjectName = child.name
            aiScopeId = "visits-child-\(child.id)-\(period.rawValue)"
            KBLog.ai.kbInfo("handleAskAI subject resolved as child")
            
        case .member(let member):
            aiSubjectName = member.displayName ?? "Membro della famiglia"
            aiScopeId = "visits-member-\(member.id)-\(period.rawValue)"
            KBLog.ai.kbInfo("handleAskAI subject resolved as family member")
        }
        
        aiSelectedVisits = currentVisits
        aiSelectedPeriod = period
        
        KBLog.ai.kbInfo("handleAskAI aiSelectedVisits.count=\(aiSelectedVisits.count)")
        KBLog.ai.kbDebug("handleAskAI aiSelectedVisitIds=\(aiSelectedVisits.map(\.id).joined(separator: ","))")
        KBLog.ai.kbInfo("handleAskAI aiScopeId=\(aiScopeId)")
        
        if !AISettings.shared.consentGiven {
            KBLog.ai.kbInfo("handleAskAI consent missing -> opening consent sheet")
            showAIConsent = true
            return
        }
        
        KBLog.ai.kbInfo("handleAskAI opening AI chat sheet")
        showAIChat = true
    }
}
