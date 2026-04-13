//
//  FamilyLeaveService.swift
//  KidBox
//
//  Created by vscocca on 10/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftData

/// Service responsible for removing the current user from a family and wiping local family data.
///
/// Flow (unchanged):
/// 1) Ensure authenticated
/// 2) Block sync locally (beginLocalWipe)
/// 3) Stop realtime listeners
/// 4) Yield briefly to let pending snapshots settle
/// 5) Server: remove member doc `families/{familyId}/members/{uid}`
/// 6) Local: wipe family data
/// 7) Optional: remove membership index `users/{uid}/memberships/{familyId}`
/// 8) Save modelContext
/// 9) Re-enable sync (endLocalWipe)
/// 10) Flush global sync
///
/// Notes:
/// - Runs on MainActor due to SwiftData `ModelContext` usage and UI-adjacent calls.
/// - If a step throws, subsequent steps won't run (same behavior as current code).
@MainActor
final class FamilyLeaveService {
    
    private let db = Firestore.firestore()
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Leaves the specified family and wipes related local data.
    func leaveFamily(familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("leaveFamily failed: not authenticated")
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbInfo("leaveFamily started familyId=\(familyId)")
        
        // 0) Block if user is the only member (would orphan the family in the cloud)
        let fid = familyId
        let memberDesc = FetchDescriptor<KBFamilyMember>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        )
        let memberCount = (try? modelContext.fetch(memberDesc).count) ?? 0
        if memberCount <= 1 {
            KBLog.sync.kbError("leaveFamily blocked: user is the only member")
            throw NSError(domain: "KidBox", code: -5, userInfo: [
                NSLocalizedDescriptionKey: "Sei l'unico membro della famiglia. Eliminala prima di uscire."
            ])
        }
        
        // 1) Block sync
        KBLog.sync.kbInfo("beginLocalWipe")
        SyncCenter.shared.beginLocalWipe()
        
        // 2) Stop listeners first to avoid re-populating while wiping
        KBLog.sync.kbInfo("Stopping realtime listeners before wipe")
        SyncCenter.shared.stopFamilyBundleRealtime()
        
        // 3) Small yield for pending snapshots
        KBLog.sync.kbDebug("Yielding briefly to let pending snapshots settle")
        try await Task.sleep(nanoseconds: 150_000_000) // 150 ms
        
        // 4) Server: remove member document
        KBLog.sync.kbInfo("Removing member doc from Firestore")
        try await db
            .collection("families")
            .document(familyId)
            .collection("members")
            .document(uid)
            .delete()
        
        // 5) Local wipe family
        KBLog.persistence.kbInfo("Wiping local family data")
        try LocalDataWiper.wipeFamily(
            familyId: familyId,
            context: modelContext
        )
        
        // 6) Optional membership index removal
        KBLog.sync.kbDebug("Removing membership index (best effort)")
        try? await db
            .collection("users")
            .document(uid)
            .collection("memberships")
            .document(familyId)
            .delete()
        
        // Persist local changes
        try modelContext.save()
        KBLog.persistence.kbInfo("Local wipe committed")
        
        // 7) Re-enable sync
        KBLog.sync.kbInfo("endLocalWipe")
        SyncCenter.shared.endLocalWipe()
        
        // 8) Flush sync
        KBLog.sync.kbInfo("flushGlobal after leaveFamily")
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        KBLog.sync.kbInfo("leaveFamily completed familyId=\(familyId)")
    }

    // Trasferisce ownership a newOwnerUid poi fa leave del caller
    func transferOwnershipAndLeave(familyId: String, newOwnerUid: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1)
        }
        let batch = db.batch()
        let familyRef = db.collection("families").document(familyId)
        batch.updateData([
            "ownerUid": newOwnerUid,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: familyRef)
        batch.updateData([
            "role": "owner",
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: familyRef.collection("members").document(newOwnerUid))
        batch.updateData([
            "role": "member",
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: familyRef.collection("members").document(uid))
        try await batch.commit()
        try await leaveFamily(familyId: familyId)
    }

    // Elimina la famiglia completamente
    func deleteFamily(familyId: String) async throws {
        KBLog.sync.kbInfo("deleteFamily started familyId=\(familyId)")

        // 1) Call Cloud Function (best effort, non-blocking)
        Task {
            do {
                let functions = Functions.functions(region: "europe-west1")
                _ = try await functions.httpsCallable("deleteFamily").call(["familyId": familyId])
                KBLog.sync.kbInfo("deleteFamily CF OK familyId=\(familyId)")
            } catch {
                KBLog.sync.kbError("deleteFamily CF failed (non-fatal): \(error.localizedDescription)")
            }
        }

        // 2) Local wipe immediately, don't wait for CF
        try wipeFamilyLocalOnly(familyId: familyId)

        KBLog.sync.kbInfo("deleteFamily completed familyId=\(familyId)")
    }
    
    /// Pulisce **solo** SwiftData e ferma i listener. Nessuna chiamata di rete (né Cloud Function).
    /// Per eliminare la famiglia sul server usare `deleteFamily(familyId:)`.
    func wipeFamilyLocalOnly(familyId: String) throws {
        KBLog.sync.kbInfo("wipeFamilyLocalOnly started familyId=\(familyId) (local only, no server)")

        SyncCenter.shared.beginLocalWipe()
        
        SyncCenter.shared.stopMembersRealtime()
        SyncCenter.shared.stopTodoRealtime()
        SyncCenter.shared.stopChildrenRealtime()
        SyncCenter.shared.stopFamilyBundleRealtime()
        SyncCenter.shared.stopDocumentsRealtime()
        
        try LocalDataWiper.wipeFamily(familyId: familyId, context: modelContext)
        try modelContext.save()
        
        SyncCenter.shared.endLocalWipe()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        KBLog.sync.kbInfo("wipeFamilyLocalOnly completed familyId=\(familyId)")
    }
}
