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

    /// Priming permesso notifiche mostrato una sola volta. La chiave in
    /// `UserDefaults` è la memoria: una volta deciso (sì o no) non si ripresenta.
    private static let didPrimePushKey = "kb_didPrimePush"
    @State private var showPushPriming = false
    
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

    /// Mostra la Home solo se esiste davvero una famiglia in SwiftData.
    ///
    /// `hasSeenOnboarding` **non** basta più a sbloccare la Home. Prima era la
    /// prima condizione e usciva subito con `true`: chi eliminava la famiglia o
    /// ne usciva restava dentro l'app senza famiglia, in una Home vuota da cui
    /// non si tornava più al wizard. Android non ha mai avuto il problema perché
    /// dopo l'uscita riavvia l'app e al riavvio controlla `!hasFamily`.
    ///
    /// La presenza in SwiftData è persistente, quindi al lancio di un utente con
    /// famiglia la Home compare subito: non c'è un lampeggio del wizard in attesa
    /// del sync.
    private var shouldShowHome: Bool {
        // Percorso "crea": la KBFamily viene inserita localmente già a pagina 4 (e pinnata come
        // active family) prima della pagina QR. Senza questo guard `pinnedFamilyReadyInStore`
        // diventa subito true e manderebbe l'utente in Home saltando la pagina del QR.
        // Resta nel walkthrough finché l'utente non finisce (→ completeOnboarding azzera il flag).
        if coordinator.isCreatingFamilyInOnboarding { return false }
        return pinnedFamilyReadyInStore || hasAnyLocalFamily
    }
    
    /// Decide se mostrare il priming: solo se non è mai stato deciso E il
    /// sistema non ha ancora uno stato (`.notDetermined`). Se l'utente ha già
    /// concesso o negato altrove (es. da un toggle in Impostazioni), non c'è
    /// niente da chiedere.
    @MainActor
    private func maybePresentPushPriming() async {
        guard !UserDefaults.standard.bool(forKey: Self.didPrimePushKey) else { return }
        await NotificationManager.shared.refreshAuthorizationStatus()
        if NotificationManager.shared.authorizationStatus == .notDetermined {
            showPushPriming = true
        } else {
            // Stato già deciso dal sistema: niente priming, e non riproporlo.
            UserDefaults.standard.set(true, forKey: Self.didPrimePushKey)
        }
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
                Group {
                    #if targetEnvironment(macCatalyst)
                    MacShellView()
                    #else
                    HomeView()
                    #endif
                }
                .fullScreenCover(isPresented: $showPushPriming) {
                    PushPrimingView { didAccept in
                        UserDefaults.standard.set(true, forKey: Self.didPrimePushKey)
                        showPushPriming = false
                        if didAccept {
                            // Solo qui parte la richiesta di sistema. Le
                            // preferenze per-categoria sono già tutte ON: il
                            // permesso di sistema è l'unico interruttore che
                            // mancava per farle valere.
                            Task { try? await NotificationManager.shared.enablePushNotificationsForCurrentUser() }
                        }
                    }
                }
                .task {
                    await maybePresentPushPriming()
                }
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
