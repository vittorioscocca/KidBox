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
    
    private let service: FamilyJoinService
    
    init(service: FamilyJoinService) {
        self.service = service
    }
    
    func join() async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return }
        
        isBusy = true
        errorMessage = nil
        didJoin = false
        defer { isBusy = false }
        
        do {
            try await service.joinFamily(code: trimmed)
            didJoin = true
        } catch {
            errorMessage = error.localizedDescription
            KBLog.sync.error("Join failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
