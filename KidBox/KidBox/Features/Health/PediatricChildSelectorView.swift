//
//  PediatricChildSelectorView.swift
//  KidBox
//
//  Selector per accedere alla sezione Pediatria.
//  Mostra figli (KBChild) + membri adulti (KBFamilyMember) come piani separati.
//  Logica:
//   - 0 persone totali  → empty state
//   - 1 persona totale  → naviga direttamente
//   - 2+ persone        → mostra lista con sezioni Figli / Adulti

import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - Persona unificata

/// Astrazione che rappresenta sia un KBChild che un KBFamilyMember
enum PediatricPerson: Identifiable {
    case child(KBChild)
    case member(KBFamilyMember)
    
    var id: String {
        switch self {
        case .child(let c):   return "child-\(c.id)"
        case .member(let m):  return "member-\(m.userId)"
        }
    }
    
    var personId: String {
        switch self {
        case .child(let c):   return c.id
        case .member(let m):  return m.userId
        }
    }
    
    var name: String {
        switch self {
        case .child(let c):   return c.name
        case .member(let m):  return m.displayName ?? ""
        }
    }
    
    var emoji: String {
        switch self {
        case .child(let c):   return c.avatarEmoji
        case .member:         return "🧑"
        }
    }
    
    var subtitle: String {
        switch self {
        case .child(let c):   return c.ageDescription
        case .member:         return "Membro famiglia"
        }
    }
    
    var isChild: Bool {
        if case .child = self { return true }
        return false
    }
}

// MARK: - View principale

struct PediatricChildSelectorView: View {
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    
    let familyId: String
    
    @Query private var children: [KBChild]
    @Query private var members:  [KBFamilyMember]
    
    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _children = Query(
            filter: #Predicate<KBChild> { $0.familyId == fid },
            sort: [SortDescriptor(\KBChild.name)]
        )
        _members = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid },
            sort: [SortDescriptor(\KBFamilyMember.displayName)]
        )
    }
    
    // Tutte le persone: prima i figli, poi i membri adulti
    private var allPersons: [PediatricPerson] {
        children.map { .child($0) } + members.map { .member($0) }
    }
    
    private var childPersons:  [PediatricPerson] { allPersons.filter {  $0.isChild } }
    private var adultPersons:  [PediatricPerson] { allPersons.filter { !$0.isChild } }
    
    var body: some View {
        Group {
            if allPersons.isEmpty {
                emptyState
            } else if allPersons.count == 1, let person = allPersons.first {
                // Un solo profilo: salta direttamente
                Color.clear.onAppear {
                    navigate(to: person)
                }
            } else {
                personList
            }
        }
        .navigationTitle("Salute")
        .navigationBarTitleDisplayMode(.large)
    }
    
    // MARK: - Lista
    
    private var personList: some View {
        ScrollView {
            VStack(spacing: 0) {
                
                if !childPersons.isEmpty {
                    sectionHeader("Bambini", icon: "figure.child")
                    VStack(spacing: 12) {
                        ForEach(childPersons) { person in
                            if case .child(let child) = person {
                                ChildHealthCard(child: child, familyId: familyId) {
                                    navigate(to: person)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                
                if !adultPersons.isEmpty {
                    sectionHeader("Adulti", icon: "person.2")
                    VStack(spacing: 12) {
                        ForEach(adultPersons) { person in
                            if case .member(let member) = person {
                                MemberHealthCard(member: member) {
                                    navigate(to: person)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .padding(.top, 8)
        }
    }
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - Navigation
    
    private func navigate(to person: PediatricPerson) {
        coordinator.navigate(to: .pediatricHome(familyId: familyId, childId: person.personId))
    }
    
    // MARK: - Empty state
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Nessun profilo disponibile")
                .font(.title3.bold())
            Text("Aggiungi figli o verifica i membri nelle impostazioni famiglia.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                coordinator.navigate(to: .familySettings)
            } label: {
                Label("Impostazioni famiglia", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - ChildHealthCard (invariata)

private struct ChildHealthCard: View {
    
    @Bindable var child: KBChild
    @Environment(\.modelContext) private var modelContext
    
    let familyId: String
    let onTap: () -> Void
    
    @State private var showWeightSheet = false
    @State private var showHeightSheet = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Text(child.avatarEmoji).font(.title)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(child.name).font(.headline).foregroundStyle(.primary)
                    Text(child.ageDescription).font(.subheadline).foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        healthChip(icon: "scalemass",
                                   value: child.weightKg.map { String(format: "%.1f kg", $0) },
                                   placeholder: "Peso?", color: .blue) { showWeightSheet = true }
                        healthChip(icon: "ruler",
                                   value: child.heightCm.map { String(format: "%.0f cm", $0) },
                                   placeholder: "Altezza?", color: .green) { showHeightSheet = true }
                    }
                }
                
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showWeightSheet) {
            MeasurementInputSheet(title: "Peso", unit: "kg", placeholder: "es. 12.5",
                                  current: child.weightKg.map { String(format: "%.1f", $0) }) { value in
                if let d = Double(value.replacingOccurrences(of: ",", with: ".")) {
                    child.weightKg = d; child.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        }
        .sheet(isPresented: $showHeightSheet) {
            MeasurementInputSheet(title: "Altezza", unit: "cm", placeholder: "es. 90",
                                  current: child.heightCm.map { String(format: "%.0f", $0) }) { value in
                if let d = Double(value.replacingOccurrences(of: ",", with: ".")) {
                    child.heightCm = d; child.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        }
    }
    
    @ViewBuilder
    private func healthChip(icon: String, value: String?, placeholder: String,
                            color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(value ?? placeholder).font(.caption)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(value != nil ? color.opacity(0.12) : Color.secondary.opacity(0.1)))
            .foregroundStyle(value != nil ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MemberHealthCard

private struct MemberHealthCard: View {
    
    let member: KBFamilyMember
    let onTap: () -> Void
    
    // Colori per ruolo
    private var roleColor: Color {
        switch member.role {
        case "owner":  return .purple
        case "admin":  return .blue
        default:       return .teal
        }
    }
    
    private var roleLabel: String {
        switch member.role {
        case "owner": return "Proprietario"
        case "admin": return "Amministratore"
        default:      return "Membro"
        }
    }
    
    // Iniziali per avatar
    private var initials: String {
        let parts = (member.displayName ?? "").split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last  = parts.dropFirst().first?.prefix(1) ?? ""
        return (first + last).uppercased()
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                
                // Avatar con iniziali
                ZStack {
                    Circle()
                        .fill(roleColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Text(initials.isEmpty ? "?" : initials)
                        .font(.title3.bold())
                        .foregroundStyle(roleColor)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(member.displayName ?? "").font(.headline).foregroundStyle(.primary)
                    
                    // Ruolo chip
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill").font(.caption2)
                        Text(roleLabel).font(.caption)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(roleColor.opacity(0.1)))
                    .foregroundStyle(roleColor)
                }
                
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MeasurementInputSheet (invariata)

private struct MeasurementInputSheet: View {
    
    let title: String
    let unit: String
    let placeholder: String
    let current: String?
    let onSave: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("\(title) (\(unit))") {
                    TextField(placeholder, text: $input).keyboardType(.decimalPad)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") { onSave(input); dismiss() }
                        .bold()
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { input = current ?? "" }
        }
        .presentationDetents([.height(220)])
    }
}
