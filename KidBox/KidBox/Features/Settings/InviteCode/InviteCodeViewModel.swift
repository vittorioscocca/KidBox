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
    
    func generateInviteCode() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        
        do {
            let families = try modelContext.fetch(FetchDescriptor<KBFamily>())
            guard let family = families.first else {
                errorMessage = "Nessuna family trovata."
                return
            }
            
            let familyId = family.id
            
            // 1️⃣ Crea codice membership (per il join classico)
            print("📝 Creating membership code for family: \(familyId)")
            let newCode = try await remote.createInviteCode(familyId: familyId)
            code = newCode
            print("✅ Membership code created: \(newCode)")
            
            // 2️⃣ Crea invito crypto-wrapped (con la chiave)
            print("🔑 Creating encrypted invite for family: \(familyId)")
            let invite = try await InviteWrapService().createInvite(
                familyId: familyId,
                ttlSeconds: 24 * 3600
            )
            print("✅ Encrypted invite created: \(invite.inviteId)")
            
            // 3️⃣ QR payload contiene ENTRAMBI
            // - familyId, inviteId, secret (per decifrare la chiave)
            // - code (per il join membership)
            qrPayload = invite.qrPayload + "&code=\(newCode)"
            print("✅ QR payload generated with both code and encrypted key")
            print("📊 QR content:")
            print("   - familyId: \(familyId)")
            print("   - inviteId: \(invite.inviteId)")
            print("   - secret: [32 bytes]")
            print("   - code: \(newCode)")
            
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Generate invite failed: \(error.localizedDescription)")
        }
    }
    
    func copyToClipboard() {
        guard let code else { return }
#if canImport(UIKit)
        UIPasteboard.general.string = code
#endif
    }
    
    var shareText: String {
        guard let code else { return "" }
        return "KidBox — codice invito: \(code)"
    }
}


