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
import Combine

/// Family settings hub.
///
/// Responsibilities:
/// - Shows current family summary and members list (local SwiftData).
/// - Provides navigation to invite/join/setup routes.
/// - Starts/stops realtime listeners for members + children while the view is visible.
///
/// Logging strategy (important for SwiftUI views):
/// - Avoid logging in `body` (recomputed frequently).
/// - Log only lifecycle transitions and user-triggered actions.
/// - Use `KBLog.*` and keep messages short but searchable.
struct FamilySettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    @Query private var families: [KBFamily]
    @Query private var members: [KBFamilyMember]
    
    // ⚠️ Compatibilità con route legacy `.editFamily(familyId:childId:)`.
    // NON renderizziamo children qui (niente card figli), li usiamo solo per ricavare un childId.
    @Query private var allChildren: [KBChild]
    
    @State private var showLeaveFamilyConfirm = false
    @State private var leaveError: String?
    @State private var memberToRevoke: KBFamilyMember?
    @State private var showRevokeConfirm = false
    @State private var revokeError: String?
    
    /// La famiglia attiva: prima cerca per activeFamilyId del coordinator,
    /// poi fallback a families.first (primo avvio, utente con una sola famiglia).
    private var family: KBFamily? {
        if let activeId = coordinator.activeFamilyId {
            return families.first(where: { $0.id == activeId }) ?? families.first
        }
        return families.first
    }
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
        
        if kids.isEmpty { return "Nessun figlio configurato." }
        if kids.count == 1 { return "Figlio: \(kids[0])" }
        if kids.count <= 3 { return "Figli: " + kids.joined(separator: ", ") }
        
        let firstThree = kids.prefix(3).joined(separator: ", ")
        return "Figli: \(firstThree) +\(kids.count - 3)"
    }
    
    private var currentUid: String { Auth.auth().currentUser?.uid ?? "" }
    private var isOwner: Bool { family?.createdBy == currentUid }
    
    /// Membri attivi (non eliminati) della famiglia corrente
    private var activeMembers: [KBFamilyMember] {
        guard let fid = family?.id else { return [] }
        return members
            .filter { $0.familyId == fid && !$0.isDeleted }
            .sorted { displayLabel(for: $0) < displayLabel(for: $1) }
    }
    
    /// Il bottone "Esci" è visibile solo se ci sono almeno 2 membri attivi
    private var canLeave: Bool { activeMembers.count >= 2 }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                
                if hasFamily {
                    familySummaryCard
                    familyMembersCard
                    actionsWithFamily
                    if canLeave { dangerZone }
                } else {
                    emptyStateCard
                    actionsWithoutFamily
                }
            }
            .padding()
        }
        .navigationTitle("Family")
        .onAppear { onAppearStartRealtime() }
        .onDisappear { onDisappearStopRealtime() }
        .onReceive(SyncCenter.shared.currentUserRevoked) { revokedFamilyId in
            guard let fid = family?.id, fid == revokedFamilyId else { return }
            KBLog.sync.info("FamilySettingsView: currentUserRevoked received familyId=\(revokedFamilyId, privacy: .public)")
            Task { @MainActor in
                // Wipe local data and return to root
                do {
                    let service = FamilyLeaveService(modelContext: modelContext)
                    try await service.leaveFamily(familyId: revokedFamilyId)
                } catch {
                    // Wipe failed (e.g. already wiped) — still reset to root
                    KBLog.sync.error("FamilySettingsView: post-revoke wipe failed: \(error.localizedDescription, privacy: .public)")
                }
                coordinator.setActiveFamily(nil)
                coordinator.resetToRoot()
            }
        }
        .alert("Uscire dalla famiglia?", isPresented: $showLeaveFamilyConfirm) {
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
        .alert("Errore", isPresented: Binding(
            get: { leaveError != nil },
            set: { if !$0 { leaveError = nil } }
        )) {
            Button("OK") { leaveError = nil }
        } message: {
            Text(leaveError ?? "")
        }
        .alert("Revocare l'accesso?", isPresented: $showRevokeConfirm) {
            Button("Annulla", role: .cancel) { memberToRevoke = nil }
            Button("Revoca", role: .destructive) {
                guard let m = memberToRevoke else { return }
                Task { @MainActor in await revokeAccess(member: m) }
            }
        } message: {
            Text("\(displayLabel(for: memberToRevoke)) non potrà più accedere ai dati della famiglia.")
        }
        .alert("Errore revoca", isPresented: Binding(
            get: { revokeError != nil },
            set: { if !$0 { revokeError = nil } }
        )) {
            Button("OK") { revokeError = nil }
        } message: {
            Text(revokeError ?? "")
        }
    }
    
    // MARK: - Lifecycle (logs only here, not in body)
    
    @MainActor
    private func onAppearStartRealtime() {
        guard let fid = family?.id else {
            KBLog.navigation.debug("FamilySettingsView appeared (no family)")
            return
        }
        
        KBLog.navigation.info("FamilySettingsView appeared familyId=\(fid, privacy: .public) start realtime (members+children)")
        SyncCenter.shared.startMembersRealtime(familyId: fid, modelContext: modelContext)
        SyncCenter.shared.startChildrenRealtime(familyId: fid, modelContext: modelContext)
    }
    
    @MainActor
    private func onDisappearStopRealtime() {
        KBLog.navigation.debug("FamilySettingsView disappeared stop realtime (members+children)")
        SyncCenter.shared.stopMembersRealtime()
        SyncCenter.shared.stopChildrenRealtime()
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
                
                KBLog.navigation.debug("FamilySettingsView: tap editFamily familyId=\(family.id, privacy: .public)")
                
                // Route legacy: richiede childId.
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
        let list = activeMembers
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
                            Image(systemName: m.userId == family?.createdBy ? "crown.fill" : "person.fill")
                                .foregroundStyle(m.userId == family?.createdBy ? Color.orange : Color.secondary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayLabel(for: m))
                                    .font(.subheadline)
                                Text(m.userId == family?.createdBy ? "Owner" : roleLabel(m.role))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            // Bottone revoca: visibile solo all'owner, non su se stesso
                            if isOwner && m.userId != currentUid {
                                Button {
                                    memberToRevoke = m
                                    showRevokeConfirm = true
                                } label: {
                                    Image(systemName: "person.crop.circle.badge.minus")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        if m.id != list.last?.id {
                            Divider()
                        }
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
                action: {
                    KBLog.navigation.debug("FamilySettingsView: tap inviteCode")
                    coordinator.navigate(to: .inviteCode)
                }
            )
            
            KBSettingsCard(
                title: "Entra con codice",
                subtitle: "Usa un codice se vuoi unirti a un’altra famiglia.",
                systemImage: "key.fill",
                style: .secondary,
                action: {
                    KBLog.navigation.debug("FamilySettingsView: tap joinFamily")
                    coordinator.navigate(to: .joinFamily)
                }
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
                guard let fid = family?.id else { return }
                KBLog.navigation.info("FamilySettingsView: tap leave familyId=\(fid, privacy: .public)")
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
                action: {
                    KBLog.navigation.debug("FamilySettingsView: tap setupFamily")
                    coordinator.navigate(to: .setupFamily)
                }
            )
            
            KBSettingsCard(
                title: "Entra con codice",
                subtitle: "Se l’altro genitore ha già creato la famiglia, inserisci il codice.",
                systemImage: "key.fill",
                style: .secondary,
                action: {
                    KBLog.navigation.debug("FamilySettingsView: tap joinFamily (no family)")
                    coordinator.navigate(to: .joinFamily)
                }
            )
        }
    }
    
    // MARK: - Actions
    
    /// Leaves the current family.
    ///
    /// Expected side effects:
    /// - Local data for that family is removed from this device (by `FamilyLeaveService`).
    /// - UI navigates back to root.
    ///
    /// Logging:
    /// - Info on start + success, error on failure.
    @MainActor
    private func leaveFamily() async {
        guard let familyId = family?.id else { return }
        
        KBLog.sync.info("FamilySettingsView: leaving familyId=\(familyId, privacy: .public)")
        
        do {
            let service = FamilyLeaveService(modelContext: modelContext)
            try await service.leaveFamily(familyId: familyId)
            KBLog.sync.info("FamilySettingsView: leave OK familyId=\(familyId, privacy: .public)")
            coordinator.resetToRoot()
        } catch {
            KBLog.sync.error("FamilySettingsView: leave FAILED familyId=\(familyId, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
            leaveError = error.localizedDescription
        }
    }
    
    @MainActor
    private func revokeAccess(member: KBFamilyMember) async {
        guard let familyId = family?.id else { return }
        KBLog.sync.info("FamilySettingsView: revoking uid=\(member.userId, privacy: .public)")
        do {
            let service = FamilyRevokeService(modelContext: modelContext)
            try await service.revokeMember(familyId: familyId, targetUid: member.userId)
            KBLog.sync.info("FamilySettingsView: revoke OK uid=\(member.userId, privacy: .public)")
            memberToRevoke = nil
        } catch {
            KBLog.sync.error("FamilySettingsView: revoke FAILED err=\(error.localizedDescription, privacy: .public)")
            revokeError = error.localizedDescription
            memberToRevoke = nil
        }
    }
    
    // MARK: - Helpers
    
    private func displayLabel(for m: KBFamilyMember?) -> String {
        guard let m else { return "questo membro" }
        return displayLabel(for: m)
    }
    
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
