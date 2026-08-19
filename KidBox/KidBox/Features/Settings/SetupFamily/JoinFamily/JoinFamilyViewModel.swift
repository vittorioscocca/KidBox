//
//  JoinFamilyViewModel.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import SwiftData
import Combine
import OSLog

@MainActor
final class JoinFamilyViewModel: ObservableObject {

    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var didJoin = false

    var coordinator: AppCoordinator
    private let modelContext: ModelContext

    init(modelContext: ModelContext, coordinator: AppCoordinator) {
        self.modelContext = modelContext
        self.coordinator = coordinator
        KBLog.auth.kbDebug("JoinFamilyViewModel init")
    }

    /// Entra in famiglia dal QR inquadrato.
    ///
    /// Il codice testuale non esiste più: prima questo flusso estraeva un `code`
    /// dal payload e faceva un secondo giro per creare la membership, mentre il
    /// QR conteneva già `familyId`. Ora il payload viene ricondotto a
    /// `PendingFamilyInvite` e gestito dallo stesso percorso del link
    /// d'invito — chiave prima, membership poi.
    ///
    /// - Important: Non registrare mai il payload: contiene il segreto.
    func joinFromQR(payload raw: String) async {
        guard let invite = PendingFamilyInvite.parse(fromQRPayload: raw) else {
            errorMessage = String(localized: "Questo QR non è un invito KidBox valido.")
            KBLog.sync.kbError("JoinFamilyViewModel: QR non valido")
            return
        }

        isBusy = true
        errorMessage = nil
        didJoin = false
        defer {
            isBusy = false
            KBLog.sync.kbDebug("JoinFamilyViewModel joinFromQR end didJoin=\(self.didJoin)")
        }

        do {
            try await FamilyInviteLinkJoiner.join(
                invite: invite,
                modelContext: modelContext,
                coordinator: coordinator
            )
            didJoin = true
            KBLog.sync.kbInfo("JoinFamilyViewModel: join da QR riuscito")
        } catch {
            errorMessage = error.localizedDescription
            KBLog.sync.kbError("JoinFamilyViewModel: join da QR fallito: \(error.localizedDescription)")
        }
    }
}
