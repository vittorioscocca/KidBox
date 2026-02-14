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

@MainActor
final class InviteCodeViewModel: ObservableObject {
    @Published var code: String?
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var qrPayload: String?
    
    private let remote: InviteRemoteStore
    private let modelContext: ModelContext
    
    init(remote: InviteRemoteStore, modelContext: ModelContext) {
        self.remote = remote
        self.modelContext = modelContext
    }
    
    /// Generates an invite for the currently active (first) local family.
    ///
    /// Output:
    /// - `code`: classic membership invite code (server-side, collision-safe).
    /// - `qrPayload`: crypto-wrapped invite payload + membership code (for QR).
    ///
    /// Notes:
    /// - This method is `@MainActor` to safely mutate published UI state.
    /// - Avoids `print` to keep logs structured and filterable in Console.
    func generateInviteCode() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        
        KBLog.sync.info("InviteCodeVM: generateInviteCode started")
        
        do {
            // Fetch the first available family (current app model: single active family).
            let families = try modelContext.fetch(FetchDescriptor<KBFamily>())
            guard let family = families.first else {
                errorMessage = "Nessuna family trovata."
                KBLog.sync.error("InviteCodeVM: no local family found")
                return
            }
            
            let familyId = family.id
            KBLog.sync.info("InviteCodeVM: using familyId=\(familyId, privacy: .public)")
            
            // 1) Create membership invite code (classic join)
            KBLog.sync.info("InviteCodeVM: creating membership code")
            let newCode = try await remote.createInviteCode(familyId: familyId)
            code = newCode
            KBLog.sync.info("InviteCodeVM: membership code created code=\(newCode, privacy: .public)")
            
            // 2) Create crypto-wrapped invite (includes encryption key material)
            KBLog.sync.info("InviteCodeVM: creating encrypted invite")
            let invite = try await InviteWrapService().createInvite(
                familyId: familyId,
                ttlSeconds: 24 * 3600
            )
            KBLog.sync.info("InviteCodeVM: encrypted invite created inviteId=\(invite.inviteId, privacy: .public)")
            
            // 3) QR payload contains BOTH:
            //    - crypto invite payload (familyId, inviteId, secret, etc.)
            //    - membership code (for join index / membership flow)
            //
            // Security note:
            // - Do NOT log secrets / full QR payload. Only log metadata.
            qrPayload = invite.qrPayload + "&code=\(newCode)"
            KBLog.sync.info("InviteCodeVM: qr payload ready familyId=\(familyId, privacy: .public) inviteId=\(invite.inviteId, privacy: .public)")
            
        } catch {
            errorMessage = error.localizedDescription
            KBLog.sync.error("InviteCodeVM: generateInviteCode failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Copies the membership invite code (not the QR payload) to the clipboard.
    ///
    /// - Note: This is a UI convenience; the QR flow should be preferred for key transfer.
    func copyToClipboard() {
        guard let code else {
            KBLog.sync.debug("InviteCodeVM: copyToClipboard ignored (no code)")
            return
        }
#if canImport(UIKit)
        UIPasteboard.general.string = code
        KBLog.sync.info("InviteCodeVM: code copied to clipboard")
#endif
    }
    
    /// Human-friendly share text containing only the membership code.
    ///
    /// - Important: This intentionally does NOT include `qrPayload` (which contains key material).
    var shareText: String {
        guard let code else { return "" }
        return "KidBox — codice invito: \(code)"
    }
}
