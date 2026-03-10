//
//  PediatricHomeView.swift
//  KidBox
//
//  Restyled: dynamic light/dark theme matching LoginView.
//  Added: floating HealthAskAIButton (full-health AI overview).
//

import SwiftUI
import SwiftData

struct PediatricHomeView: View {
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    let familyId: String
    let childId: String
    
    @Query private var children: [KBChild]
    @Query private var members:  [KBFamilyMember]
    
    @Query private var allTreatments: [KBTreatment]
    @Query private var allLogs:       [KBDoseLog]
    @Query private var allVaccines:   [KBVaccine]
    @Query private var allVisits:     [KBMedicalVisit]
    @Query private var allExams:      [KBMedicalExam]
    
    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId  = childId
        
        let cid = childId
        let fid = familyId
        
        _children = Query(filter: #Predicate<KBChild> { $0.id == cid })
        _members  = Query(filter: #Predicate<KBFamilyMember> { $0.userId == cid })
        
        _allTreatments = Query(filter: #Predicate<KBTreatment> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false && $0.isActive == true
        })
        _allLogs = Query(filter: #Predicate<KBDoseLog> {
            $0.familyId == fid && $0.childId == cid && $0.taken == true
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
    
    // childId is used as the universal subjectId — valid for both KBChild and KBFamilyMember
    private var child: KBChild?         { children.first }
    private var member: KBFamilyMember? { members.first }
    private var subjectName: String     { child?.name ?? member?.displayName ?? "Profilo" }
    private var childEmoji: String      { child?.avatarEmoji ?? "🧑" }
    
    /// Cure davvero in corso (esclude terminate per dosi/data)
    private var activeTreatments: [KBTreatment] {
        let today = Calendar.current.startOfDay(for: Date())
        return allTreatments.filter { t in
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
    
    private var activeTreatmentsCount: Int { activeTreatments.count }
    
    /// Esami in attesa o prenotati (non ancora eseguiti)
    private var pendingExamsCount: Int {
        allExams.filter { $0.status == .pending || $0.status == .booked }.count
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerView
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    moduleCard(
                        title: "Cure",
                        subtitle: activeTreatmentsCount > 0
                        ? "\(activeTreatmentsCount) attiv\(activeTreatmentsCount == 1 ? "a" : "e")"
                        : "Farmaci attivi",
                        systemImage: "cross.case.fill",
                        tint: Color(red: 0.6, green: 0.45, blue: 0.85),
                        badge: activeTreatmentsCount > 0 ? activeTreatmentsCount : nil
                    ) {
                        coordinator.navigate(to: .pediatricTreatments(familyId: familyId, childId: childId))
                    }
                    moduleCard(
                        title: "Vaccini",
                        subtitle: "\(allVaccines.count) registrati",
                        systemImage: "syringe.fill",
                        tint: Color(red: 0.95, green: 0.55, blue: 0.45)
                    ) {
                        coordinator.navigate(to: .pediatricVaccines(familyId: familyId, childId: childId))
                    }
                    moduleCard(
                        title: "Visite",
                        subtitle: "\(allVisits.count) registrate",
                        systemImage: "stethoscope",
                        tint: Color(red: 0.35, green: 0.6, blue: 0.85)
                    ) {
                        coordinator.navigate(to: .pediatricVisits(familyId: familyId, childId: childId))
                    }
                    moduleCard(
                        title: "Analisi & Esami",
                        subtitle: pendingExamsCount > 0
                        ? "\(pendingExamsCount) in attesa"
                        : "\(allExams.count) registrati",
                        systemImage: "testtube.2",
                        tint: Color(red: 0.25, green: 0.65, blue: 0.75),
                        badge: pendingExamsCount > 0 ? pendingExamsCount : nil
                    ) {
                        coordinator.navigate(to: .pediatricExams(familyId: familyId, childId: childId))
                    }
                    moduleCard(
                        title: "Scheda Medica",
                        subtitle: "Allergie, pediatra",
                        systemImage: "doc.text.fill",
                        tint: Color(red: 0.4, green: 0.75, blue: 0.65)
                    ) {
                        coordinator.navigate(to: .pediatricMedicalRecord(familyId: familyId, childId: childId))
                    }
                }
                .padding(.horizontal)
                
                // Spacer so the last card is never hidden behind the floating button
                Spacer(minLength: 80)
            }
            .padding(.vertical)
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Salute")
        .navigationBarTitleDisplayMode(.large)
        // ── Floating AI button — works for both KBChild and KBFamilyMember ──
        .overlay(alignment: .bottomTrailing) {
            HealthAskAIButton(
                subjectName: subjectName,
                subjectId:   childId,
                exams:       allExams,
                visits:      allVisits,
                treatments:  activeTreatments,
                vaccines:    allVaccines
            )
            .padding(.trailing, 20)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(KBTheme.tint.opacity(0.15))
                    .frame(width: 52, height: 52)
                Text(childEmoji).font(.title2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(subjectName)
                    .font(.title3.bold())
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                Text("Diario di salute")
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }
            Spacer()
        }
        .padding(.horizontal)
    }
    
    // MARK: - Module card
    
    @ViewBuilder
    private func moduleCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        badge: Int? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle().fill(tint.opacity(0.15)).frame(width: 60, height: 60)
                        Image(systemName: systemImage).font(.title2).foregroundStyle(tint)
                    }
                    if let badge, badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(tint))
                            .offset(x: 4, y: -4)
                    }
                }
                VStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(KBTheme.cardBackground(colorScheme))
                    .shadow(color: KBTheme.shadow(colorScheme), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
