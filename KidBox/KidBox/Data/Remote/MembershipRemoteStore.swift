//
//  MembershipRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct RemoteMembershipRead {
    let familyId: String
    let role: String
}

final class MembershipRemoteStore {
    private var db: Firestore { Firestore.firestore() }
    
    func fetchMembershipsForCurrentUser() async throws -> [RemoteMembershipRead] {
        try await fetchMemberships()
    }
    
    func fetchMemberships() async throws -> [RemoteMembershipRead] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let qs = try await db.collection("users")
            .document(uid)
            .collection("memberships")
            .getDocuments()
        
        return qs.documents.compactMap { doc in
            let d = doc.data()
            let role = (d["role"] as? String) ?? "member"
            return RemoteMembershipRead(familyId: doc.documentID, role: role)
        }
    }
}
