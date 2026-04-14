
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
    
    @State private var showLeaveFamilyConfirm = false
    @State private var showOwnerLeaveOptions = false
    @State private var showOwnerAloneDeleteConfirm = false
    @State private var showDeleteFamilyConfirm = false
    @State private var showTransferSheet = false
    @State private var selectedNewOwner: KBFamilyMember?
    @State private var leaveError: String?
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
        
        if kids.isEmpty { return "Nessun figlio configurato." }
        if kids.count == 1 { return "Figlio: \(kids[0])" }
        if kids.count <= 3 { return "Figli: " + kids.joined(separator: ", ") }
        
        let firstThree = kids.prefix(3).joined(separator: ", ")
        return "Figli: \(firstThree) +\(kids.count - 3)"
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
        return members
            .filter { $0.familyId == fid && !$0.isDeleted }
            .sorted { displayLabel(for: $0) < displayLabel(for: $1) }
    }
    
    private var canLeave: Bool { activeMembers.count >= 2 }
    private var otherMembers: [KBFamilyMember] {
        activeMembers.filter { $0.userId != currentUid }
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
        .navigationTitle("Family")
        .onAppear {
            onAppearStartRealtime()
            syncMyMemberName()
        }
        .onDisappear { onDisappearStopRealtime() }
        .onReceive(NotificationCenter.default.publisher(for: .kbProfileDisplayNameUpdated)) { notification in
            guard let name = notification.userInfo?["displayName"] as? String,
                  !name.isEmpty else { return }
            updateMyMemberDisplayName(name)
        }
        .onReceive(SyncCenter.shared.currentUserRevoked) { revokedFamilyId in
            guard let fid = family?.id, fid == revokedFamilyId else { return }
            KBLog.sync.info("FamilySettingsView: currentUserRevoked received familyId=\(revokedFamilyId, privacy: .public)")
            Task { @MainActor in
                let service = FamilyLeaveService(modelContext: modelContext)
                do {
                    try service.wipeFamilyLocalOnly(familyId: revokedFamilyId)
                } catch {
                    KBLog.sync.error("FamilySettingsView: post-revoke local wipe failed: \(error.localizedDescription, privacy: .public)")
                }
                coordinator.setActiveFamily(nil)
                coordinator.resetToRoot()
            }
        }
        // MARK: - Alerts
        .alert("Uscire dalla famiglia?", isPresented: $showLeaveFamilyConfirm) {
            Button("Annulla", role: .cancel) { }
            Button("Esci", role: .destructive) {
                Task { @MainActor in await leaveFamily() }
            }
        } message: {
            Text("Verrai rimosso dalla famiglia e tutti i dati associati verranno eliminati da questo dispositivo.")
        }
        .alert("Non puoi uscire ora", isPresented: $showOwnerAloneDeleteConfirm) {
            Button("Annulla", role: .cancel) { }
            Button("Elimina famiglia", role: .destructive) {
                Task { @MainActor in await deleteFamily() }
            }
        } message: {
            Text("Sei l'unico membro. Per uscire devi eliminare la famiglia.")
        }
        .alert("Eliminare la famiglia?", isPresented: $showDeleteFamilyConfirm) {
            Button("Annulla", role: .cancel) { }
            Button("Elimina famiglia", role: .destructive) {
                Task { @MainActor in await deleteFamily() }
            }
        } message: {
            Text("Questa azione elimina la famiglia per tutti i membri.")
        }
        .alert("Sei il creatore della famiglia", isPresented: $showOwnerLeaveOptions) {
            Button("Trasferisci ownership") {
                showOwnerLeaveOptions = false
                showTransferSheet = true
            }
            Button("Elimina famiglia", role: .destructive) {
                showOwnerLeaveOptions = false
                Task { @MainActor in await deleteFamily() }
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Prima di uscire puoi trasferire la ownership a un altro membro oppure eliminare la famiglia.")
        }
        .sheet(isPresented: $showTransferSheet) {
            NavigationStack {
                List(otherMembers) { member in
                    Button {
                        selectedNewOwner = member
                        showTransferSheet = false
                        Task { @MainActor in
                            await transferOwnershipAndLeave(newOwnerUid: member.userId)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayLabel(for: member))
                                .foregroundStyle(.primary)
                            Text(member.email?.trimmedNonEmpty ?? member.userId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Nuovo owner")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Annulla") { showTransferSheet = false }
                    }
                }
            }
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
    
    // MARK: - Lifecycle
    
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
            Text("Qui gestisci la famiglia e inviti l'altro genitore.")
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
                    KBLog.navigation.debug("FamilySettingsView: tap inviteCode")
                    coordinator.navigate(to: .inviteCode)
                }
            )
            
            KBSettingsCard(
                title: "Entra con codice",
                subtitle: "Usa un codice se vuoi unirti a un'altra famiglia.",
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
                if activeMembers.count <= 1 {
                    showOwnerAloneDeleteConfirm = true
                } else if !isOwner {
                    showLeaveFamilyConfirm = true
                } else {
                    showOwnerLeaveOptions = true
                }
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
                subtitle: "Se l'altro genitore ha già creato la famiglia, inserisci il codice.",
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
            let message = error.localizedDescription.lowercased()
            if message.contains("unico membro") {
                showOwnerAloneDeleteConfirm = true
            } else {
                leaveError = error.localizedDescription
            }
        }
    }
    
    @MainActor
    private func transferOwnershipAndLeave(newOwnerUid: String) async {
        guard let familyId = family?.id else { return }
        do {
            let service = FamilyLeaveService(modelContext: modelContext)
            try await service.transferOwnershipAndLeave(familyId: familyId, newOwnerUid: newOwnerUid)
            coordinator.resetToRoot()
        } catch {
            leaveError = error.localizedDescription
        }
    }
    
    @MainActor
    private func deleteFamily() async {
        guard let familyId = family?.id else { return }
        do {
            let service = FamilyLeaveService(modelContext: modelContext)
            try await service.deleteFamily(familyId: familyId)
            coordinator.setActiveFamily(nil)
            coordinator.resetToRoot()
        } catch {
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
            KBLog.sync.debug("FamilySettings: updated local member displayName=\(name, privacy: .public)")
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
                KBLog.sync.debug("FamilySettings: updated remote member displayName=\(name, privacy: .public)")
            } catch {
                KBLog.sync.error("FamilySettings: remote member name update failed: \(error.localizedDescription, privacy: .public)")
            }
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
