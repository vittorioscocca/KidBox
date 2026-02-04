//
//  KidBoxApp.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI
import SwiftData
import OSLog

@main
struct KidBoxApp: App {
    private let modelContainer = ModelContainerProvider.makeContainer(inMemory: false)
    
    init() {
        KBLog.app.info("KidBoxApp init")
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
