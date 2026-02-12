//
//  FamilyRepository+Remote.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import SwiftData
import OSLog
import FirebaseAuth

@MainActor
final class FamilyCreationService {
    
    private let remote: FamilyRemoteStore
    private let modelContext: ModelContext
    
    init(remote: FamilyRemoteStore, modelContext: ModelContext) {
        self.remote = remote
        self.modelContext = modelContext
    }
    
    func createFamily(
        name: String,
        childName: String,
        childBirthDate: Date?
    ) async throws -> (familyId: String, childId: String) {
        
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1)
        }
        
        let familyId = UUID().uuidString
        let childId = UUID().uuidString
        let now = Date()
        
        let family = KBFamily(
            id: familyId,
            name: name,
            createdBy: uid,
            updatedBy: uid,
            createdAt: now,
            updatedAt: now
        )
        
        let child = KBChild(
            id: childId,
            familyId: familyId,
            name: childName,
            birthDate: childBirthDate,
            createdBy: uid,
            createdAt: now,
            updatedBy: uid,
            updatedAt: now
        )
        
        // ✅ NO array append
        modelContext.insert(family)
        modelContext.insert(child)
        child.family = family
        
        try modelContext.save()
        
        KBLog.data.info("Local family created id=\(familyId, privacy: .public)")
        
        // REMOTE best-effort (non bloccare UI)
        Task.detached { [remote] in
            do {
                try await remote.createFamilyWithChild(
                    family: .init(id: familyId, name: name, ownerUid: uid),
                    child: .init(id: childId, name: childName, birthDate: childBirthDate)
                )
            } catch {
                await KBLog.data.error("Remote family create failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        return (familyId, childId)
    }
}
