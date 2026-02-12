//
//  FamilySettingsView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import FirebaseAuth
import OSLog
import SwiftData

struct FamilySettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    @Query private var families: [KBFamily]
    @Query private var members: [KBFamilyMember]
    
    // ⚠️ solo per compatibilità con la route .editFamily(familyId:childId:)
    // NON renderizziamo children qui, niente card figli.
    @Query private var allChildren: [KBChild]
    
    @State private var showLeaveFamilyConfirm = false
    @State private var leaveError: String?
    
    private var family: KBFamily? { families.first }
    private var hasFamily: Bool { family != nil }
    
    /// Primo childId disponibile per la family (serve solo per la route legacy).
    /// Se non esiste, ritorna stringa vuota: la destination deve gestire fallback.
    private var firstChildIdForRoute: String {
        guard let family else { return "" }
        return allChildren.first(where: { $0.familyId == family.id })?.id ?? ""
    }
    
    private var childrenNamesSummary: String {
        guard let family else { return "" }
        
        let kids = allChildren
            .filter { $0.familyId == family.id }
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if kids.isEmpty {
            return "Nessun figlio configurato."
        }
        
        if kids.count == 1 {
            return "Figlio: \(kids[0])"
        }
        
        if kids.count <= 3 {
            return "Figli: " + kids.joined(separator: ", ")
        }
        
        let firstThree = kids.prefix(3).joined(separator: ", ")
        return "Figli: \(firstThree) +\(kids.count - 3)"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                
                if hasFamily {
                    familySummaryCard
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
            subtitle: childrenNamesSummary,
            systemImage: "person.2.fill",
            style: .info,
            action: nil,
            trailingSystemImage: "pencil",
            trailingAction: {
                guard let family else { return }
                
                // Route legacy: richiede childId.
                // Qui passiamo un childId disponibile se c’è, altrimenti stringa vuota.
                coordinator.navigate(
                    to: .editFamily(
                        familyId: family.id,
                        childId: firstChildIdForRoute
                    )
                )
            }
        )
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
}

// MARK: - Small helpers

private extension String {
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
