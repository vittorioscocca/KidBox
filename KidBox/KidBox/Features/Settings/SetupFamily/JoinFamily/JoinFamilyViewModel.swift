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
    @Published var code: String = ""
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var didJoin = false
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
        didJoin = false
        defer {
            isBusy = false
            KBLog.sync.kbDebug("JoinFamilyViewModel join end didJoin=\(self.didJoin)")
        }
        
        do {
            try await service.joinFamily(code: trimmed, coordinator: coordinator)
            didJoin = true
            KBLog.sync.kbInfo("JoinFamilyViewModel join OK")
        } catch {
            errorMessage = error.localizedDescription
            KBLog.sync.kbError("JoinFamilyViewModel join failed: \(error.localizedDescription)")
        }
    }
}
