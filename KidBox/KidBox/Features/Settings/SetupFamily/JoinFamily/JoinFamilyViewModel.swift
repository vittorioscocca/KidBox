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
    /// Testo mostrato quando si entra con il solo codice testuale, senza chiave.
    /// Nomina la schermata e il pulsante reali ("Invita genitore" →
    /// "Genera codice QR") così l'utente sa esattamente cosa chiedere.
    static let missingVaultKeyMessage = """
        Sei entrato nella famiglia, ma questo invito non conteneva la chiave di \
        cifratura: Password, Documenti e Wallet condivisi resteranno illeggibili. \
        Chiedi a chi ti ha invitato di aprire "Invita genitore" e generare un \
        codice QR, poi scansionalo da questa schermata.
        """

    @Published var code: String = ""
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var didJoin = false

    /// Avviso non bloccante mostrato quando il join riesce ma senza chiave di
    /// cifratura: l'utente è membro, però i contenuti cifrati restano illeggibili.
    /// Distinto da `errorMessage` perché il join **non** è fallito.
    @Published var vaultKeyWarning: String?

    var coordinator: AppCoordinator
    
    private let service: FamilyJoinService
    
    init(service: FamilyJoinService, coordinator: AppCoordinator) {
        self.service = service
        self.coordinator = coordinator
        KBLog.auth.kbDebug("JoinFamilyViewModel init")
    }
    
    /// Attempts to join a family using the current `code`.
    ///
    /// - Note: The code is normalized (trim + uppercase) before being sent to `FamilyJoinService`.
    /// - Important: Never log the invite code content; it can be sensitive. If needed, log only its length.
    func join() async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            KBLog.auth.kbDebug("JoinFamilyViewModel join skipped: empty code")
            return
        }
        
        // Log only metadata (length), not the code.
        KBLog.sync.kbInfo("JoinFamilyViewModel join start codeLen=\(trimmed.count)")
        
        isBusy = true
        errorMessage = nil
        vaultKeyWarning = nil
        didJoin = false
        defer {
            isBusy = false
            KBLog.sync.kbDebug("JoinFamilyViewModel join end didJoin=\(self.didJoin)")
        }

        do {
            let outcome = try await service.joinFamily(code: trimmed, coordinator: coordinator)
            if case .missingVaultKey = outcome {
                vaultKeyWarning = Self.missingVaultKeyMessage
                KBLog.sync.kbError("JoinFamilyViewModel join OK but vault key missing")
            }
            didJoin = true
            KBLog.sync.kbInfo("JoinFamilyViewModel join OK")
        } catch {
            errorMessage = error.localizedDescription
            KBLog.sync.kbError("JoinFamilyViewModel join failed: \(error.localizedDescription)")
        }
    }
}
