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
    
    // Impostato a true da ChatViewModel durante la registrazione.
    // Blocca overrideOutputAudioPort mentre AVAudioRecorder è attivo:
    // chiamarlo durante recording causa err=-19431 (kAudioSessionIncompatibleCategory)
    // su alcuni dispositivi (es. iPhone 14), invalidando la sessione audio
    // e impedendo la scrittura dei dati sul file.
    // Quando viene reimpostato a false, applica l'eventuale override in sospeso.
    var isRecordingActive: Bool = false {
        didSet {
            guard !isRecordingActive, let pending = pendingOverride else { return }
            pendingOverride = nil
            applyOverride(pending)
        }
    }
    
    // Override richiesto mentre isRecordingActive era true.
    // Viene applicato non appena isRecordingActive torna false.
    private var pendingOverride: AVAudioSession.PortOverride? = nil
    
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
        pendingOverride = nil
        
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.proximityStateDidChangeNotification,
            object: nil
        )
        UIDevice.current.isProximityMonitoringEnabled = false
    }
    
    @objc private func onProximityChanged() {
        let port: AVAudioSession.PortOverride = UIDevice.current.proximityState ? .none : .speaker
        
        // Non toccare la sessione audio mentre si sta registrando.
        // Salva l'override come pending: verrà applicato al termine
        // della registrazione tramite il didSet di isRecordingActive.
        guard !isRecordingActive else {
            pendingOverride = port
            return
        }
        
        applyOverride(port)
    }
    
    private func applyOverride(_ port: AVAudioSession.PortOverride) {
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(port)
        } catch {
            // silenzioso: il routing è best-effort
        }
    }
}
