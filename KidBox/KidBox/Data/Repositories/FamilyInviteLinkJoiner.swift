//
//  FamilyInviteLinkJoiner.swift
//  KidBox
//
//  Applica un invito arrivato da Universal Link.
//
//  Ordine dei due passi, che non è indifferente:
//  1. `JoinWrapService` consuma l'invito e sblocca la master key
//  2. `FamilyJoinService` crea la membership e scarica il bundle famiglia
//
//  La chiave PRIMA della membership: `JoinWrapService` valida il segreto in una
//  transazione e marca l'invito come usato. Se fallisse (scaduto, già usato,
//  segreto errato) non si deve entrare affatto, altrimenti si ricadrebbe nello
//  stato che questo lavoro serve a eliminare — membro dentro la famiglia ma
//  senza chiave, con documenti, wallet, foto e chat illeggibili.
//

import Foundation
import SwiftData

@MainActor
enum FamilyInviteLinkJoiner {

    enum JoinLinkError: LocalizedError {
        case alreadyMember

        var errorDescription: String? {
            switch self {
            case .alreadyMember:
                return String(localized: "Fai già parte di questa famiglia.")
            }
        }
    }

    /// Esegue l'invito. Rilancia gli errori di `JoinWrapService`
    /// (scaduto, già usato, segreto non valido) perché il chiamante li mostri.
    static func join(
        invite: PendingFamilyInvite,
        modelContext: ModelContext,
        coordinator: AppCoordinator
    ) async throws {
        KBLog.sync.kbInfo("InviteLink: inizio familyId=\(invite.familyId)")

        // Già dentro: l'invito è comunque da consumare? No — si esce subito,
        // così un link riaperto per sbaglio non brucia un invito valido né
        // rifà il bootstrap di una famiglia che si ha già.
        let fid = invite.familyId
        let descriptor = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
        if (try? modelContext.fetch(descriptor).first) != nil {
            KBLog.sync.kbInfo("InviteLink: già membro familyId=\(fid)")
            coordinator.setActiveFamily(fid, force: true)
            throw JoinLinkError.alreadyMember
        }

        // 1) Chiave: riusa il percorso già collaudato del QR.
        try await JoinWrapService().join(usingQRPayload: invite.qrEquivalentPayload)
        KBLog.sync.kbInfo("InviteLink: master key sbloccata familyId=\(fid)")

        // 2) Membership + bundle famiglia.
        let service = FamilyJoinService(
            inviteRemote: InviteRemoteStore(),
            readRemote: FamilyReadRemoteStore(),
            modelContext: modelContext
        )
        let outcome = try await service.joinFamily(familyId: fid, coordinator: coordinator)

        if case .missingVaultKey = outcome {
            // Non dovrebbe accadere: il passo 1 ha appena salvato la chiave in
            // Keychain. Se succede è un problema di Keychain, e va visto nei log
            // invece di passare inosservato.
            KBLog.security.kbError("InviteLink: chiave assente DOPO unwrap riuscito familyId=\(fid)")
        }

        // 3) Nome sul documento membro. Sta QUI e non nei chiamanti perché
        // `addMember` crea il membro senza `displayName`: chi non lo propagava
        // — il join da QR nelle impostazioni e l'invito consumato in
        // `RootHostView` — lasciava un membro anonimo agli occhi degli altri.
        // Questo è l'unico punto attraversato da tutte le strade di join.
        await UserProfileWriter.propagateDisplayNameToMember(
            familyId: fid,
            modelContext: modelContext
        )

        KBLog.sync.kbInfo("InviteLink: completato familyId=\(fid)")
    }
}
