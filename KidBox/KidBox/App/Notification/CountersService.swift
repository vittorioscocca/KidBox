//
//  CountersService.swift
//  KidBox
//
//  Created by vscocca on 24/02/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

enum CountersField: String {
    case chat
    case documents
}

final class CountersService {
    static let shared = CountersService()
    private init() {}
    
    private let db = Firestore.firestore()
    
    func reset(familyId: String, field: CountersField) async {
        guard !familyId.isEmpty else { return }
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("counters")
            .document(uid)
        
        do {
            try await ref.setData([
                field.rawValue: 0,
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
            
            KBLog.sync.debug("Counters reset ok familyId=\(familyId, privacy: .public) field=\(field.rawValue, privacy: .public)")
        } catch {
            KBLog.sync.error("Counters reset FAILED familyId=\(familyId, privacy: .public) field=\(field.rawValue, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
        }
    }
}
