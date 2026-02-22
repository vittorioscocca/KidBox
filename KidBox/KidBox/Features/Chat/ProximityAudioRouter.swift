//
//  ProximityAudioRouter.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//

import UIKit
import AVFoundation

final class ProximityAudioRouter {
    private var isEnabled = false
    
    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        
        UIDevice.current.isProximityMonitoringEnabled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onProximityChanged),
            name: UIDevice.proximityStateDidChangeNotification,
            object: nil
        )
    }
    
    func stop() {
        guard isEnabled else { return }
        isEnabled = false
        
        NotificationCenter.default.removeObserver(self, name: UIDevice.proximityStateDidChangeNotification, object: nil)
        UIDevice.current.isProximityMonitoringEnabled = false
    }
    
    @objc private func onProximityChanged() {
        let session = AVAudioSession.sharedInstance()
        
        do {
            if UIDevice.current.proximityState {
                // ✅ vicino all’orecchio -> auricolare
                try session.overrideOutputAudioPort(.none)
            } else {
                // ✅ lontano -> speaker
                try session.overrideOutputAudioPort(.speaker)
            }
        } catch {
            // log se vuoi
        }
    }
}
