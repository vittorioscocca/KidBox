//
//  PediatricHomeView.swift
//  KidBox
//
//  Restyled: dynamic light/dark theme matching LoginView.
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
    @Query private var allVaccines:   [KBVaccine]
    @Query private var allVisits:     [KBMedicalVisit]
    
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
        _allVaccines = Query(filter: #Predicate<KBVaccine> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
        })
        _allVisits = Query(filter: #Predicate<KBMedicalVisit> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
        })
    }
    
    private var child: KBChild?             { children.first }
    private var member: KBFamilyMember?     { members.first }
    private var childName: String           { child?.name ?? member?.displayName ?? "Profilo" }
    private var childEmoji: String          { child?.avatarEmoji ?? "🧑" }
    private var activeTreatmentsCount: Int  { allTreatments.count }
    
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
                        title: "Scheda Medica",
                        subtitle: "Allergie, pediatra",
                        systemImage: "doc.text.fill",
                        tint: Color(red: 0.4, green: 0.75, blue: 0.65)
                    ) {
                        coordinator.navigate(to: .pediatricMedicalRecord(familyId: familyId, childId: childId))
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Salute")
        .navigationBarTitleDisplayMode(.large)
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
                Text(childName)
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
