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
            KBLog.app.debug("Firebase already configured")
            return
        }
        
        let plistName: String
        #if DEBUG
        plistName = "GoogleService-Info-Debug"
        #else
        plistName = "GoogleService-Info-Release"
        #endif
        
        guard let path = Bundle.main.path(forResource: plistName, ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            KBLog.app.fault("Missing Firebase plist: \(plistName, privacy: .public).plist")
            return
        }
        
        FirebaseApp.configure(options: options)
        KBLog.app.info("Firebase configured using \(plistName, privacy: .public)")
    }
}
