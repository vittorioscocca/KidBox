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
        // Percorso "crea": la KBFamily viene inserita localmente già a pagina 4 (e pinnata come
        // active family) prima della pagina QR. Senza questo guard `pinnedFamilyReadyInStore`
        // diventa subito true e manderebbe l'utente in Home saltando la pagina del QR.
        // Resta nel walkthrough finché l'utente non finisce (→ completeOnboarding azzera il flag).
        if coordinator.isCreatingFamilyInOnboarding { return false }
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
                #if targetEnvironment(macCatalyst)
                MacShellView()
                #else
                HomeView()
                #endif
            } else {
                OnboardingWalkthroughView {
                    coordinator.completeOnboarding()
                    coordinator.resetToRoot()
                }
            }
        }
        // Su Mac Catalyst i Button che non dichiarano uno stile usano lo stile
        // `.automatic`, reso come un riquadro grigio/traslucido arrotondato
        // (il "bezel" AppKit) che appare dietro i pulsanti circolari/a pillola
        // — vedi FAB, chevron, pill posizione. Impostando `.plain` come stile
        // di default per tutto l'albero, solo i pulsanti che si affidano allo
        // stile di default (quelli col bezel) cambiano: i pulsanti con uno
        // `.buttonStyle` esplicito lo sovrascrivono e restano invariati.
        // Disabilitiamo anche l'hover effect rettangolare del puntatore.
        // Sheet e fullScreenCover ereditano l'ambiente.
        #if targetEnvironment(macCatalyst)
        .buttonStyle(.plain)
        .hoverEffectDisabled()
        #endif
        .onAppear {
            KBLog.navigation.kbDebug("RootGateView appeared")
        }
        .onChange(of: coordinator.isAuthenticated) { _, newValue in
            KBLog.navigation.kbInfo("Auth state changed: \(newValue)")
        }
        /// Quando SwiftData riceve la famiglia dopo join ma `hasSeenOnboarding` è ancora false, completa l’onboarding così non si resta bloccati sul walkthrough.
        /// NB: nel percorso "crea" la KBFamily viene inserita localmente già a pagina 4, prima
        /// della pagina QR; `isCreatingFamilyInOnboarding` evita che questo auto-complete scatti
        /// in quel caso e salti la pagina del QR. Resta attivo solo per il flusso join.
        .task(id: families.map(\.id).joined(separator: "|")) {
            guard !coordinator.hasSeenOnboarding,
                  !coordinator.isCreatingFamilyInOnboarding,
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
