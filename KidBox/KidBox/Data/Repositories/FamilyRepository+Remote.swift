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
    
    func createFamily(name: String, childName: String, childBirthDate: Date?) async throws -> (familyId: String, childId: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1)
        }
        // 1) crea IDs
        let familyId = UUID().uuidString
        let childId = UUID().uuidString
        
        // 2) LOCAL: crea modelli SwiftData (usa i tuoi modelli reali)
        // Qui assumo che tu abbia KBFamily e KBChild; se i nomi differiscono, me li dici e lo adatto.
        let family = KBFamily(
            id: familyId,
            name: name,
            createdBy: uid,
            updatedBy: uid,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let child = KBChild(
            id: childId,
            familyId: familyId,
            name: childName,
            birthDate: childBirthDate,
            createdBy: uid,
            createdAt: Date(),
            updatedBy: uid,
            updatedAt: Date()
        )
        
        family.children.append(child)
        
        modelContext.insert(family)
        try modelContext.save()
        
        KBLog.data.info("Local family created id=\(familyId, privacy: .public)")
        
        // 3) REMOTE: sync Firestore
        do {
            try await remote.createFamilyWithChild(
                family: .init(id: familyId, name: name, ownerUid: uid),
                child: .init(id: childId, name: childName, birthDate: childBirthDate)
            )
        } catch {
            KBLog.sync.error("Remote family create failed: \(error.localizedDescription, privacy: .public)")
            // MVP: non rollback locale. In futuro: retry queue / outbox.
        }
        
        return (familyId, childId)
    }
}
