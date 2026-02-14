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

/// Creates a new family locally (SwiftData) and then best-effort creates it remotely (Firestore).
///
/// Responsibilities:
/// - Generate ids for family + first child.
/// - Persist both entities locally and link the relationship (`child.family = family`).
/// - Trigger a **best-effort** remote creation (detached task) so UI is not blocked.
///
/// Notes:
/// - This service is `@MainActor` because it mutates SwiftData (`ModelContext`).
/// - Remote write happens in a detached task exactly as before (logic unchanged).
@MainActor
final class FamilyCreationService {
    
    // MARK: - Dependencies
    
    private let remote: FamilyRemoteStore
    private let modelContext: ModelContext
    
    /// Creates a `FamilyCreationService` with required dependencies.
    init(remote: FamilyRemoteStore, modelContext: ModelContext) {
        self.remote = remote
        self.modelContext = modelContext
        KBLog.data.kbDebug("FamilyCreationService init")
    }
    
    // MARK: - Public API
    
    /// Creates a family and its first child.
    ///
    /// Behavior (unchanged):
    /// - Requires authenticated user.
    /// - Creates local `KBFamily` and `KBChild` with generated UUIDs.
    /// - Inserts both in SwiftData and links `child.family = family`.
    /// - Saves local context.
    /// - Starts a detached best-effort remote create.
    ///
    /// - Returns: Tuple `(familyId, childId)` for navigation / follow-up actions.
    func createFamily(
        name: String,
        childName: String,
        childBirthDate: Date?
    ) async throws -> (familyId: String, childId: String) {
        
        KBLog.data.kbInfo("createFamily start nameLen=\(name.count) childNameLen=\(childName.count)")
        
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("createFamily failed: not authenticated")
            throw NSError(domain: "KidBox", code: -1)
        }
        
        let familyId = UUID().uuidString
        let childId = UUID().uuidString
        let now = Date()
        
        KBLog.data.kbDebug("createFamily generated ids familyId=\(familyId) childId=\(childId)")
        
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
        
        // ✅ NO array append (unchanged)
        modelContext.insert(family)
        modelContext.insert(child)
        child.family = family
        
        try modelContext.save()
        
        KBLog.data.kbInfo("Local family created familyId=\(familyId) childId=\(childId)")
        
        // REMOTE best-effort (non bloccare UI) (unchanged)
        Task.detached { [remote] in
            await KBLog.sync.kbDebug("Remote family create started familyId=\(familyId)")
            do {
                try await remote.createFamilyWithChild(
                    family: .init(id: familyId, name: name, ownerUid: uid),
                    child: .init(id: childId, name: childName, birthDate: childBirthDate)
                )
                await KBLog.sync.kbInfo("Remote family create completed familyId=\(familyId)")
            } catch {
                await KBLog.sync.kbError("Remote family create failed: \(error.localizedDescription)")
            }
        }
        
        KBLog.data.kbDebug("createFamily done returning ids familyId=\(familyId) childId=\(childId)")
        return (familyId, childId)
    }
}
