//
//  SyncCenter+Trips.swift
//  KidBox
//

import Foundation
import SwiftData
import FirebaseFirestore

extension SyncCenter {

    func startTripsRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startTripsRealtime familyId=\(familyId)")
        stopTripsRealtime()

        tripsListener = tripRemote.listenTrips(
            familyId: familyId,
            modelContext: modelContext,
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "trips", error: err)
                    }
                } else {
                    KBLog.sync.kbError("Trips realtime error: \(err.localizedDescription)")
                }
            }
        )
    }

    func stopTripsRealtime() {
        if tripsListener != nil {
            KBLog.sync.kbInfo("stopTripsRealtime")
        }
        tripsListener?.remove()
        tripsListener = nil
    }
}
