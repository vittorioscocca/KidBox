//
//  FirestorePingService..swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import FirebaseFirestore
internal import os

final class FirestorePingService {
    
    /// Firestore instance resolved at call time (after Firebase configuration).
    private lazy var db = Firestore.firestore()
    
    func ping(completion: @escaping (Result<Void, Error>) -> Void) {
        db.collection("diagnostics").document("ping").setData([
            "ts": FieldValue.serverTimestamp(),
            "client": "KidBox"
        ], merge: true) { error in
            if let error {
                KBLog.sync.error("Firestore ping failed: \(error.localizedDescription, privacy: .public)")
                completion(.failure(error))
            } else {
                KBLog.sync.info("Firestore ping OK")
                completion(.success(()))
            }
        }
    }
}
