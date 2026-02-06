//
//  FamilySettingsView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import SwiftData

struct FamilySettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    
    @Query private var families: [KBFamily]
    @Query private var members: [KBFamilyMember]
    
    private var family: KBFamily? { families.first }
    private var child: KBChild? { families.first?.children.first }
    private var hasFamily: Bool { family != nil }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                
                if hasFamily {
                    familySummaryCard
                    familyMembersCard
                    actionsWithFamily
                } else {
                    emptyStateCard
                    actionsWithoutFamily
                }
            }
            .padding()
        }
        .navigationTitle("Family")
    }
    
    // MARK: - UI
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Famiglia")
                .font(.title2).bold()
            Text("Qui gestisci la famiglia e inviti l’altro genitore.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
    
    /// Card riepilogo + matita (edit)
    private var familySummaryCard: some View {
        KBSettingsCard(
            title: family?.name ?? "Famiglia",
            subtitle: childSummaryText,
            systemImage: "person.2.fill",
            style: .info,
            action: nil,
            trailingSystemImage: "pencil",
            trailingAction: {
                guard let family, let child else { return }
                coordinator.navigate(to: .editFamily(familyId: family.id, childId: child.id))
            }
        )
    }
    
    /// ✅ Card con lista membri dentro (usa KBSettingsCardWithExtra)
    private var familyMembersCard: some View {
        let familyId = family?.id ?? ""
        
        let list = members
            .filter { $0.familyId == familyId && !$0.isDeleted }
            .sorted { displayLabel(for: $0) < displayLabel(for: $1) }
        
        return KBSettingsCardWithExtra(
            title: "Membri",
            subtitle: membersSubtitle(list: list),
            systemImage: "person.crop.circle.badge.checkmark",
            style: .secondary,
            action: nil
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if list.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                        Text("Nessun membro ancora sincronizzato.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(list) { m in
                        HStack(spacing: 10) {
                            Image(systemName: m.role == "admin" ? "crown.fill" : "person.fill")
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayLabel(for: m))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                
                                Text(roleLabel(m.role))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
    
    private var actionsWithFamily: some View {
        VStack(spacing: 12) {
            KBSettingsCard(
                title: "Invita l’altro genitore o un altro componente della famiglia",
                subtitle: "Genera un codice e condividilo.",
                systemImage: "qrcode",
                style: .primary,
                action: { coordinator.navigate(to: .inviteCode) }
            )
            
            KBSettingsCard(
                title: "Entra con codice",
                subtitle: "Usa un codice se vuoi unirti a un’altra famiglia.",
                systemImage: "key.fill",
                style: .secondary,
                action: { coordinator.navigate(to: .joinFamily) }
            )
        }
    }
    
    private var emptyStateCard: some View {
        KBSettingsCard(
            title: "Nessuna famiglia configurata",
            subtitle: "Puoi crearne una nuova oppure entrare usando un codice invito.",
            systemImage: "exclamationmark.triangle",
            style: .warning,
            action: nil
        )
    }
    
    private var actionsWithoutFamily: some View {
        VStack(spacing: 12) {
            KBSettingsCard(
                title: "Crea una famiglia",
                subtitle: "Sei il primo genitore su questo account.",
                systemImage: "plus.circle.fill",
                style: .primary,
                action: { coordinator.navigate(to: .setupFamily) }
            )
            
            KBSettingsCard(
                title: "Entra con codice",
                subtitle: "Se l’altro genitore ha già creato la famiglia, inserisci il codice.",
                systemImage: "key.fill",
                style: .secondary,
                action: { coordinator.navigate(to: .joinFamily) }
            )
        }
    }
    
    private var childSummaryText: String {
        guard let child else { return "Nessun bimbo/a configurato" }
        if let birth = child.birthDate {
            return "Bimbo/a: \(child.name) • Nato/a: \(birth.formatted(date: .numeric, time: .omitted))"
        }
        return "Bimbo/a: \(child.name)"
    }
    
    // MARK: - Helpers
    
    private func displayLabel(for m: KBFamilyMember) -> String {
        (m.displayName?.trimmedNonEmpty)
        ?? (m.email?.trimmedNonEmpty)
        ?? "Utente"
    }
    
    private func membersSubtitle(list: [KBFamilyMember]) -> String {
        if list.isEmpty { return "Chi può accedere ai dati della famiglia." }
        if list.count == 1 { return "1 membro collegato." }
        return "\(list.count) membri collegati."
    }
    
    private func roleLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "admin", "owner": return "Admin"
        default: return "Membro"
        }
    }
}

// MARK: - Small helpers (TIENI SOLO QUESTA, NON DUPLICARLA ALTROVE)

private extension String {
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
