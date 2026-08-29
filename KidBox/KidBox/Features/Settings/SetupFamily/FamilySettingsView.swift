
//
//  FamilySettingsView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import OSLog
import SwiftData
import Combine

/// Family settings hub.
struct FamilySettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    
    // MARK: - Dynamic theme (same as LoginView)
    
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    @Query private var families: [KBFamily]
    @Query private var members: [KBFamilyMember]
    @Query private var allChildren: [KBChild]
    
    @StateObject private var leaveFlow = FamilyLeaveFlow()
    @State private var memberToRevoke: KBFamilyMember?
    @State private var showRevokeConfirm = false
    @State private var revokeError: String?
    
    private var family: KBFamily? {
        if let activeId = coordinator.activeFamilyId {
            return families.first(where: { $0.id == activeId }) ?? families.first
        }
        return families.first
    }
    private var hasFamily: Bool { family != nil }
    
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
        
        if kids.isEmpty { return String(localized: "Nessun figlio configurato.") }
        if kids.count == 1 { return String(localized: "Figlio: \(kids[0])") }
        if kids.count <= 3 { return String(localized: "Figli: \(kids.joined(separator: ", "))") }
        
        let firstThree = kids.prefix(3).joined(separator: ", ")
        return String(localized: "Figli: \(firstThree) +\(kids.count - 3)")
    }
    
    private var currentUid: String { Auth.auth().currentUser?.uid ?? "" }
    private var isOwner: Bool {
        guard let fid = family?.id else { return false }
        let ownerFromMembers = members.contains {
            $0.familyId == fid &&
            !$0.isDeleted &&
            $0.userId == currentUid &&
            $0.role.lowercased() == "owner"
        }
        return ownerFromMembers || (family?.createdBy == currentUid)
    }
    
    private var activeMembers: [KBFamilyMember] {
        guard let fid = family?.id else { return [] }
        var seen = Set<String>()
        return members
            .filter { $0.familyId == fid && !$0.isDeleted }
            .filter { seen.insert($0.userId).inserted }
            .sorted { displayLabel(for: $0) < displayLabel(for: $1) }
    }
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
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
        }
        .onAppear {
            syncMyMemberName()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kbProfileDisplayNameUpdated)) { notification in
            guard let name = notification.userInfo?["displayName"] as? String,
                  !name.isEmpty else { return }
            updateMyMemberDisplayName(name)
        }
        .onReceive(SyncCenter.shared.currentUserRevoked) { revokedFamilyId in
            guard let fid = family?.id, fid == revokedFamilyId else { return }
            KBLog.sync.kbInfo("FamilySettingsView: currentUserRevoked received familyId=\(revokedFamilyId)")
            Task { @MainActor in
                let service = FamilyLeaveService(modelContext: modelContext)
                do {
                    try service.wipeFamilyLocalOnly(familyId: revokedFamilyId)
                } catch {
                    KBLog.sync.kbError("FamilySettingsView: post-revoke local wipe failed: \(error.localizedDescription)")
                }
                coordinator.setActiveFamily(nil)
                coordinator.resetToRoot()
            }
        }
        // MARK: - Alerts
        .familyLeaveAlerts(
            leaveFlow,
            familyId: family?.id,
            modelContext: modelContext,
            coordinator: coordinator
        )
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
    
    // MARK: - UI
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Famiglia")
                .font(.title2).bold()
            Text("KidBox funziona davvero quando la famiglia è al completo: appena inviti l'altro genitore, calendario, spese, liste, documenti e chat si aggiornano per tutti in tempo reale. Da solo vedi solo la tua metà dell'organizzazione.")
                // 13pt: stessa dimensione del 13.sp di FamilySettingsScreen su Android.
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
    
    private var familySummaryCard: some View {
        KBSettingsCard(
            // Nomi liberi inseriti dall'utente: escape di "%" per evitare che
            // LocalizedStringKey lo interpreti come specificatore di formato.
            title: LocalizedStringKey((family?.name ?? NSLocalizedString("Famiglia", comment: "")).replacingOccurrences(of: "%", with: "%%")),
            subtitle: LocalizedStringKey(childrenNamesSummary.replacingOccurrences(of: "%", with: "%%")),
            systemImage: "person.2.fill",
            style: .info,
            action: nil,
            trailingSystemImage: "pencil",
            trailingAction: {
                guard let family else { return }
                KBLog.navigation.kbDebug("FamilySettingsView: tap editFamily familyId=\(family.id)")
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
                title: "Invita l'altro genitore o un altro componente della famiglia",
                subtitle: "Genera un codice e condividilo.",
                systemImage: "qrcode",
                style: .primary,
                action: {
                    KBLog.navigation.kbDebug("FamilySettingsView: tap inviteCode")
                    coordinator.navigate(to: .inviteCode)
                }
            )
            
            KBSettingsCard(
                title: "Entra con codice",
                subtitle: "Usa un codice se vuoi unirti a un'altra famiglia.",
                systemImage: "key.fill",
                style: .secondary,
                action: {
                    KBLog.navigation.kbDebug("FamilySettingsView: tap joinFamily")
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
                KBLog.navigation.kbInfo("FamilySettingsView: tap leave familyId=\(fid)")
                leaveFlow.requestLeave(
                    activeMembers: activeMembers,
                    isOwner: isOwner,
                    currentUid: currentUid
                )
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
                    KBLog.navigation.kbDebug("FamilySettingsView: tap setupFamily")
                    coordinator.navigate(to: .setupFamily)
                }
            )
            
            KBSettingsCard(
                title: "Entra con codice",
                subtitle: "Se l'altro genitore ha già creato la famiglia, inserisci il codice.",
                systemImage: "key.fill",
                style: .secondary,
                action: {
                    KBLog.navigation.kbDebug("FamilySettingsView: tap joinFamily (no family)")
                    coordinator.navigate(to: .joinFamily)
                }
            )
        }
    }
    
    // MARK: - Actions
    
    @MainActor
    private func revokeAccess(member: KBFamilyMember) async {
        guard let familyId = family?.id else { return }
        KBLog.sync.kbInfo("FamilySettingsView: revoking uid=\(member.userId)")
        do {
            let service = FamilyRevokeService(modelContext: modelContext)
            try await service.revokeMember(familyId: familyId, targetUid: member.userId)
            KBLog.sync.kbInfo("FamilySettingsView: revoke OK uid=\(member.userId)")
            memberToRevoke = nil
        } catch {
            KBLog.sync.kbError("FamilySettingsView: revoke FAILED err=\(error.localizedDescription)")
            revokeError = error.localizedDescription
            memberToRevoke = nil
        }
    }
    
    // MARK: - Name sync helpers
    
    private func syncMyMemberName() {
        let uid = currentUid
        guard !uid.isEmpty else { return }
        
        let profileDesc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
        guard let profile = try? modelContext.fetch(profileDesc).first else { return }
        
        let dn = (profile.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        if !dn.isEmpty && dn != "Utente" {
            name = dn
        } else {
            let fn = (profile.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ln = (profile.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            name = "\(fn) \(ln)".trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard !name.isEmpty && name != "Utente" else { return }
        updateMyMemberDisplayName(name)
    }
    
    private func updateMyMemberDisplayName(_ name: String) {
        let uid = currentUid
        guard !uid.isEmpty, let fid = family?.id else { return }
        
        let desc = FetchDescriptor<KBFamilyMember>(
            predicate: #Predicate { $0.userId == uid && $0.familyId == fid }
        )
        if let member = try? modelContext.fetch(desc).first {
            guard member.displayName != name else { return }
            member.displayName = name
            try? modelContext.save()
            KBLog.sync.kbDebug("FamilySettings: updated local member displayName=\(name)")
        }
        
        Task {
            do {
                try await Firestore.firestore()
                    .collection("families").document(fid)
                    .collection("members").document(uid)
                    .setData([
                        "displayName": name,
                        "updatedAt": Timestamp(date: Date())
                    ], merge: true)
                KBLog.sync.kbDebug("FamilySettings: updated remote member displayName=\(name)")
            } catch {
                KBLog.sync.kbError("FamilySettings: remote member name update failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func displayLabel(for m: KBFamilyMember?) -> String {
        guard let m else { return NSLocalizedString("questo membro", comment: "Fallback member label") }
        return displayLabel(for: m)
    }

    private func displayLabel(for m: KBFamilyMember) -> String {
        (m.displayName?.trimmedNonEmpty)
        ?? (m.email?.trimmedNonEmpty)
        ?? NSLocalizedString("Utente", comment: "Fallback member label")
    }

    private func membersSubtitle(list: [KBFamilyMember]) -> LocalizedStringKey {
        if list.isEmpty { return "Chi può accedere ai dati della famiglia." }
        // L'interpolazione dentro `LocalizedStringKey` risolve dal catalogo la
        // variazione plurale ("%lld membri collegati.") già impostata con
        // singolare/plurale per tutte le lingue — niente più caso speciale per 1.
        return "\(list.count) membri collegati."
    }

    private func roleLabel(_ raw: String) -> LocalizedStringKey {
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
