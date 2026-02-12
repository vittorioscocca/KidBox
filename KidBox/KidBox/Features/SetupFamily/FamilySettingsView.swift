//
//  FamilySettingsView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//


import SwiftUI
import SwiftData
import FirebaseAuth

struct FamilySettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    @Query private var families: [KBFamily]
    @Query private var members: [KBFamilyMember]
    
    @State private var showLeaveFamilyConfirm = false
    @State private var leaveError: String?
    
    private var family: KBFamily? { families.first }
    @Query(sort: \KBChild.birthDate, order: .forward)
    private var allChildren: [KBChild]
    
    private var children: [KBChild] {
        guard let family else { return [] }
        
        return allChildren
            .filter { $0.familyId == family.id }   // ✅ SOLO familyId
            .sorted { ($0.birthDate ?? .distantPast) < ($1.birthDate ?? .distantPast) }
    }
    
    // MARK: - Snapshot rows (anti SwiftData crash)
    
    struct ChildRow: Identifiable {
        let id: String
        let name: String
        let birthDate: Date?
    }
    
    private var childRows: [ChildRow] {
        children.map {
            ChildRow(
                id: $0.id,
                name: $0.name,
                birthDate: $0.birthDate
            )
        }
    }
    
    private var hasFamily: Bool { family != nil }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                
                if hasFamily {
                    familySummaryCard
                    familyChildrenCard
                    familyMembersCard
                    actionsWithFamily
                    dangerZone
                } else {
                    emptyStateCard
                    actionsWithoutFamily
                }
            }
            .padding()
        }
        .navigationTitle("Family")
        .onAppear {
            if let fid = family?.id {
                SyncCenter.shared.startMembersRealtime(familyId: fid, modelContext: modelContext)
                SyncCenter.shared.startChildrenRealtime(familyId: fid, modelContext: modelContext)
            }
        }
        .onDisappear {
            SyncCenter.shared.stopMembersRealtime()
            SyncCenter.shared.stopChildrenRealtime()
        }
        .alert(
            "Uscire dalla famiglia?",
            isPresented: $showLeaveFamilyConfirm
        ) {
            Button("Annulla", role: .cancel) { }
            Button("Esci", role: .destructive) {
                Task { @MainActor in
                    await leaveFamily()
                }
            }
        } message: {
            Text(
                """
                Verrai rimosso dalla famiglia e tutti i dati \
                associati verranno eliminati da questo dispositivo.
                """
            )
        }
        .alert("Errore", isPresented: .constant(leaveError != nil)) {
            Button("OK") { leaveError = nil }
        } message: {
            Text(leaveError ?? "")
        }
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
    
    private var familySummaryCard: some View {
        KBSettingsCard(
            title: family?.name ?? "Famiglia",
            subtitle: childSummaryText,
            systemImage: "person.2.fill",
            style: .info,
            action: nil,
            trailingSystemImage: "pencil",
            trailingAction: {
                guard let family else { return }
                let firstChildId = children.first?.id ?? ""
                coordinator.navigate(
                    to: .editFamily(
                        familyId: family.id,
                        childId: firstChildId
                    )
                )
            }
        )
    }
    
    private var familyChildrenCard: some View {
        let list = childRows
        
        return KBSettingsCardWithExtra(
            title: "Figli",
            subtitle: childrenSubtitle(list: list),
            systemImage: "figure.and.child.holdinghands",
            style: .secondary,
            action: nil
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if list.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "figure.child")
                        Text("Nessun figlio ancora inserito.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    // ✅ Semplice lista in sola lettura
                    ForEach(list, id: \.id) { c in
                        Button {
                            guard let family else { return }
                            coordinator.navigate(to: .editChild(familyId: family.id, childId: c.id))
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "face.smiling")
                                    .foregroundStyle(.secondary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name.isEmpty ? "Senza nome" : c.name)
                                        .font(.subheadline)
                                    
                                    if let birth = c.birthDate {
                                        Text("Nato/a: \(birth.formatted(date: .numeric, time: .omitted))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Divider().padding(.vertical, 6)
                
                // ✅ Navigazione a SetupFamilyView per aggiungere figli
                Button {
                    guard let family else { return }
                    let firstChildId = children.first?.id ?? ""
                    coordinator.navigate(
                        to: .editFamily(
                            familyId: family.id,
                            childId: firstChildId
                        )
                    )
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                        Text("Aggiungi figlio")
                        Spacer()
                    }
                }
                .font(.subheadline)
            }
        }
    }
    
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
    
    private var dangerZone: some View {
        KBSettingsCard(
            title: "Esci dalla famiglia",
            subtitle: "Non potrai più accedere ai dati condivisi.",
            systemImage: "rectangle.portrait.and.arrow.right",
            style: .danger,
            action: {
                showLeaveFamilyConfirm = true
            }
        )
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
        if children.isEmpty { return "Nessun bimbo/a configurato" }
        if children.count == 1 {
            let c = children[0]
            if let birth = c.birthDate {
                return "Bimbo/a: \(c.name) • Nato/a: \(birth.formatted(date: .numeric, time: .omitted))"
            }
            return "Bimbo/a: \(c.name)"
        }
        // 2+ figli: testo compatto
        let names = children.prefix(3).map(\.name).joined(separator: ", ")
        if children.count <= 3 { return "Figli: \(names)" }
        return "Figli: \(names) +\(children.count - 3)"
    }
    
    // MARK: - Actions
    
    private func leaveFamily() async {
        guard let familyId = family?.id else { return }
        
        do {
            let service = FamilyLeaveService(modelContext: modelContext)
            try await service.leaveFamily(familyId: familyId)
            coordinator.resetToRoot()
        } catch {
            leaveError = error.localizedDescription
        }
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
    
    private func childrenSubtitle(list: [ChildRow]) -> String {
        if list.isEmpty { return "Gestisci i profili dei figli." }
        if list.count == 1 { return "1 figlio configurato." }
        return "\(list.count) figli configurati."
    }
}

// MARK: - Small helpers

private extension String {
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
