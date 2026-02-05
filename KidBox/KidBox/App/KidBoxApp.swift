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
import FirebaseAuth

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
            .onChange(of: coordinator.path) { _, newValue in
                KBLog.navigation.debug("NavigationStack observed path: \(newValue.count, privacy: .public)")
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
            .onAppear {
                let context = modelContainer.mainContext
                
#if DEBUG
                // Seed SOLO se non c’è un utente Firebase loggato
                // (evita che Apple/Google vedano sempre "Famiglia Rossi")
                if Auth.auth().currentUser == nil {
                    DebugSeeder.seedIfNeeded(context: context)
                } else {
                    KBLog.persistence.info("DEBUG seed skipped (authenticated user)")
                }
#endif
            }
            .task {
                #if DEBUG
                FirestorePingService().ping { _ in }
                #endif
            }
        }
        .modelContainer(modelContainer)
        
    }
}
