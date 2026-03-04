//
//  PediatricChildSelectorView.swift
//  KidBox
//
//  Created by vscocca on 03/03/26.
//

//
//  PediatricChildSelectorView.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//
//  Mostrata quando si tappa la card "Pediatria" dalla Home.
//  Elenca i figli della famiglia, per ognuno mostra nome, età,
//  peso e altezza (con possibilità di aggiornare inline se mancanti),
//  poi naviga alla PediatricHomeView del figlio selezionato.

import SwiftUI
import SwiftData
import FirebaseAuth

struct PediatricChildSelectorView: View {
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    
    let familyId: String
    
    @Query private var children: [KBChild]
    
    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _children = Query(
            filter: #Predicate<KBChild> { $0.familyId == fid },
            sort: [SortDescriptor(\KBChild.name)]
        )
    }
    
    var body: some View {
        Group {
            if children.isEmpty {
                emptyState
            } else if children.count == 1, let child = children.first {
                // Un solo figlio: vai direttamente
                Color.clear
                    .onAppear {
                        coordinator.navigate(to: .pediatricHome(familyId: familyId, childId: child.id))
                    }
            } else {
                childList
            }
        }
        .navigationTitle("Pediatria")
        .navigationBarTitleDisplayMode(.large)
    }
    
    // MARK: - Child list
    
    private var childList: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(children) { child in
                    ChildHealthCard(child: child, familyId: familyId) {
                        coordinator.navigate(to: .pediatricHome(familyId: familyId, childId: child.id))
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Empty state
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Nessun figlio registrato")
                .font(.title3.bold())
            Text("Aggiungi un figlio nelle impostazioni famiglia per iniziare.")
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

// MARK: - ChildHealthCard

private struct ChildHealthCard: View {
    
    @Bindable var child: KBChild
    @Environment(\.modelContext) private var modelContext
    
    let familyId: String
    let onTap: () -> Void
    
    // Editing inline peso/altezza
    @State private var showWeightSheet = false
    @State private var showHeightSheet = false
    @State private var weightInput = ""
    @State private var heightInput = ""
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Text(child.avatarEmoji)
                        .font(.title)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(child.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(child.ageDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    // Peso + Altezza
                    HStack(spacing: 12) {
                        healthChip(
                            icon: "scalemass",
                            value: child.weightKg.map { String(format: "%.1f kg", $0) },
                            placeholder: "Peso?",
                            color: .blue
                        ) { showWeightSheet = true }
                        
                        healthChip(
                            icon: "ruler",
                            value: child.heightCm.map { String(format: "%.0f cm", $0) },
                            placeholder: "Altezza?",
                            color: .green
                        ) { showHeightSheet = true }
                    }
                }
                
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        // ── Sheet peso ──
        .sheet(isPresented: $showWeightSheet) {
            MeasurementInputSheet(
                title: "Peso",
                unit: "kg",
                placeholder: "es. 12.5",
                current: child.weightKg.map { String(format: "%.1f", $0) }
            ) { value in
                if let d = Double(value.replacingOccurrences(of: ",", with: ".")) {
                    child.weightKg = d
                    child.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        }
        // ── Sheet altezza ──
        .sheet(isPresented: $showHeightSheet) {
            MeasurementInputSheet(
                title: "Altezza",
                unit: "cm",
                placeholder: "es. 90",
                current: child.heightCm.map { String(format: "%.0f", $0) }
            ) { value in
                if let d = Double(value.replacingOccurrences(of: ",", with: ".")) {
                    child.heightCm = d
                    child.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        }
    }
    
    @ViewBuilder
    private func healthChip(
        icon: String,
        value: String?,
        placeholder: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(value ?? placeholder)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(value != nil ? color.opacity(0.12) : Color.secondary.opacity(0.1))
            )
            .foregroundStyle(value != nil ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MeasurementInputSheet

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
                    TextField(placeholder, text: $input)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") {
                        onSave(input)
                        dismiss()
                    }
                    .bold()
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { input = current ?? "" }
        }
        .presentationDetents([.height(220)])
    }
}
