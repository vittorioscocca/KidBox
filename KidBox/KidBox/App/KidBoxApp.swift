//
//  KidBoxApp.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI
import SwiftData
import OSLog
import GoogleSignIn

@main
struct KidBoxApp: App {
    private var modelContainer = ModelContainerProvider.makeContainer(inMemory: false)
    @StateObject private var coordinator = AppCoordinator()
    
    init() {
        FirebaseBootstrap.configureIfNeeded()
        KBLog.app.info("KidBoxApp init")
        
        self.modelContainer = ModelContainerProvider.makeContainer(inMemory: false)
        KBLog.app.info("KidBoxApp ready")
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $coordinator.path) {
                coordinator.makeRootView()
                    .navigationDestination(for: Route.self) { coordinator.makeDestination(for: $0) }
            }
            .environmentObject(coordinator)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
        .modelContainer(modelContainer)
        
    }
}
