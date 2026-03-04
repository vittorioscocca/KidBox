//
//  DrugCatalog.swift
//  KidBox
//
//  Created by vscocca on 03/03/26.
//



import SwiftUI

struct DrugEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let activeIngredient: String
    let category: String        // usato per il colore icona
    let systemImage: String
    let iconColor: Color
}

enum DrugCatalog {
    
    static let common: [DrugEntry] = [
        DrugEntry(name: "Tachipirina",  activeIngredient: "Paracetamolo",               category: "Antipiretico",   systemImage: "thermometer.medium", iconColor: .red),
        DrugEntry(name: "Nurofen",      activeIngredient: "Ibuprofene",                  category: "Antidolorifico", systemImage: "bandage",            iconColor: .orange),
        DrugEntry(name: "Augmentin",    activeIngredient: "Amoxicillina + Ac. clavulanico", category: "Antibiotico", systemImage: "pills",              iconColor: Color(red: 0.6, green: 0.45, blue: 0.85)),
        DrugEntry(name: "Zimox",        activeIngredient: "Amoxicillina",                category: "Antibiotico",   systemImage: "pills",              iconColor: Color(red: 0.6, green: 0.45, blue: 0.85)),
        DrugEntry(name: "Amoxil",       activeIngredient: "Amoxicillin",                 category: "Antibiotico",   systemImage: "pills",              iconColor: Color(red: 0.6, green: 0.45, blue: 0.85)),
        DrugEntry(name: "Zithromax",    activeIngredient: "Azithromycin",                category: "Antibiotico",   systemImage: "pills",              iconColor: Color(red: 0.6, green: 0.45, blue: 0.85)),
        DrugEntry(name: "Moment",       activeIngredient: "Ibuprofene",                  category: "Antidolorifico", systemImage: "bandage",           iconColor: .orange),
        DrugEntry(name: "Zerinol",      activeIngredient: "Paracetamolo + Clorfenamina", category: "Antipiretico",  systemImage: "thermometer.medium", iconColor: .red),
        DrugEntry(name: "Claritromicina", activeIngredient: "Claritromicina",            category: "Antibiotico",   systemImage: "pills",              iconColor: Color(red: 0.6, green: 0.45, blue: 0.85)),
        DrugEntry(name: "Fluimucil",    activeIngredient: "N-acetilcisteina",            category: "Mucolitico",    systemImage: "lungs",              iconColor: .teal),
        DrugEntry(name: "Rinowash",     activeIngredient: "Soluzione salina",            category: "Nasale",        systemImage: "nose",               iconColor: .blue),
        DrugEntry(name: "Aerius",       activeIngredient: "Desloratadina",               category: "Antistaminico", systemImage: "allergens",          iconColor: .green),
        DrugEntry(name: "Zyrtec",       activeIngredient: "Cetirizina",                  category: "Antistaminico", systemImage: "allergens",          iconColor: .green),
        DrugEntry(name: "Bentelan",     activeIngredient: "Betametasone",                category: "Cortisonico",   systemImage: "cross.vial",         iconColor: .pink),
        DrugEntry(name: "Deltacortene", activeIngredient: "Prednisone",                  category: "Cortisonico",   systemImage: "cross.vial",         iconColor: .pink),
    ]
    
    static func search(_ query: String) -> [DrugEntry] {
        guard !query.isEmpty else { return common }
        let q = query.lowercased()
        return common.filter {
            $0.name.lowercased().contains(q) ||
            $0.activeIngredient.lowercased().contains(q) ||
            $0.category.lowercased().contains(q)
        }
    }
}
