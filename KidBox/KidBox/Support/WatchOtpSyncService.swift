//
//  WatchOtpSyncService.swift
//  KidBox
//

import Foundation
import WatchConnectivity

enum WatchOtpSyncService {
    static func sendOtpPayloadIfNeeded(entry: PasswordEntry) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState == .notActivated {
            session.activate()
        }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        guard let config = OtpKeychainStore.retrieveOtpConfig(elementID: entry.id) else {
            session.sendMessage(["hasOTP": false, "elementID": entry.id], replyHandler: nil, errorHandler: nil)
            return
        }
        let payload: [String: Any] = [
            "hasOTP": true,
            "elementID": entry.id,
            "secret": config["secret"] as? String ?? "",
            "period": config["period"] as? Int ?? 30,
            "digits": config["digits"] as? Int ?? 6,
            "algorithm": config["algorithm"] as? String ?? "SHA1"
        ]
        session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }
}
