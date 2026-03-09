//
//  DrugCatalog.swift
//  KidBox
//

import SwiftUI

struct DrugEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let activeIngredient: String
    let category: String
    let form: String?
    let systemImage: String
    let iconColor: Color
    
    init(
        id: String? = nil,
        name: String,
        activeIngredient: String,
        category: String,
        form: String? = nil,
        systemImage: String,
        iconColor: Color
    ) {
        self.id = id ?? "\(name.lowercased())|\(activeIngredient.lowercased())|\(category.lowercased())|\((form ?? "").lowercased())"
        self.name = name
        self.activeIngredient = activeIngredient
        self.category = category
        self.form = form
        self.systemImage = systemImage
        self.iconColor = iconColor
    }
}

enum DrugCatalog {
    
    static let common: [DrugEntry] = [
        DrugEntry(name: "Tachipirina",  activeIngredient: "Paracetamolo", category: "Antipiretico",   systemImage: "thermometer.medium", iconColor: .red),
        DrugEntry(name: "Nurofen",      activeIngredient: "Ibuprofene", category: "Antidolorifico", systemImage: "bandage", iconColor: .orange),
        DrugEntry(name: "Augmentin",    activeIngredient: "Amoxicillina + Ac. clavulanico", category: "Antibiotico", systemImage: "pills", iconColor: Color(red: 0.6, green: 0.45, blue: 0.85)),
        DrugEntry(name: "Zimox",        activeIngredient: "Amoxicillina", category: "Antibiotico", systemImage: "pills", iconColor: Color(red: 0.6, green: 0.45, blue: 0.85)),
        DrugEntry(name: "Amoxil",       activeIngredient: "Amoxicillin", category: "Antibiotico", systemImage: "pills", iconColor: Color(red: 0.6, green: 0.45, blue: 0.85)),
        DrugEntry(name: "Zithromax",    activeIngredient: "Azithromycin", category: "Antibiotico", systemImage: "pills", iconColor: Color(red: 0.6, green: 0.45, blue: 0.85)),
        DrugEntry(name: "Moment",       activeIngredient: "Ibuprofene", category: "Antidolorifico", systemImage: "bandage", iconColor: .orange),
        DrugEntry(name: "Zerinol",      activeIngredient: "Paracetamolo + Clorfenamina", category: "Antipiretico", systemImage: "thermometer.medium", iconColor: .red),
        DrugEntry(name: "Claritromicina", activeIngredient: "Claritromicina", category: "Antibiotico", systemImage: "pills", iconColor: Color(red: 0.6, green: 0.45, blue: 0.85)),
        DrugEntry(name: "Fluimucil",    activeIngredient: "N-acetilcisteina", category: "Mucolitico", systemImage: "lungs", iconColor: .teal),
        DrugEntry(name: "Rinowash",     activeIngredient: "Soluzione salina", category: "Nasale", systemImage: "nose", iconColor: .blue),
        DrugEntry(name: "Aerius",       activeIngredient: "Desloratadina", category: "Antistaminico", systemImage: "allergens", iconColor: .green),
        DrugEntry(name: "Zyrtec",       activeIngredient: "Cetirizina", category: "Antistaminico", systemImage: "allergens", iconColor: .green),
        DrugEntry(name: "Bentelan",     activeIngredient: "Betametasone", category: "Cortisonico", systemImage: "cross.vial", iconColor: .pink),
        DrugEntry(name: "Deltacortene", activeIngredient: "Prednisone", category: "Cortisonico", systemImage: "cross.vial", iconColor: .pink),
    ]
    
    static func search(_ query: String, custom: [DrugEntry] = []) -> [DrugEntry] {
        let all = deduplicated(common + custom)
        
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        
        return all.filter {
            $0.name.lowercased().contains(q) ||
            $0.activeIngredient.lowercased().contains(q) ||
            $0.category.lowercased().contains(q) ||
            ($0.form?.lowercased().contains(q) ?? false)
        }
    }
    
    static func fromCustomDrug(_ item: KBCustomDrug) -> DrugEntry {
        DrugEntry(
            id: item.id,
            name: item.name,
            activeIngredient: item.activeIngredient,
            category: item.category,
            form: item.form,
            systemImage: iconName(for: item.category, form: item.form),
            iconColor: color(for: item.category)
        )
    }
    
    static func color(for category: String) -> Color {
        switch category {
        case "Antipiretico": return .red
        case "Antidolorifico": return .orange
        case "Antibiotico": return Color(red: 0.6, green: 0.45, blue: 0.85)
        case "Mucolitico": return .teal
        case "Nasale": return .blue
        case "Antistaminico": return .green
        case "Cortisonico": return .pink
        default: return KBTheme.tint
        }
    }
    
    static func iconName(for category: String, form: String?) -> String {
        if let form {
            switch form {
            case "Liquido": return "drop.fill"
            case "Compressa": return "pills.fill"
            case "Supposta": return "oval.portrait.fill"
            case "Gocce": return "eyedropper"
            case "Sciroppo": return "spoon"
            case "Polvere": return "aqi.low"
            default: break
            }
        }
        
        switch category {
        case "Antipiretico": return "thermometer.medium"
        case "Antidolorifico": return "bandage"
        case "Antibiotico": return "pills"
        case "Mucolitico": return "lungs"
        case "Nasale": return "nose"
        case "Antistaminico": return "allergens"
        case "Cortisonico": return "cross.vial"
        default: return "cross.vial.fill"
        }
    }
    
    private static func deduplicated(_ entries: [DrugEntry]) -> [DrugEntry] {
        var seen = Set<String>()
        var output: [DrugEntry] = []
        
        for item in entries {
            let key = "\(item.name.lowercased())|\(item.activeIngredient.lowercased())"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(item)
        }
        return output
    }
}
