//
//  RootGateView.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

//
//  RootGateView.swift
//  KidBox
//
//  Root authentication gate.
//  Decides whether to show LoginView or HomeView.
//

import SwiftUI
import SwiftData

struct RootGateView: View {
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    /// Usato per ingresso diretto in Home dopo join: DB ha una famiglia e coincide con `activeFamilyId`.
    @Query(sort: \KBFamily.updatedAt, order: .reverse)
    private var families: [KBFamily]
    
    /// `activeFamilyId` valorizzato **e** `KBFamily` corrispondente già in SwiftData (post-join / QR).
    private var pinnedFamilyReadyInStore: Bool {
        guard let fid = coordinator.activeFamilyId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fid.isEmpty else { return false }
        return families.contains { $0.id == fid }
    }

    /// Any local family already available in SwiftData.
    private var hasAnyLocalFamily: Bool {
        !families.isEmpty
    }
    
    /// Mostra la Home se onboarding completato **oppure** c’è una famiglia attiva coerente nel DB (nessuna lista selezione dopo join).
    private var shouldShowHome: Bool {
        if coordinator.hasSeenOnboarding { return true }
        return pinnedFamilyReadyInStore || hasAnyLocalFamily
    }
    
    var body: some View {
        Group {
            if coordinator.isCheckingAuth {
                // Firebase non ha ancora risposto — mostra sfondo arancione
                // per evitare il flash della login screen
                Color(red: 0.95, green: 0.38, blue: 0.10)
                    .ignoresSafeArea()
            } else if !coordinator.isAuthenticated {
                LoginView()
            } else if shouldShowHome {
                HomeView()
            } else {
                OnboardingWalkthroughView {
                    coordinator.completeOnboarding()
                    coordinator.resetToRoot()
                }
            }
        }
        .onAppear {
            KBLog.navigation.kbDebug("RootGateView appeared")
        }
        .onChange(of: coordinator.isAuthenticated) { _, newValue in
            KBLog.navigation.kbInfo("Auth state changed: \(newValue)")
        }
        /// Quando SwiftData riceve la famiglia dopo join ma `hasSeenOnboarding` è ancora false, completa l’onboarding così non si resta bloccati sul walkthrough.
        .task(id: families.map(\.id).joined(separator: "|")) {
            guard !coordinator.hasSeenOnboarding,
                  hasAnyLocalFamily else { return }
            coordinator.completeOnboarding()
            KBLog.navigation.kbInfo("RootGateView: completeOnboarding after joined family present in store")
        }
        .onChange(of: coordinator.activeFamilyId) { _, newId in
            KBLog.navigation.kbDebug("RootGateView: activeFamilyId=\(newId ?? "nil") pinnedReady=\(pinnedFamilyReadyInStore)")
        }
        .task {
            KBLog.navigation.kbDebug("Starting session listener")
            coordinator.startSessionListener(modelContext: modelContext)
        }
    }
}
