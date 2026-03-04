//
//  DrugSelectorView.swift
//  KidBox
//
//  Restyled: dynamic light/dark theme matching LoginView.
//

import SwiftUI

struct SelectedDrug {
    var name: String
    var activeIngredient: String
}

// MARK: - Step 0 view

struct DrugSelectorStep: View {
    
    @Binding var drugName: String
    @Binding var activeIngredient: String
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var searchText      = ""
    @State private var showCustomSheet = false
    
    private let tint = KBTheme.tint
    private var results: [DrugEntry] { DrugCatalog.search(searchText) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Seleziona farmaco")
                .font(.title3.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Cerca Farmaco", text: $searchText)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(KBTheme.inputBackground(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if !results.isEmpty {
                Text("Farmaci Comuni")
                    .font(.headline)
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                    .padding(.top, 4)
            }
            
            VStack(spacing: 0) {
                ForEach(results) { drug in
                    drugRow(drug)
                    if drug != results.last { Divider().padding(.leading, 68) }
                }
                
                // Aggiungi personalizzato
                Button { showCustomSheet = true } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(tint.opacity(0.12)).frame(width: 44, height: 44)
                            Image(systemName: "plus").foregroundStyle(tint)
                        }
                        Text("Aggiungi farmaco personalizzato")
                            .foregroundStyle(tint).font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(KBTheme.cardBackground(colorScheme))
                    .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
            )
        }
        .sheet(isPresented: $showCustomSheet) {
            CustomDrugSheet(drugName: $drugName, activeIngredient: $activeIngredient)
        }
    }
    
    private func drugRow(_ drug: DrugEntry) -> some View {
        Button {
            drugName         = drug.name
            activeIngredient = drug.activeIngredient
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(drug.iconColor.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: drug.systemImage).foregroundStyle(drug.iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(drug.name).font(.subheadline.bold())
                    Text(drug.activeIngredient).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if drugName == drug.name {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(tint)
                } else {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheet farmaco personalizzato

struct CustomDrugSheet: View {
    
    @Binding var drugName: String
    @Binding var activeIngredient: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var localName        = ""
    @State private var localIngredient  = ""
    @State private var selectedCategory = ""
    @State private var selectedForm     = "Liquido"
    
    private let tint       = KBTheme.tint
    private let categories = ["Antipiretico", "Antidolorifico", "Antibiotico",
                              "Antistaminico", "Mucolitico", "Cortisonico",
                              "Nasale", "Altro"]
    private let forms      = ["Liquido", "Compressa", "Supposta", "Gocce", "Sciroppo", "Polvere"]
    private let formIcons: [String: String] = [
        "Liquido":   "drop.fill",
        "Compressa": "pills.fill",
        "Supposta":  "oval.portrait.fill",
        "Gocce":     "eyedropper",
        "Sciroppo":  "spoon",
        "Polvere":   "aqi.low"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Icon header
                    ZStack {
                        Circle().fill(tint.opacity(0.1)).frame(width: 72, height: 72)
                        Image(systemName: "cross.vial.fill").font(.title).foregroundStyle(tint)
                    }
                    .padding(.top, 8)
                    
                    Text("Aggiungi farmaco personalizzato")
                        .font(.title3.bold())
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                        .multilineTextAlignment(.center)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        
                        fieldSection(label: "Nome") {
                            TextField("", text: $localName)
                                .padding(12)
                                .background(KBTheme.inputBackground(colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        
                        fieldSection(label: "Principio attivo") {
                            TextField("", text: $localIngredient)
                                .padding(12)
                                .background(KBTheme.inputBackground(colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        
                        fieldSection(label: "Categoria") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(categories, id: \.self) { cat in categoryChip(cat) }
                                }
                            }
                        }
                        
                        fieldSection(label: "Forma (es: Sciroppo, Compresse)") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(forms, id: \.self) { form in formChip(form) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Button {
                        drugName         = localName
                        activeIngredient = localIngredient
                        dismiss()
                    } label: {
                        Label("Salva", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 14).fill(canSave ? tint : Color(.systemGray4)))
                            .foregroundStyle(.white)
                            .font(.headline)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle("Aggiungi farmaco personalizzato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
            }
        }
    }
    
    private var canSave: Bool {
        !localName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    @ViewBuilder
    private func fieldSection<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            content()
        }
    }
    
    private func categoryChip(_ cat: String) -> some View {
        let isSelected = selectedCategory == cat
        return Button { selectedCategory = isSelected ? "" : cat } label: {
            Text(cat)
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(isSelected ? tint.opacity(0.15) : KBTheme.inputBackground(colorScheme)))
                .foregroundStyle(isSelected ? tint : .primary)
                .overlay(Capsule().stroke(isSelected ? tint : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    
    private func formChip(_ form: String) -> some View {
        let isSelected = selectedForm == form
        let icon = formIcons[form] ?? "pills"
        return Button { selectedForm = form } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(form).font(.caption)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(isSelected ? tint.opacity(0.15) : KBTheme.inputBackground(colorScheme)))
            .foregroundStyle(isSelected ? tint : .primary)
            .overlay(Capsule().stroke(isSelected ? tint : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
