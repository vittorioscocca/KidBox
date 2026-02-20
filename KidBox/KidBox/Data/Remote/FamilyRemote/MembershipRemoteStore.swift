//
//  MembershipRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

/// Read model for a membership entry in `users/{uid}/memberships/{familyId}`.
struct RemoteMembershipRead {
    let familyId: String
    let role: String
}

/// Remote store responsible for reading the current user's family memberships.
///
/// Data source:
/// - `users/{uid}/memberships/*`
///
/// Notes:
/// - Requires an authenticated Firebase user.
final class MembershipRemoteStore {
    
    /// Firestore handle (computed as in original code).
    private var db: Firestore { Firestore.firestore() }
    
    /// Convenience wrapper that fetches memberships for the currently authenticated user.
    ///
    /// Behavior (unchanged): delegates to `fetchMemberships()`.
    func fetchMembershipsForCurrentUser() async throws -> [RemoteMembershipRead] {
        KBLog.sync.kbDebug("fetchMembershipsForCurrentUser start")
        let items = try await fetchMemberships()
        KBLog.sync.kbDebug("fetchMembershipsForCurrentUser done count=\(items.count)")
        return items
    }
    
    /// Fetches membership documents from Firestore for the current user.
    ///
    /// Behavior (unchanged):
    /// - Requires authenticated user.
    /// - Reads `users/{uid}/memberships`.
    /// - Maps each document to `RemoteMembershipRead` using:
    ///   - `familyId = documentID`
    ///   - `role = d["role"] ?? "member"`
    func fetchMemberships() async throws -> [RemoteMembershipRead] {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("fetchMemberships failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        KBLog.sync.kbInfo("fetchMemberships start")
        
        let qs = try await db.collection("users")
            .document(uid)
            .collection("memberships")
            .getDocuments()
        
        let items: [RemoteMembershipRead] = qs.documents.compactMap { doc in
            let d = doc.data()
            let role = (d["role"] as? String) ?? "member"
            return RemoteMembershipRead(familyId: doc.documentID, role: role)
        }
        
        KBLog.sync.kbInfo("fetchMemberships done count=\(items.count)")
        return items
    }
}
