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
    case location
    case todos
    case shopping  // ← NEW
    case notes     // ← NEW
    case calendar
    case expenses  // ← NEW
    case wallet    // ← NEW (biglietti Wallet)
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
            
            KBLog.sync.kbDebug("Counters reset ok familyId=\(familyId) field=\(field.rawValue)")
        } catch {
            KBLog.sync.kbError("Counters reset FAILED familyId=\(familyId) field=\(field.rawValue) err=\(error.localizedDescription)")
        }
    }
}
