//
//  InviteCodeViewModel.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import SwiftData
import OSLog
import Combine
import UIKit
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class InviteCodeViewModel: ObservableObject {
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var qrPayload: String?
    /// Universal Link da condividere: trasporta anche la chiave, a differenza
    /// del solo `code`.
    @Published var shareLink: String?

    /// Invito attualmente valido, da annullare con [revokeInvite].
    @Published private(set) var currentInviteId: String?
    @Published private(set) var currentInviteFamilyId: String?
    
    private let remote: InviteRemoteStore
    private let modelContext: ModelContext
    private let coordinator: AppCoordinator
    
    init(remote: InviteRemoteStore, modelContext: ModelContext, coordinator: AppCoordinator) {
        self.remote = remote
        self.modelContext = modelContext
        self.coordinator = coordinator
    }
    
    /// Generates an invite for the currently active family ([AppCoordinator.activeFamilyId]).
    ///
    /// Produce il QR e il link condivisibile, entrambi con il materiale
    /// crittografico necessario a sbloccare la chiave di famiglia.
    ///
    /// Notes:
    /// - This method is `@MainActor` to safely mutate published UI state.
    /// - Avoids `print` to keep logs structured and filterable in Console.
    func generateInviteCode() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        
        KBLog.sync.kbInfo("InviteCodeVM: generateInviteCode started")
        
        do {
            let (familyId, familyName) = try resolveInviteFamily()
            KBLog.sync.kbInfo("InviteCodeVM: using familyId=\(familyId)")

            KBLog.sync.kbInfo("InviteCodeVM: creating encrypted invite")
            let invite = try await InviteWrapService().createInvite(
                familyId: familyId,
                familyName: familyName,
                inviterDisplayName: currentUserDisplayName(),
                ttlSeconds: 24 * 3600
            )
            KBLog.sync.kbInfo("InviteCodeVM: encrypted invite created inviteId=\(invite.inviteId)")
            
            // Il QR porta familyId + inviteId + secret: tutto ciò che serve per
            // entrare e per sbloccare la chiave. Il vecchio `&code=` è sparito
            // insieme al codice testuale, che creava membri privi di chiave.
            //
            // Nota di sicurezza: non loggare mai il payload completo.
            qrPayload = invite.qrPayload
            shareLink = invite.shareLink
            currentInviteId = invite.inviteId
            currentInviteFamilyId = familyId
            KBLog.sync.kbInfo("InviteCodeVM: qr payload + share link ready familyId=\(familyId) inviteId=\(invite.inviteId)")
            
        } catch {
            errorMessage = (error as NSError).localizedDescription
            KBLog.sync.kbError("InviteCodeVM: generateInviteCode failed: \(error.localizedDescription)")
        }
    }
    
    /// Annulla l'invito in corso, rendendo inservibile il link già condiviso.
    ///
    /// È la difesa che conta quando il link viene mandato al contatto sbagliato:
    /// il segreto viaggia dentro l'URL, quindi finché l'invito è valido chi lo
    /// possiede può entrare. Cancellando il documento su Firestore,
    /// `JoinWrapService` non trova più nulla e rifiuta.
    ///
    /// Su Android esisteva già (`InviteCodeViewModel.revokeInvite`), su iOS no:
    /// c'era solo la revoca di un membro **già entrato**, che arriva tardi.
    func revokeInvite() async {
        guard let familyId = currentInviteFamilyId, let inviteId = currentInviteId else {
            KBLog.sync.kbDebug("InviteCodeVM: revoke ignorata (nessun invito attivo)")
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await Firestore.firestore()
                .collection("families").document(familyId)
                .collection("invites").document(inviteId)
                .delete()
            KBLog.security.kbInfo("InviteCodeVM: invito revocato inviteId=\(inviteId)")
            resetInviteState()
        } catch {
            errorMessage = error.localizedDescription
            KBLog.sync.kbError("InviteCodeVM: revoca fallita: \(error.localizedDescription)")
        }
    }

    private func resetInviteState() {
        qrPayload = nil
        shareLink = nil
        currentInviteId = nil
        currentInviteFamilyId = nil
    }

    private func resolveInviteFamily() throws -> (id: String, name: String) {
        if let activeId = coordinator.activeFamilyId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !activeId.isEmpty {
            let descriptor = FetchDescriptor<KBFamily>(
                predicate: #Predicate { $0.id == activeId }
            )
            if let family = try modelContext.fetch(descriptor).first {
                return (family.id, family.name)
            }
            KBLog.sync.kbWarning("InviteCodeVM: activeFamilyId=\(activeId) not in local DB, fallback")
        }
        let sorted = FetchDescriptor<KBFamily>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let family = try modelContext.fetch(sorted).first else {
            throw NSError(
                domain: "KidBox",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Nessuna family trovata."]
            )
        }
        return (family.id, family.name)
    }

    /// Nome mostrato a chi riceve l'invito, prima ancora che entri. Il
    /// profilo locale ha la precedenza; altrimenti si spezza il `displayName`
    /// di Firebase Auth, come già fa `prefillNameFromExistingProfile` nel
    /// wizard.
    private func currentUserDisplayName() -> String {
        guard let uid = Auth.auth().currentUser?.uid else { return "" }
        let descriptor = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
        if let profile = try? modelContext.fetch(descriptor).first {
            let name = (profile.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, name != "Utente" { return name }
        }
        let authName = (Auth.auth().currentUser?.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return authName
    }
    
    /// Copia negli appunti il link d'invito completo.
    ///
    /// Prima copiava il solo codice testuale, che **non** trasporta la chiave di
    /// cifratura: chi lo usava entrava in famiglia senza poter leggere password,
    /// documenti, wallet e allegati. Il link invece è autosufficiente.
    func copyToClipboard() {
        guard let shareLink else {
            KBLog.sync.kbDebug("InviteCodeVM: copyToClipboard ignored (no link)")
            return
        }
#if canImport(UIKit)
        UIPasteboard.general.string = shareLink
        KBLog.sync.kbInfo("InviteCodeVM: invite link copied to clipboard")
#endif
    }

    /// Testo da condividere: contiene il Universal Link dell'invito.
    ///
    /// Il segreto è nel frammento dell'URL (dopo `#`), quindi non viene inviato
    /// ai server né ai bot che generano le anteprime dei link nelle app di
    /// messaggistica. Vedi `InviteWrapService.shareLink(familyId:inviteId:secretBase64url:)`.
    var shareText: String {
        guard let shareLink else { return "" }
        return "\(Self.shareSubject):\n\(shareLink)"
    }

    /// Oggetto della mail quando si condivide da Mail o da un client di posta.
    ///
    /// Esplicito e non lasciato dedurre dalla prima riga del testo: senza, alcuni
    /// client mandano una mail con oggetto vuoto. È la stessa stringa usata da
    /// Android (`settings_invite_share_subject`), così l'invito arriva identico
    /// da entrambe le app.
    static let shareSubject = String(localized: "Entra nella nostra famiglia su KidBox")
}
