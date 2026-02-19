//
//  Untitled.swift
//  KidBox
//
//  Created by vscocca on 19/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftData

/// Service responsible for revoking another member's access to the family.
///
/// Only the family owner (family.createdBy == currentUid) can revoke members.
///
/// Flow:
/// 1) Verify caller is authenticated and is the owner
/// 2) Remove member doc          `families/{familyId}/members/{targetUid}`
/// 3) Remove membership index    `users/{targetUid}/memberships/{familyId}` (best effort)
/// 4) Mark member as deleted locally (so the list updates immediately)
/// 5) Save local context
///
/// Notes:
/// - Does NOT wipe the target user's local data (we have no way to reach another device).
///   The target will lose access on next app launch when listeners return 403.
/// - Runs on MainActor due to SwiftData usage.
@MainActor
final class FamilyRevokeService {
    
    private let db = Firestore.firestore()
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Revokes `targetUid` from `familyId`.
    /// - Throws if caller is not authenticated, not the owner, or the Firestore delete fails.
    func revokeMember(familyId: String, targetUid: String) async throws {
        guard let callerUid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("revokeMember failed: not authenticated")
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Fetch family to verify ownership
        let fid = familyId
        let familyDesc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
        guard let family = try modelContext.fetch(familyDesc).first else {
            throw NSError(domain: "KidBox", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Family not found locally"])
        }
        
        guard family.createdBy == callerUid else {
            KBLog.auth.kbError("revokeMember failed: caller is not owner")
            throw NSError(domain: "KidBox", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Solo l'owner può revocare i membri"])
        }
        
        guard targetUid != callerUid else {
            throw NSError(domain: "KidBox", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "Non puoi revocare te stesso"])
        }
        
        KBLog.sync.kbInfo("revokeMember started familyId=\(familyId) targetUid=\(targetUid)")
        
        // 1) Remove member document from Firestore
        try await db
            .collection("families")
            .document(familyId)
            .collection("members")
            .document(targetUid)
            .delete()
        
        KBLog.sync.kbInfo("revokeMember: member doc deleted")
        
        // 2) Remove membership index on the target user (best effort — we may lack permission)
        try? await db
            .collection("users")
            .document(targetUid)
            .collection("memberships")
            .document(familyId)
            .delete()
        
        KBLog.sync.kbDebug("revokeMember: membership index removed (best effort)")
        
        // 3) Mark member as deleted locally so the UI updates immediately
        let tid = targetUid
        let memberDesc = FetchDescriptor<KBFamilyMember>(
            predicate: #Predicate { $0.familyId == fid && $0.userId == tid }
        )
        if let localMember = try? modelContext.fetch(memberDesc).first {
            localMember.isDeleted = true
        }
        
        try modelContext.save()
        KBLog.sync.kbInfo("revokeMember completed familyId=\(familyId) targetUid=\(targetUid)")
    }
}
