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
            
            let newCode = try await remote.createInviteCode(familyId: family.id)
            code = newCode
        } catch {
            errorMessage = error.localizedDescription
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
        return "KidBox – codice invito: \(code)"
    }
}
