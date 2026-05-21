//
//  FirebaseBootstrap.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import FirebaseCore
import OSLog

/// Bootstraps Firebase using an environment-specific GoogleService-Info plist.
enum FirebaseBootstrap {
    
    /// Configures Firebase once at app startup.
    static func configureIfNeeded() {
        guard FirebaseApp.app() == nil else {
            KBLog.app.kbDebug("Firebase already configured")
            return
        }
        
        let plistName: String
        plistName = "GoogleService-Info"
        
        guard let path = Bundle.main.path(forResource: plistName, ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            KBLog.app.kbCrash("Missing Firebase plist: \(plistName).plist")
            return
        }
        
        FirebaseApp.configure(options: options)
        KBLog.app.kbInfo("Firebase configured using \(plistName)")
    }
}
